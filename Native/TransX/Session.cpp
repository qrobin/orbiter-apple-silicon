#include "Session.h"
#include "WindowSearch.h"
#include "Flight.h"
#include "SolarSystem.h"
#include "transx.h"
#include "viewstate.h"
#include "shiplist.h"
#include "basefunction.h"
#include <stdexcept>
extern "C" void opcPostStep(double,double,double);
namespace native::transx {
struct Session::Impl {
    Flight &flight;
    std::unique_ptr<TransxMFD> mfd[3];
    basefunction *selectedBase=nullptr;
    std::unique_ptr<WindowSearch> search;
    Route searchRoute;
    SearchStatus searchStatus;
    Flight searchFlight;
    struct GraphRotation {double yaw=0,pitch=0;} rotation[3];
    explicit Impl(Flight &f):flight(f){
        bind(&f);mapfunction::getthemap();
        // Original map construction and background scheduling run on the main
        // thread. Build the small catalogue before constructing its MFD views.
        for(int i=0;i<256;++i)MFDFunction::donextaction();
        mfd[0]=std::make_unique<TransxMFD>(512,512,oapiGetFocusInterface(),0);
        mfd[1]=std::make_unique<TransxMFD>(512,512,oapiGetFocusInterface(),1);
        mfd[2]=std::make_unique<TransxMFD>(512,512,oapiGetFocusInterface(),2);
        for(int i=0;i<128;++i)opcPostStep(oapiGetSimTime(),0,oapiGetSimMJD());
    }
    ~Impl(){bind(&flight);for(auto &view:mfd)view.reset();shipptrs::destroyshipptrs();pendingInput()={};}
    TransxMFD &display(int d){bind(&flight);return *mfd[std::clamp(d,0,2)];}
};
Session::Session(Flight &f):impl(std::make_unique<Impl>(f)){}
Session::~Session()=default;
void Session::tick(){bind(&impl->flight);for(int i=0;i<8;++i)opcPostStep(oapiGetSimTime(),0,oapiGetSimMJD());}
Frame Session::frame(int display){
    auto &mfd=impl->display(display);oapi::Sketchpad s;Frame f;
    const auto &rotation=impl->rotation[std::clamp(display,0,2)];s.graphYaw=rotation.yaw;s.graphPitch=rotation.pitch;
    f.ready=mfd.Update(&s);f.commands=std::move(s.commands);
    auto *view=mfd.nativeView();f.stage=view->nativeStage();f.view=view->nativeMode();
    auto *variable=view->GetCurrVariable();if(!variable)return f;
    char name[80]={},help1[80]={},help2[80]={};variable->getname(name);f.selected=name;
    variable->gethelpstrings(help1,help2);f.help=std::string(help1)+" "+help2;
    auto *handler=view->GetVarhandler();
    for(int i=0;i<128;++i){auto *v=handler->getcurrent(view->nativeMode());if(!v)break;
        v->getname(name);f.variables.emplace_back(name);handler->setnextcurrent(view->nativeMode());
        if(handler->getcurrent(view->nativeMode())==variable)break;
    }
    return f;
}
void Session::rotateGraph(int display,double horizontalPoints,double verticalPoints){
    if(!std::isfinite(horizontalPoints)||!std::isfinite(verticalPoints))return;
    auto &r=impl->rotation[std::clamp(display,0,2)];
    r.yaw=std::remainder(r.yaw+horizontalPoints*.008,PI2);
    r.pitch=std::clamp(r.pitch+verticalPoints*.008,-PI*.49,PI*.49);
}
void Session::resetGraph(int display){impl->rotation[std::clamp(display,0,2)]={};}
void Session::button(int display,int index,bool held){
    if(index<0||index>=12)return;
    impl->display(display).ConsumeButton(index,held?PANEL_MOUSE_LBPRESSED:PANEL_MOUSE_LBDOWN);
    tick();
}
bool Session::selectVariable(int display,const std::string &name){
    auto *v=impl->display(display).nativeView();auto *handler=v->GetVarhandler();
    auto *initial=handler->getcurrent(v->nativeMode());
    for(int i=0;i<128;++i){auto *current=handler->getcurrent(v->nativeMode());if(!current)return false;
        char buffer[80]={};current->getname(buffer);if(name==buffer)return true;handler->setnextcurrent(v->nativeMode());
        if(handler->getcurrent(v->nativeMode())==initial)return false;
    }
    return false;
}
bool Session::enterValue(int display,const std::string &value){
    pendingInput()={};impl->display(display).ConsumeKeyBuffered(OAPI_KEY_E);
    auto input=pendingInput();pendingInput()={};if(!input.callback||value.size()>(size_t)input.maxLength)return false;
    std::vector<char> text(value.begin(),value.end());text.push_back(0);bool accepted=input.callback(nullptr,text.data(),input.data);tick();return accepted;
}
void Session::save(const std::string &path){
    FILE *file=fopen(path.c_str(),"w");if(!file)throw std::runtime_error("Cannot save TransX plan.");
    shipptrs::refreshsave();impl->display(0).WriteStatus(file);fclose(file);
}
void Session::load(const std::string &path){
    FILE *file=fopen(path.c_str(),"r");if(!file)throw std::runtime_error("Cannot open TransX plan.");
    Frame original[2]={frame(0),frame(1)};
    // A full Orbiter scenario has a focus Ship entry before the MFD block.
    // Start at TYPE TransX so the original module only sees its own status.
    char line[2048];long start=0;
    while(fgets(line,sizeof(line),file)){char type[80]={},key[80]={};if(sscanf(line,"%79s %79s",key,type)==2&&!strcasecmp(key,"TYPE")&&!strcasecmp(type,"TransX")){start=ftell(file);break;}}
    fseek(file,start,SEEK_SET);impl->display(0).ReadStatus(file);fclose(file);for(int i=0;i<128;++i)tick();
    impl->selectedBase=nullptr;
    int stages=impl->display(RouteDisplay).nativeView()->nativeState()->getnumfunctions();
    for(int d=0;d<2;++d){int stage=std::min(original[d].stage,stages);
        if(!displayView(d,stage,original[d].view))displayView(d,stage,2);}
}
bool Session::maneuverDirection(int display,VECTOR3 &direction){
    auto *view=impl->display(display).nativeView();return maneuverDirectionForStage(view->nativeStage(),direction);
}
bool Session::maneuverDirectionForStage(int stage,VECTOR3 &direction){
    auto *view=impl->display(RouteDisplay).nativeView();auto *base=view->nativeState()->getbasefn(stage);
    if(!base)return false;
    if(base->gethmajor()!=oapiGetFocusInterface()->GetSurfaceRef()||!base->nativeManeuverVector(&direction))return false;
    double magnitude=length(direction);
    if(!std::isfinite(magnitude)||magnitude<.1)return false;direction/=magnitude;return true;
}
int Session::stageCount(){return impl->display(RouteDisplay).nativeView()->nativeState()->getnumfunctions();}
int Session::selectedStage(){
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    for(int i=1;i<=state->getnumfunctions();++i)if(state->getbasefn(i)==impl->selectedBase)return i;
    impl->selectedBase=state->getbasefn(1);return impl->selectedBase?1:0;
}
bool Session::selectStage(int stage){
    auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(stage);
    if(!base)return false;impl->selectedBase=base;return true;
}
bool Session::stageInfo(int stage,StageInfo &info){
    auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(stage);if(!base)return false;
    char name[80]={};oapiGetObjectName(base->gethmajor(),name,sizeof(name));
    try{info.reference=findBody(name);}catch(...){return false;}
    auto &v=info.maneuver;base->nativeManeuverValues(&v.date,&v.prograde,&v.outward,&v.plane,&info.enabled);
    return std::isfinite(v.date)&&std::isfinite(v.prograde)&&std::isfinite(v.outward)&&std::isfinite(v.plane);
}
bool Session::setStageManeuver(int stage,const RouteValues &values){
    auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(stage);
    if(!base||!base->nativeSetManeuver(values.date,values.prograde,values.outward,values.plane))return false;
    for(int i=0;i<32;++i)tick();return true;
}
bool Session::stageTiming(int stage,BurnTiming &timing){
    StageInfo info;if(!stageInfo(stage,info)||!info.enabled)return false;
    auto &flight=impl->flight;auto &v=info.maneuver;
    timing.secondsToBurn=(v.date-(flight.mjd+flight.elapsed/86400.))*86400.;
    timing.deltaV=std::hypot(v.prograde,v.outward,v.plane);
    timing.propellant=flight.mass()*(1-std::exp(-timing.deltaV/ExhaustVelocity));
    double thrust=200000*(std::clamp(1-flight.glider.mainBalance,0.,1.)+std::clamp(1+flight.glider.mainBalance,0.,1.));
    timing.duration=thrust>0?timing.propellant/(thrust/ExhaustVelocity):0;
    timing.sufficientFuel=timing.propellant<=flight.fuel;
    return std::isfinite(timing.secondsToBurn)&&std::isfinite(timing.duration);
}
bool Session::alignStage(int stage){
    // Only the current stage has the vessel's actual, rather than predicted, state.
    VECTOR3 direction;if(stage!=1||impl->flight.rcs<=0||!maneuverDirectionForStage(stage,direction))return false;
    auto &flight=impl->flight;flight.clearAssist();flight.maneuverDirection={direction.x,direction.y,direction.z};
    flight.assist=Assist::Maneuver;flight.glider.rcsMode=1;return true;
}
bool Session::beginWindowSearch(const Route &route,std::string &error){
    if(!routeMatches(route)||!route.targetStage){error="Choose a route with a target first.";return false;}
    if(route.targetStage!=1&&route.ejectStage!=route.targetStage){error="This route starts with multiple escape stages; search is available after reaching the parent system.";return false;}
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    auto *departure=state->getbasefn(1),*target=state->getbasefn(route.targetStage);
    if(!departure||!target){error="TransX stages are not ready.";return false;}
    VECTOR3 v;departure->calculate(&v);target->calculate(&v);
    const auto &origin=route.ejectStage?target->getminororbit():departure->getcraftorbit();
    const auto &destination=target->gettargetorbit();
    auto leg=std::find_if(route.legs.begin(),route.legs.end(),[](const RouteLeg &item){return !item.escape;});
    if(leg==route.legs.end()){error="There is no target encounter to search.";return false;}
    try{impl->search=std::make_unique<WindowSearch>(impl->flight,leg->next,route.ejectStage!=0,origin,destination);}
    catch(const std::exception &exception){error=exception.what();return false;}
    impl->searchFlight=impl->flight;impl->searchRoute=route;impl->searchStatus={};
    impl->searchStatus.state=SearchState::Running;impl->searchStatus.message="Searching transfer windows for lowest estimated fuel use.";
    error.clear();return true;
}
void Session::cancelWindowSearch(){impl->search.reset();impl->searchStatus={};}
SearchStatus Session::windowSearchStatus()const{return impl->searchStatus;}
void Session::stepWindowSearch(size_t budget){
    if(!impl->search||impl->searchStatus.state!=SearchState::Running)return;
    auto fail=[&](const std::string &message){impl->searchStatus.state=SearchState::Failed;impl->searchStatus.message=message;impl->search.reset();};
    if(!routeMatches(impl->searchRoute)){fail("The TransX route changed while searching.");return;}
    impl->search->step(budget);impl->searchStatus.progress=impl->search->progress();
    if(impl->search->running())return;
    if(!impl->search->result()){std::string message=impl->search->error();fail(message);return;}
    auto solution=*impl->search->result();auto &flight=impl->flight;auto &start=impl->searchFlight;
    if(flight.reference!=start.reference||flight.mjd!=start.mjd||flight.mjd+flight.elapsed/86400.>=solution.burn.date){fail("Flight time or reference changed; search again from the current orbit.");return;}
    Elements orbit=start.orbit();Vector expectedPosition,expectedVelocity;orbit.PosVel(expectedPosition,expectedVelocity,flight.elapsed);
    if(expectedPosition.dist(flight.position)>1000||expectedVelocity.dist(flight.velocity)>1){fail("The spacecraft orbit changed during the search; search again.");return;}
    std::unique_ptr<FILE,decltype(&fclose)> backup(tmpfile(),&fclose);
    if(!backup){fail("Unable to preserve the existing TransX plan.");return;}
    frame(0);shipptrs::refreshsave();impl->display(0).WriteStatus(backup.get());
    if(fflush(backup.get())!=0||ftell(backup.get())<=0){fail("Unable to preserve the existing TransX plan.");return;}
    auto restore=[&](const std::string &message){rewind(backup.get());impl->display(0).ReadStatus(backup.get());
        for(int i=0;i<128;++i)tick();impl->selectedBase=nullptr;fail(message);};
    if((solution.hasTransfer&&!setRouteValues(impl->searchRoute,false,solution.transfer))||!setStageManeuver(1,solution.burn)){
        restore("TransX could not apply the candidate; the previous plan was restored.");return;
    }
    // Show the trajectory produced by the maneuver itself, including the
    // inherited escape, rather than a separate idealized ejection plan.
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    auto *departure=state->getbasefn(1),*target=state->getbasefn(impl->searchRoute.targetStage);
    if(!departure||!target){restore("The TransX stages changed; the previous plan was restored.");return;}
    departure->nativeSetInterceptSource(2);
    if(target!=departure)target->nativeSetInterceptSource(3);
    for(int i=0;i<256;++i)tick();
    target->nativeSeedIntercept(solution.arrivalMJD);
    for(int i=0;i<256;++i)tick();
    Approach approach;
    auto leg=std::find_if(impl->searchRoute.legs.begin(),impl->searchRoute.legs.end(),[](const RouteLeg &item){return !item.escape;});
    bool valid=leg!=impl->searchRoute.legs.end()&&routeApproach(impl->searchRoute,approach)&&
        approach.source==(target==departure?2:3)&&approach.mjd>solution.burn.date&&
        fabs(approach.mjd-solution.arrivalMJD)<30&&approach.relativeSpeed>0&&
        approach.distance<sphereOfInfluence(leg->next,approach.mjd)*.9;
    if(valid){
        const auto &destination=body(leg->next);double speed2=approach.relativeSpeed*approach.relativeSpeed;
        double h2=approach.distance*approach.distance*speed2,mu=destination.mu();
        double periapsis=h2/(mu*(1+sqrt(1+h2*speed2/(mu*mu))));
        double atmosphere=leg->next==BodyId::Earth?120000.:destination.atmosphereLimit;
        valid=std::isfinite(periapsis)&&periapsis>destination.radius+atmosphere;
    }
    if(!valid){restore("TransX did not confirm a safe encounter; the previous plan was restored.");return;}
    impl->searchStatus.state=SearchState::Complete;impl->searchStatus.progress=1;
    impl->searchStatus.arrivalMJD=solution.arrivalMJD;impl->searchStatus.departureDV=solution.departureDV;
    impl->searchStatus.captureDV=solution.captureDV;impl->searchStatus.missDistance=approach.distance;
    impl->searchStatus.message="Window applied. Review the TransX closest approach and the manual burn.";
    impl->search.reset();
}

bool Session::displayView(int display,int stage,int mode){
    if(stage<0||mode<1||mode>4)return false;
    if(!frame(display).ready)return false;
    auto *view=impl->display(display).nativeView();
    if(stage>view->nativeState()->getnumfunctions())return false;
    for(int i=0;i<64&&view->nativeStage()!=stage;++i){
        int before=view->nativeStage();button(display,before<stage?1:2);frame(display);
        if(view->nativeStage()==before)return false;
    }
    for(int i=0;i<5&&view->nativeMode()!=mode;++i){button(display,3);frame(display);}
    // Original TransX does not cycle to a future stage's maneuver view; the
    // native route editor can show that existing view directly.
    if(display==RouteDisplay&&mode==4&&view->nativeMode()!=mode){view->nativeSetMode(mode);frame(display);}
    return view->nativeStage()==stage&&view->nativeMode()==mode;
}
bool Session::routeView(int stage,int mode){return stage>0&&displayView(RouteDisplay,stage,mode);}

bool Session::createRoute(BodyId destination,Route &route,std::string &error){
    return createRoute(std::vector<BodyId>{destination},route,error);
}
bool Session::createRoute(const std::vector<BodyId> &waypoints,Route &route,std::string &error){
    const auto valid=[](BodyId id){return (int)id>=0&&(int)id<(int)BodyId::Count;};
    BodyId origin=impl->flight.reference;
    if(!valid(origin)||waypoints.empty()||waypoints.size()>12){error="Choose between one and twelve destinations.";return false;}
    BodyId previous=origin;
    for(auto destination:waypoints){
        if(!valid(destination)||destination==previous){error="Choose a different destination for each consecutive step.";return false;}
        previous=destination;
    }

    // Walk the original body hierarchy for each stop. Targeting a body opens
    // its next TransX stage before a subsequent escape or encounter.
    Route candidate;candidate.origin=origin;candidate.destination=waypoints.back();candidate.waypoints=waypoints;
    int stage=1;BodyId current=origin;
    for(size_t stop=0;stop<waypoints.size();++stop){
        BodyId destination=waypoints[stop];std::vector<BodyId> originPath,destinationPath;
        for(BodyId id=current;;id=body(id).parent){originPath.push_back(id);if(id==BodyId::Sun)break;}
        for(BodyId id=destination;;id=body(id).parent){destinationPath.push_back(id);if(id==BodyId::Sun)break;}
        BodyId common=BodyId::Sun;
        for(auto id:originPath)if(std::find(destinationPath.begin(),destinationPath.end(),id)!=destinationPath.end()){common=id;break;}
        while(current!=common){auto next=body(current).parent;candidate.legs.push_back({current,next,stage++,true});current=next;}
        std::vector<BodyId> descent;
        for(BodyId id=destination;id!=common;id=body(id).parent)descent.push_back(id);
        std::reverse(descent.begin(),descent.end());
        for(size_t i=0;i<descent.size();++i){
            if(!candidate.targetStage)candidate.targetStage=stage;
            candidate.legs.push_back({current,descent[i],stage,false});current=descent[i];
            if(i+1<descent.size()||stop+1<waypoints.size())++stage;
        }
    }

    Frame original[2]={frame(0),frame(1)};
    std::unique_ptr<FILE,decltype(&fclose)> backup(tmpfile(),&fclose);
    if(!backup){error="Unable to preserve the existing TransX plan.";return false;}
    shipptrs::refreshsave();impl->display(0).WriteStatus(backup.get());
    if(fflush(backup.get())!=0||ftell(backup.get())<=0){error="Unable to preserve the existing TransX plan.";return false;}
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    auto restoreViews=[&](){for(int d=0;d<2;++d){
        int oldStage=std::min(original[d].stage,state->getnumfunctions());
        if(!displayView(d,oldStage,original[d].view))displayView(d,oldStage,2);
    }};
    auto fail=[&](const char *message){
        rewind(backup.get());impl->display(0).ReadStatus(backup.get());
        for(int i=0;i<128;++i)tick();impl->selectedBase=nullptr;restoreViews();error=message;return false;
    };
    if(!state->nativeRestart())return fail("TransX could not start a new plan; the previous plan was restored.");
    for(int i=0;i<32;++i)tick();frame(RouteDisplay);
    for(size_t i=0;i<candidate.legs.size();++i){
        const auto &leg=candidate.legs[i];
        if(!routeView(leg.stage,2))return fail("TransX could not open the setup view; the previous plan was restored.");
        if(!selectVariable(RouteDisplay,"Select Target"))return fail("TransX target control is unavailable; the previous plan was restored.");
        if(!enterValue(RouteDisplay,leg.escape?"Escape":body(leg.next).name)){
            return fail("TransX rejected a route target; the previous plan was restored.");
        }
        frame(RouteDisplay);
        if(leg.escape||i+1<candidate.legs.size()){
            button(RouteDisplay,1);auto f=frame(RouteDisplay);
            if(f.stage!=leg.stage+1)return fail("TransX could not create the next stage; the previous plan was restored.");
        }
    }
    if(candidate.targetStage){
        routeView(candidate.targetStage,2);
        auto *base=state->getbasefn(candidate.targetStage);
        base->updateplan();
        if(base->getplanpointer()&&base->getplanpointer()->getplanid()==2)candidate.ejectStage=candidate.targetStage;
    }
    for(int i=0;i<64;++i)tick();
    restoreViews();
    impl->selectedBase=state->getbasefn(1);
    route=std::move(candidate);error.clear();return true;
}

bool Session::routeMatches(const Route &route){
    if(route.origin!=impl->flight.reference||route.legs.empty())return false;
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    const auto &last=route.legs.back();int expected=last.stage+(last.escape?1:0);
    int count=state->getnumfunctions();
    if(count!=expected){
        // FWD on the final target opens its arrival stage without changing the
        // route. Keep recognizing that common original-MFD workflow.
        if(last.escape||count!=expected+1)return false;
        auto *arrival=state->getbasefn(count);OBJHANDLE major=nullptr,minor=nullptr;
        if(!arrival||arrival->gethmajor()!=oapiGetGbodyByName(body(route.destination).name))return false;
        arrival->handlesfornextfunction(&major,&minor);if(major||minor)return false;
    }
    for(const auto &leg:route.legs){
        auto *base=state->getbasefn(leg.stage);if(!base||base->gethmajor()!=oapiGetGbodyByName(body(leg.center).name))return false;
        OBJHANDLE major=nullptr,minor=nullptr;base->handlesfornextfunction(&major,&minor);
        if(major!=oapiGetGbodyByName(body(leg.next).name)||
           (leg.escape?minor!=base->gethmajor():minor!=nullptr))return false;
    }
    if(route.ejectStage){
        auto *base=state->getbasefn(route.ejectStage);
        if(!base||!base->getplanpointer()||(base->getplanpointer()->getplanid()!=2&&base->getplanpointer()->getplanid()!=3))return false;
    }
    return true;
}

bool Session::currentRoute(Route &route){
    auto *state=impl->display(RouteDisplay).nativeView()->nativeState();
    int count=state->getnumfunctions();if(count<1||count>(int)BodyId::Count)return false;
    Route candidate;candidate.origin=impl->flight.reference;BodyId center=candidate.origin;
    for(int stage=1;stage<=count;++stage){
        auto *base=state->getbasefn(stage);
        if(!base||base->gethmajor()!=oapiGetGbodyByName(body(center).name))return false;
        OBJHANDLE major=nullptr,minor=nullptr;base->handlesfornextfunction(&major,&minor);
        if(!major){
            if(stage!=count||candidate.legs.empty())return false;
            break;
        }
        char name[80]={};oapiGetObjectName(major,name,sizeof(name));BodyId next;
        try{next=findBody(name);}catch(...){return false;}
        bool escape=minor==base->gethmajor();
        if((minor&&!escape)||(escape?body(center).parent!=next:body(next).parent!=center))return false;
        candidate.legs.push_back({center,next,stage,escape});
        if(!escape&&!candidate.targetStage){
            candidate.targetStage=stage;
            if(base->getplanpointer()&&(base->getplanpointer()->getplanid()==2||base->getplanpointer()->getplanid()==3))candidate.ejectStage=stage;
        }
        center=next;
    }
    if(candidate.legs.empty())return false;
    candidate.destination=center;
    for(size_t i=0;i<candidate.legs.size();++i){
        const auto &leg=candidate.legs[i];
        if(!leg.escape&&i+1<candidate.legs.size()&&candidate.legs[i+1].escape&&candidate.legs[i+1].center==leg.next)
            candidate.waypoints.push_back(leg.next);
    }
    if(candidate.waypoints.empty()||candidate.waypoints.back()!=center)candidate.waypoints.push_back(center);
    if(!routeMatches(candidate))return false;
    route=std::move(candidate);return true;
}

bool Session::routeValues(const Route &route,bool departure,RouteValues &values){
    if(!routeMatches(route))return false;
    int stage=departure?1:route.ejectStage,mode=departure?4:3;
    if(!stage||!routeView(stage,mode))return false;
    if(!departure){
        auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(stage);
        auto *sling=base?dynamic_cast<slingejectplan*>(base->getplanpointer()):nullptr;
        if(sling){VECTOR3 unused;base->calculate(&unused);auto *previous=base->getpreviousfunc();
            double inherited=previous&&previous->getplanpointer()?previous->getplanpointer()->getentryvelocity():0;
            sling->nativeEjectionValues(inherited,&values.date,&values.prograde,&values.outward,&values.plane);
            return std::isfinite(values.date)&&std::isfinite(values.prograde)&&std::isfinite(values.outward)&&std::isfinite(values.plane);}
    }
    auto *view=impl->display(RouteDisplay).nativeView();
    std::string previous=frame(RouteDisplay).selected;
    if(departure){
        if(!selectVariable(RouteDisplay,"Manoeuvre mode"))return false;
        auto *choice=dynamic_cast<MFDvardiscrete*>(view->GetCurrVariable());
        if(!choice)return false;
        if((int)*choice==0){values={oapiGetSimMJD(),0,0,0};selectVariable(RouteDisplay,previous);return true;}
    }
    auto read=[&](const char *name,double &out){
        if(!selectVariable(RouteDisplay,name))return false;
        auto *number=dynamic_cast<MFDvarfloat*>(view->GetCurrVariable());
        if(!number)return false;out=number->getvalue();return std::isfinite(out);
    };
    bool ok=read(departure?"Man. date":"Eject date",values.date)&&read("Prograde vel.",values.prograde)&&
            read("Outward vel.",values.outward)&&read("Ch. plane vel.",values.plane);
    selectVariable(RouteDisplay,previous);return ok;
}

bool Session::setRouteValues(const Route &route,bool departure,const RouteValues &values){
    if(!routeMatches(route)||!std::isfinite(values.date)||values.date<0||values.date>1e20||
       !std::isfinite(values.prograde)||fabs(values.prograde)>1e8||
       !std::isfinite(values.outward)||fabs(values.outward)>1e8||
       !std::isfinite(values.plane)||fabs(values.plane)>1e8)return false;
    int stage=departure?1:route.ejectStage,mode=departure?4:3;
    if(!stage||!routeView(stage,mode))return false;
    if(!departure){
        auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(stage);
        auto *sling=base?dynamic_cast<slingejectplan*>(base->getplanpointer()):nullptr;
        if(sling){if(!sling->nativeSetEjectionValues(values.date,values.prograde,values.outward,values.plane))return false;
            base->addaction(0);for(int i=0;i<32;++i)tick();return true;}
    }
    auto *view=impl->display(RouteDisplay).nativeView();std::string previous=frame(RouteDisplay).selected;
    if(departure){
        if(!selectVariable(RouteDisplay,"Manoeuvre mode"))return false;
        auto *choice=dynamic_cast<MFDvardiscrete*>(view->GetCurrVariable());if(!choice)return false;
        if((int)*choice==0){button(RouteDisplay,8);frame(RouteDisplay);}
    }
    auto write=[&](const char *name,double value){
        if(!selectVariable(RouteDisplay,name))return false;
        char buffer[24];snprintf(buffer,sizeof(buffer),"%.12g",value);return enterValue(RouteDisplay,buffer);
    };
    bool ok=write(departure?"Man. date":"Eject date",values.date)&&write("Prograde vel.",values.prograde)&&
            write("Outward vel.",values.outward)&&write("Ch. plane vel.",values.plane);
    frame(RouteDisplay);selectVariable(RouteDisplay,previous);
    for(int i=0;i<32;++i)tick();return ok;
}

bool Session::routeApproach(const Route &route,Approach &approach){
    if(!routeMatches(route)||!route.targetStage)return false;
    auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(route.targetStage);
    return base&&base->nativeApproach(&approach.distance,&approach.relativeSpeed,&approach.mjd,&approach.source);
}

bool Session::routeHohmann(const Route &route,double &dv){
    if(!routeMatches(route)||!route.targetStage)return false;
    auto *base=impl->display(RouteDisplay).nativeView()->nativeState()->getbasefn(route.targetStage);
    if(!base)return false;VECTOR3 velocity;base->calculate(&velocity);dv=base->GetHohmannDV();
    return std::isfinite(dv)&&fabs(dv)>.01;
}
}
