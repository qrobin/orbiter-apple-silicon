#pragma once
// Minimal native host for the original MIT-licensed TransX module. No Win32,
// graphics compatibility layer, or vessel-module loading is involved.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>
#include <strings.h>
using DWORD=uint32_t;using UINT=unsigned;using WORD=uint16_t;
using WPARAM=uintptr_t;using LPARAM=intptr_t;using OAPI_MSGTYPE=intptr_t;
using HINSTANCE=void*;using HWND=void*;using BOOL=bool;
using OBJHANDLE=void*;using FILEHANDLE=FILE*;using THRUSTER_HANDLE=void*;using DOCKHANDLE=void*;
#define DLLCLBK extern "C"
#define LOWORD(x) ((uint16_t)((uintptr_t)(x)&65535))
#define HIWORD(x) ((uint16_t)(((uintptr_t)(x)>>16)&65535))
#define RGB(r,g,b) ((DWORD)(r)|((DWORD)(g)<<8)|((DWORD)(b)<<16))
#define ZeroMemory(p,n) memset(p,0,n)
#define _stricmp strcasecmp
#define _strnicmp strncasecmp
#define _finite std::isfinite
#define _isnan std::isnan
using std::min;using std::max;
#include "CoreConstants.h"
constexpr double PI2=2*PI;
struct VECTOR3 {double x,y,z;};
struct MATRIX3 {double m11,m12,m13,m21,m22,m23,m31,m32,m33;};
struct IVECTOR2 {int x,y;};
inline VECTOR3 _V(double x,double y,double z){return{x,y,z};}
inline VECTOR3 operator+(VECTOR3 a,VECTOR3 b){return{a.x+b.x,a.y+b.y,a.z+b.z};}
inline VECTOR3 operator-(VECTOR3 a,VECTOR3 b){return{a.x-b.x,a.y-b.y,a.z-b.z};}
inline VECTOR3 operator-(VECTOR3 a){return{-a.x,-a.y,-a.z};}
inline VECTOR3 operator*(VECTOR3 a,double s){return{a.x*s,a.y*s,a.z*s};}
inline VECTOR3 operator*(double s,VECTOR3 a){return a*s;}
inline VECTOR3 operator/(VECTOR3 a,double s){return a*(1/s);}
inline VECTOR3 &operator+=(VECTOR3 &a,VECTOR3 b){return a=a+b;}
inline VECTOR3 &operator-=(VECTOR3 &a,VECTOR3 b){return a=a-b;}
inline VECTOR3 &operator*=(VECTOR3 &a,double b){return a=a*b;}
inline VECTOR3 &operator/=(VECTOR3 &a,double b){return a=a/b;}
inline double dotp(VECTOR3 a,VECTOR3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline VECTOR3 crossp(VECTOR3 a,VECTOR3 b){return{a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double length(VECTOR3 a){return sqrt(dotp(a,a));}
inline VECTOR3 unit(VECTOR3 a){double n=length(a);return n>0?a/n:VECTOR3{};}
inline VECTOR3 mul(const MATRIX3&m,VECTOR3 v){return{m.m11*v.x+m.m12*v.y+m.m13*v.z,m.m21*v.x+m.m22*v.y+m.m23*v.z,m.m31*v.x+m.m32*v.y+m.m33*v.z};}
inline VECTOR3 tmul(const MATRIX3&m,VECTOR3 v){return{m.m11*v.x+m.m21*v.y+m.m31*v.z,m.m12*v.x+m.m22*v.y+m.m32*v.z,m.m13*v.x+m.m23*v.y+m.m33*v.z};}
inline MATRIX3 mul(const MATRIX3&a,const MATRIX3&b){
    auto x=mul(a,VECTOR3{b.m11,b.m21,b.m31}),y=mul(a,VECTOR3{b.m12,b.m22,b.m32}),z=mul(a,VECTOR3{b.m13,b.m23,b.m33});
    return{x.x,y.x,z.x,x.y,y.y,z.y,x.z,y.z,z.z};
}
template<size_t N,typename...Args>int sprintf_s(char(&buffer)[N],const char *format,Args...args){return snprintf(buffer,N,format,args...);}
struct ATMCONST{double radlimit;};
struct ATMPARAM{double T,p,rho;};
struct VESSELSTATUS {int status=0;OBJHANDLE rbody=nullptr,base=nullptr;VECTOR3 rpos{},rvel{},arot{},vrot{};};
enum THGROUP_TYPE{THGROUP_MAIN,THGROUP_RETRO,THGROUP_HOVER};
class VESSEL {
public:
    double GetMass()const;
    void GetStatus(VESSELSTATUS &status)const;
    void GetGlobalPos(VECTOR3 &p)const;
    OBJHANDLE GetSurfaceRef()const;
    unsigned DockCount()const{return 0;}
    DOCKHANDLE GetDockHandle(unsigned)const{return nullptr;}
    OBJHANDLE GetDockStatus(DOCKHANDLE)const{return nullptr;}
    int GetGroupThrusterCount(THGROUP_TYPE type)const{return type==THGROUP_HOVER?3:2;}
    THRUSTER_HANDLE GetGroupThruster(THGROUP_TYPE type,int index)const;
    double GetThrusterMax0(THRUSTER_HANDLE handle)const;
    double GetThrusterIsp0(THRUSTER_HANDLE)const;
};
namespace oapi {
using IVECTOR2=::IVECTOR2;
struct Pen{int style,width;DWORD color;};struct Brush{DWORD color;};
struct DrawCommand{enum Kind{Text,Line,Ellipse,Rectangle,Polyline}kind;int x=0,y=0,x2=0,y2=0;DWORD color=0x00ff00,fill=0;bool filled=false,dashed=false;int width=1;std::string text;std::vector<IVECTOR2> points;};
class Sketchpad{
    Pen fallback{1,1,0x00ff00};Pen *pen=&fallback;Brush *brush=nullptr;int x=0,y=0;
    DrawCommand command(DrawCommand::Kind kind)const;
public:
    std::vector<DrawCommand> commands;
    // Native display-only viewpoint offsets; original TransX calculations are unchanged.
    double graphYaw=0,graphPitch=0;
    Pen *SetPen(Pen*p){auto old=pen;pen=p;return old;}
    Brush *SetBrush(Brush*b){auto old=brush;brush=b;return old;}
    bool Text(int x,int y,const char *text,int count);
    void MoveTo(int a,int b){x=a;y=b;}
    void LineTo(int a,int b);
    void Ellipse(int a,int b,int c,int d);
    void Rectangle(int a,int b,int c,int d);
    void Polyline(const IVECTOR2 *points,int count);
};
}
struct MFDBUTTONMENU{const char *line1,*line2;char key;};
class MFD2 {
protected:DWORD W,H;VESSEL *vessel;
public:
    MFD2(DWORD w,DWORD h,VESSEL*v):W(w),H(h),vessel(v){}
    virtual ~MFD2()=default;
    oapi::Pen *GetDefaultPen(int id)const;
    void Title(oapi::Sketchpad *s,const char *title)const{s->Text(0,0,title,(int)strlen(title));}
};
enum{OAPI_KEY_A=30,OAPI_KEY_B,OAPI_KEY_C,OAPI_KEY_D,OAPI_KEY_E,OAPI_KEY_F,OAPI_KEY_G,OAPI_KEY_H,OAPI_KEY_I,OAPI_KEY_J,OAPI_KEY_K,OAPI_KEY_L,OAPI_KEY_M,OAPI_KEY_N,OAPI_KEY_O,OAPI_KEY_P,OAPI_KEY_Q,OAPI_KEY_R,OAPI_KEY_S,OAPI_KEY_T,OAPI_KEY_U,OAPI_KEY_V,OAPI_KEY_W,OAPI_KEY_X,OAPI_KEY_Y,OAPI_KEY_Z,OAPI_KEY_MINUS,OAPI_KEY_EQUALS,OAPI_KEY_PERIOD,OAPI_KEY_COMMA,OAPI_KEY_LBRACKET,OAPI_KEY_RBRACKET};
constexpr int PANEL_MOUSE_LBDOWN=1,PANEL_MOUSE_LBPRESSED=2,OAPI_MSG_MFD_OPENED=1;
struct MFDMODESPECEX{char *name;DWORD key;OAPI_MSGTYPE(*msgproc)(UINT,UINT,WPARAM,LPARAM);void*context;};
int oapiRegisterMFDMode(const MFDMODESPECEX&);
void oapiUnregisterMFDMode(int);
double oapiGetSimTime();double oapiGetSimMJD();double oapiTime2MJD(double seconds);
int oapiGetGbodyCount();OBJHANDLE oapiGetGbodyByIndex(int index);OBJHANDLE oapiGetGbodyByName(const char *name);
OBJHANDLE oapiGetObjectByName(const char *name);OBJHANDLE oapiGetVesselByName(const char *name);
void oapiGetObjectName(OBJHANDLE handle,char *name,int capacity);
double oapiGetMass(OBJHANDLE handle);double oapiGetSize(OBJHANDLE handle);
void oapiGetGlobalPos(OBJHANDLE handle,VECTOR3 *p);void oapiGetGlobalVel(OBJHANDLE handle,VECTOR3 *v);
void oapiGetRelativePos(OBJHANDLE object,OBJHANDLE reference,VECTOR3 *p);void oapiGetRelativeVel(OBJHANDLE object,OBJHANDLE reference,VECTOR3 *v);
OBJHANDLE oapiGetFocusObject();VESSEL *oapiGetFocusInterface();VESSEL *oapiGetVesselInterface(OBJHANDLE handle);
void oapiGetFocusRelativePos(OBJHANDLE reference,VECTOR3 *p);void oapiGetFocusRelativeVel(OBJHANDLE reference,VECTOR3 *v);
void oapiGetFocusShipAirspeedVector(VECTOR3 *v);void oapiGetFocusEquPos(double *longitude,double *latitude,double *radius);
double oapiGetPlanetPeriod(OBJHANDLE handle);bool oapiPlanetHasAtmosphere(OBJHANDLE handle);
const ATMCONST *oapiGetPlanetAtmConstants(OBJHANDLE handle);void oapiGetPlanetAtmParams(OBJHANDLE handle,double altitude,double longitude,double latitude,ATMPARAM *parameters);
void oapiGetPlanetObliquityMatrix(OBJHANDLE handle,MATRIX3 *matrix);void oapiGetRotationMatrix(OBJHANDLE handle,MATRIX3 *matrix);
oapi::Pen *oapiCreatePen(int style,int width,DWORD color);oapi::Brush *oapiCreateBrush(DWORD color);
void oapiReleasePen(oapi::Pen *pen);void oapiReleaseBrush(oapi::Brush *brush);
bool oapiReadScenario_nextline(FILEHANDLE file,char *&line);void oapiWriteLine(FILEHANDLE file,const char *line);
void oapiWriteScenario_int(FILEHANDLE file,const char *key,int value);void oapiWriteScenario_string(FILEHANDLE file,const char *key,const char *value);
char *oapiDebugString();void oapiWriteLog(const char *line);
using NativeTransXInputCallback=bool(*)(void*,char*,void*);
void oapiOpenInputBox(char *prompt,NativeTransXInputCallback callback,char *initial,int max,void *data);
namespace native {class Flight;}
namespace native::transx {
struct InputRequest{std::string prompt,initial;NativeTransXInputCallback callback=nullptr;void *data=nullptr;int maxLength=20;};
void bind(const Flight *flight);
InputRequest &pendingInput();
}
