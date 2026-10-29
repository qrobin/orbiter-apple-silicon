#include "Session.h"
#include "Flight.h"
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
    return view->nativeStage()==stage&&view->nativeMode()==mode;
}
bool Session::routeView(int stage,int mode){return stage>0&&displayView(RouteDisplay,stage,mode);}

bool Session::createRoute(BodyId destination,Route &route,std::string &error){
    const auto valid=[](BodyId id){return (int)id>=0&&(int)id<(int)BodyId::Count;};
    BodyId origin=impl->flight.reference;
    if(!valid(origin)||!valid(destination)||origin==destination){error="Choose a different destination.";return false;}

    // Walk the original body's hierarchy: escape up to the common parent,
    // then target each child down to the destination.
    std::vector<BodyId> originPath,destinationPath;
    for(BodyId id=origin;;id=body(id).parent){originPath.push_back(id);if(id==BodyId::Sun)break;}
    for(BodyId id=destination;;id=body(id).parent){destinationPath.push_back(id);if(id==BodyId::Sun)break;}
    BodyId common=BodyId::Sun;
    for(auto id:originPath)if(std::find(destinationPath.begin(),destinationPath.end(),id)!=destinationPath.end()){common=id;break;}
    Route candidate;candidate.origin=origin;candidate.destination=destination;
    int stage=1;BodyId current=origin;
    while(current!=common){auto next=body(current).parent;candidate.legs.push_back({current,next,stage++,true});current=next;}
    std::vector<BodyId> descent;
    for(BodyId id=destination;id!=common;id=body(id).parent)descent.push_back(id);
    std::reverse(descent.begin(),descent.end());
    for(size_t i=0;i<descent.size();++i){
        if(!candidate.targetStage)candidate.targetStage=stage;
        candidate.legs.push_back({current,descent[i],stage,false});current=descent[i];
        if(i+1<descent.size())++stage;
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
        for(int i=0;i<128;++i)tick();restoreViews();error=message;return false;
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
        if(!base||!base->getplanpointer()||base->getplanpointer()->getplanid()!=2)return false;
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
            if(base->getplanpointer()&&base->getplanpointer()->getplanid()==2)candidate.ejectStage=stage;
        }
        center=next;
    }
    if(candidate.legs.empty())return false;
    candidate.destination=center;
    if(!routeMatches(candidate))return false;
    route=std::move(candidate);return true;
}

bool Session::routeValues(const Route &route,bool departure,RouteValues &values){
    if(!routeMatches(route))return false;
    int stage=departure?1:route.ejectStage,mode=departure?4:3;
    if(!stage||!routeView(stage,mode))return false;
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
