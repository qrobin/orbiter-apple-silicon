#include "SDK.h"
#include "Flight.h"
#include "SolarSystem.h"
#include "Surface.h"
#include <ctime>
#include <stdexcept>
namespace {
const native::Flight *flight;
VESSEL vessel;
struct BodyHandle{native::BodyId id;};
std::array<BodyHandle,native::BodyCount> handles=[](){std::array<BodyHandle,native::BodyCount> a{};for(size_t i=0;i<a.size();++i)a[i].id=(native::BodyId)i;return a;}();
VECTOR3 cv(Vector v){return{v.x,v.y,v.z};}
OBJHANDLE handle(native::BodyId id){return &handles.at((size_t)id);}
const native::CelestialBody &bodyFor(OBJHANDLE h){if(!h||h==&vessel)throw std::runtime_error("Invalid TransX body handle");return native::body(static_cast<BodyHandle*>(h)->id);}
native::BodyState state(OBJHANDLE h){
    if(!h)return {};
    if(h==&vessel){auto p=native::bodyState(flight->reference,oapiGetSimMJD());return {p.position+flight->position,p.velocity+flight->velocity};}
    return native::bodyState(bodyFor(h).id,oapiGetSimMJD());
}
MATRIX3 columns(Vector x,Vector y,Vector z){return{x.x,y.x,z.x,x.y,y.y,z.y,x.z,y.z,z.z};}
}
namespace native::transx {
void bind(const Flight *f){flight=f;}
InputRequest &pendingInput(){static InputRequest input;return input;}
bool formatCalendarUTC(double mjd,char *output,size_t capacity){
    if(!std::isfinite(mjd)||mjd<0||mjd>2973483.)return false;
    time_t instant=(time_t)std::round((mjd-40587.)*86400.);std::tm calendar={};
    return gmtime_r(&instant,&calendar)&&strftime(output,capacity,"%Y-%m-%d %H:%M:%S",&calendar)==19;
}
bool parseCalendarUTC(const char *text,double &mjd){
    if(!text||strlen(text)!=19)return false;
    std::tm calendar={};char *end=strptime(text,"%Y-%m-%d %H:%M:%S",&calendar);
    if(!end||*end)return false;
    time_t instant=timegm(&calendar);char normalized[32];
    mjd=double(instant)/86400.+40587.;
    return mjd>=0&&formatCalendarUTC(mjd,normalized,sizeof(normalized))&&!strcmp(text,normalized);
}
}
double oapiGetSimTime(){return flight?flight->elapsed:0;}
double oapiGetSimMJD(){return flight?flight->mjd+flight->elapsed/86400:51544.5;}
double oapiTime2MJD(double seconds){return (flight?flight->mjd:51544.5)+seconds/86400;}
int oapiGetGbodyCount(){return (int)handles.size();}
OBJHANDLE oapiGetGbodyByIndex(int i){return i>=0&&i<(int)handles.size()?&handles[i]:nullptr;}
OBJHANDLE oapiGetGbodyByName(const char *name){try{return handle(native::findBody(name));}catch(...){return nullptr;}}
OBJHANDLE oapiGetVesselByName(const char *name){return flight&&!strcasecmp(name,flight->name.c_str())?&vessel:nullptr;}
OBJHANDLE oapiGetObjectByName(const char *name){if(auto v=oapiGetVesselByName(name))return v;return oapiGetGbodyByName(name);}
void oapiGetObjectName(OBJHANDLE h,char *out,int count){if(count<=0)return;snprintf(out,count,"%s",!h?"None":h==&vessel?flight->name.c_str():bodyFor(h).name);}
double oapiGetMass(OBJHANDLE h){return !h?0:h==&vessel?flight->mass():bodyFor(h).mass;}
double oapiGetSize(OBJHANDLE h){return !h?0:h==&vessel?9:bodyFor(h).radius;}
void oapiGetGlobalPos(OBJHANDLE h,VECTOR3 *p){*p=cv(state(h).position);}
void oapiGetGlobalVel(OBJHANDLE h,VECTOR3 *v){*v=cv(state(h).velocity);}
void oapiGetRelativePos(OBJHANDLE h,OBJHANDLE ref,VECTOR3 *p){*p=h==&vessel&&ref==handle(flight->reference)?cv(flight->position):cv(state(h).position-state(ref).position);}
void oapiGetRelativeVel(OBJHANDLE h,OBJHANDLE ref,VECTOR3 *v){*v=h==&vessel&&ref==handle(flight->reference)?cv(flight->velocity):cv(state(h).velocity-state(ref).velocity);}
OBJHANDLE oapiGetFocusObject(){return &vessel;}
VESSEL *oapiGetFocusInterface(){return &vessel;}
VESSEL *oapiGetVesselInterface(OBJHANDLE h){return h==&vessel?&vessel:nullptr;}
void oapiGetFocusRelativePos(OBJHANDLE ref,VECTOR3*p){oapiGetRelativePos(&vessel,ref,p);}
void oapiGetFocusRelativeVel(OBJHANDLE ref,VECTOR3*v){oapiGetRelativeVel(&vessel,ref,v);}
void oapiGetFocusShipAirspeedVector(VECTOR3*v){*v=cv(flight->airRelativeVelocity());}
void oapiGetFocusEquPos(double*lon,double*lat,double*r){native::bodyCoordinates(flight->reference,flight->position,flight->mjd,flight->elapsed,*lat,*lon);*r=flight->position.length();}
double oapiGetPlanetPeriod(OBJHANDLE h){return bodyFor(h).period;}
bool oapiPlanetHasAtmosphere(OBJHANDLE h){return bodyFor(h).density>0&&bodyFor(h).atmosphereLimit>0;}
const ATMCONST *oapiGetPlanetAtmConstants(OBJHANDLE h){static std::array<ATMCONST,native::BodyCount> a{};auto &b=bodyFor(h);a[(size_t)b.id].radlimit=b.atmosphereLimit;return &a[(size_t)b.id];}
void oapiGetPlanetAtmParams(OBJHANDLE h,double alt,double,double,ATMPARAM *p){auto a=native::bodyAtmosphere(bodyFor(h).id,alt);*p={a.T,a.p,a.rho};}
void oapiGetPlanetObliquityMatrix(OBJHANDLE h,MATRIX3*m){auto &b=bodyFor(h);*m=columns(b.equatorX(),b.pole(),b.equatorZ());}
void oapiGetRotationMatrix(OBJHANDLE h,MATRIX3*m){
    if(h==&vessel){*m=columns(flight->right,flight->up,flight->forward);return;}
    auto &b=bodyFor(h);double a=b.rotation(oapiGetSimMJD());*m=columns(b.equatorX()*cos(a)+b.equatorZ()*sin(a),b.pole(),b.equatorZ()*cos(a)-b.equatorX()*sin(a));
}
double VESSEL::GetMass()const{return flight->mass();}
void VESSEL::GetStatus(VESSELSTATUS &s)const{
    s={};s.status=flight->groundContact?1:0;s.rbody=handle(flight->reference);s.rpos=cv(flight->position);s.rvel=cv(flight->velocity);s.vrot=cv(flight->angularVelocity);
    // TransX's getinvrotmatrix expects the ZYX angles of the inertial-to-local matrix.
    s.arot={atan2(flight->forward.y,flight->forward.z),asin(std::clamp(-flight->forward.x,-1.,1.)),atan2(flight->up.x,flight->right.x)};
}
void VESSEL::GetGlobalPos(VECTOR3&p)const{oapiGetGlobalPos(&vessel,&p);}
OBJHANDLE VESSEL::GetSurfaceRef()const{return handle(flight->reference);}
THRUSTER_HANDLE VESSEL::GetGroupThruster(THGROUP_TYPE type,int index)const{return reinterpret_cast<void*>(uintptr_t(1+(int)type*4+index));}
double VESSEL::GetThrusterMax0(THRUSTER_HANDLE h)const{int i=(int)(uintptr_t(h)-1),type=i/4,index=i%4;return type==THGROUP_MAIN?200000:type==THGROUP_RETRO?34000:index==0?140000:140000*3/4.55*.5;}
double VESSEL::GetThrusterIsp0(THRUSTER_HANDLE)const{return native::ExhaustVelocity;}
oapi::DrawCommand oapi::Sketchpad::command(DrawCommand::Kind kind)const{DrawCommand c;c.kind=kind;if(pen){c.color=pen->color;c.width=pen->width;c.dashed=pen->style==2;}if(brush){c.fill=brush->color;c.filled=true;}return c;}
bool oapi::Sketchpad::Text(int a,int b,const char*t,int n){auto c=command(DrawCommand::Text);c.x=a;c.y=b;c.text.assign(t,strnlen(t,std::max(0,n)));commands.push_back(std::move(c));return true;}
void oapi::Sketchpad::LineTo(int a,int b){auto c=command(DrawCommand::Line);c.x=x;c.y=y;c.x2=a;c.y2=b;commands.push_back(std::move(c));x=a;y=b;}
void oapi::Sketchpad::Ellipse(int a,int b,int d,int e){auto c=command(DrawCommand::Ellipse);c.x=a;c.y=b;c.x2=d;c.y2=e;commands.push_back(std::move(c));}
void oapi::Sketchpad::Rectangle(int a,int b,int d,int e){auto c=command(DrawCommand::Rectangle);c.x=a;c.y=b;c.x2=d;c.y2=e;commands.push_back(std::move(c));}
void oapi::Sketchpad::Polyline(const IVECTOR2*p,int n){auto c=command(DrawCommand::Polyline);if(n>0&&n<10000)c.points.assign(p,p+n);commands.push_back(std::move(c));}
oapi::Pen *oapiCreatePen(int s,int w,DWORD c){return new oapi::Pen{s,w,c};}
oapi::Brush *oapiCreateBrush(DWORD c){return new oapi::Brush{c};}
void oapiReleasePen(oapi::Pen*p){delete p;}void oapiReleaseBrush(oapi::Brush*b){delete b;}
oapi::Pen *MFD2::GetDefaultPen(int id)const{static oapi::Pen p[]={{1,1,0x00ff00},{1,1,0xff0000},{1,1,0x00ffff},{1,1,0x0000ff},{1,1,0x888888},{2,1,0x888888},{1,1,0xffffff}};return &p[std::clamp(id,0,6)];}
int oapiRegisterMFDMode(const MFDMODESPECEX&){return 1;}void oapiUnregisterMFDMode(int){}
bool oapiReadScenario_nextline(FILEHANDLE f,char *&line){static char buffer[2048];if(!f)return false;
    while(fgets(buffer,sizeof(buffer),f)){line=buffer;while(*line==' '||*line=='\t')++line;line[strcspn(line,"\r\n")]=0;if(*line&&*line!=';')return true;}return false;
}
void oapiWriteLine(FILEHANDLE f,const char *line){if(f)fprintf(f,"%s\n",line);}
void oapiWriteScenario_int(FILEHANDLE f,const char*k,int v){if(f)fprintf(f,"%s %d\n",k,v);}
void oapiWriteScenario_string(FILEHANDLE f,const char*k,const char*v){if(f)fprintf(f,"%s %s\n",k,v);}
char *oapiDebugString(){static char debug[1024];return debug;}
void oapiWriteLog(const char *s){fprintf(stderr,"TransX: %s\n",s);}
void oapiOpenInputBox(char *p,NativeTransXInputCallback cb,char *initial,int max,void *data){native::transx::pendingInput()={p?p:"",initial?initial:"",cb,data,max};}
