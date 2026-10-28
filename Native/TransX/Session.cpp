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
    std::unique_ptr<TransxMFD> mfd[2];
    struct GraphRotation {double yaw=0,pitch=0;} rotation[2];
    explicit Impl(Flight &f):flight(f){
        bind(&f);mapfunction::getthemap();
        // Original map construction and background scheduling run on the main
        // thread. Build the small catalogue before constructing its MFD views.
        for(int i=0;i<256;++i)MFDFunction::donextaction();
        mfd[0]=std::make_unique<TransxMFD>(512,512,oapiGetFocusInterface(),0);
        mfd[1]=std::make_unique<TransxMFD>(512,512,oapiGetFocusInterface(),1);
        for(int i=0;i<128;++i)opcPostStep(oapiGetSimTime(),0,oapiGetSimMJD());
    }
    ~Impl(){bind(&flight);mfd[0].reset();mfd[1].reset();shipptrs::destroyshipptrs();pendingInput()={};}
    TransxMFD &display(int d){bind(&flight);return *mfd[std::clamp(d,0,1)];}
};
Session::Session(Flight &f):impl(std::make_unique<Impl>(f)){}
Session::~Session()=default;
void Session::tick(){bind(&impl->flight);for(int i=0;i<8;++i)opcPostStep(oapiGetSimTime(),0,oapiGetSimMJD());}
Frame Session::frame(int display){
    auto &mfd=impl->display(display);oapi::Sketchpad s;Frame f;
    const auto &rotation=impl->rotation[std::clamp(display,0,1)];s.graphYaw=rotation.yaw;s.graphPitch=rotation.pitch;
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
    auto &r=impl->rotation[std::clamp(display,0,1)];
    r.yaw=std::remainder(r.yaw+horizontalPoints*.008,PI2);
    r.pitch=std::clamp(r.pitch+verticalPoints*.008,-PI*.49,PI*.49);
}
void Session::resetGraph(int display){impl->rotation[std::clamp(display,0,1)]={};}
void Session::button(int display,int index,bool held){
    if(index<0||index>=12)return;
    impl->display(display).ConsumeButton(index,held?PANEL_MOUSE_LBPRESSED:PANEL_MOUSE_LBDOWN);
    tick();
}
void Session::selectVariable(int display,const std::string &name){
    auto *v=impl->display(display).nativeView();auto *handler=v->GetVarhandler();
    auto *initial=handler->getcurrent(v->nativeMode());
    for(int i=0;i<128;++i){auto *current=handler->getcurrent(v->nativeMode());if(!current)return;
        char buffer[80]={};current->getname(buffer);if(name==buffer)return;handler->setnextcurrent(v->nativeMode());
        if(handler->getcurrent(v->nativeMode())==initial)return;
    }
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
    // A full Orbiter scenario has a focus Ship entry before the MFD block.
    // Start at TYPE TransX so the original module only sees its own status.
    char line[2048];long start=0;
    while(fgets(line,sizeof(line),file)){char type[80]={},key[80]={};if(sscanf(line,"%79s %79s",key,type)==2&&!strcasecmp(key,"TYPE")&&!strcasecmp(type,"TransX")){start=ftell(file);break;}}
    fseek(file,start,SEEK_SET);impl->display(0).ReadStatus(file);fclose(file);for(int i=0;i<128;++i)tick();
}
bool Session::maneuverDirection(int display,VECTOR3 &direction){
    auto *view=impl->display(display).nativeView();auto *base=view->nativeState()->getbasefn(view->nativeStage());
    if(!base)return false;
    if(base->gethmajor()!=oapiGetFocusInterface()->GetSurfaceRef()||!base->nativeManeuverVector(&direction))return false;
double magnitude=length(direction);
    if(!std::isfinite(magnitude)||magnitude<.1)return false;direction/=magnitude;return true;
}
}
