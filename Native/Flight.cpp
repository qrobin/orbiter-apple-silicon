#include "Flight.h"
#include "TimeData.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
TimeData td;
char DBG_MSG[256] = {};
namespace native {
static Vector rotate(const Vector &v,const Vector &axis,double angle) {
    return v*cos(angle)+crossp(axis,v)*sin(angle)+axis*(dotp(axis,v)*(1-cos(angle)));
}
Flight::Flight() {
    position={3626158.96,4307928.18,-3325004.36};
    velocity={6623.108,-3432.497,2656.884};
    align(velocity);
}
void Flight::align(const Vector &direction) {
    if(direction.length2()<1e-15) return;
    forward=direction.unit();
    Vector normal=position.unit();
    if(fabs(dotp(normal,forward))>.98) normal={0,1,0};
    if(fabs(dotp(normal,forward))>.98) normal={1,0,0};
    right=crossp(normal,forward).unit(); up=crossp(forward,right).unit();
}
void Flight::load(const std::filesystem::path &path) {
    std::ifstream file(path); if(!file) throw std::runtime_error("Cannot open scenario.");
    Flight candidate; std::string line, focus, blockName;
    bool ships=false, selected=false, found=false, orbiting=false, gotPos=false, gotVel=false;
    bool gotElements=false; double vals[7]={}; Vector arot,vrot; bool hasArot=false;
    // Read focus and date first; vessel blocks can appear in any order.
    while(std::getline(file,line)) {
        std::istringstream s(line); std::string key; s>>key;
        if(key=="Ship") s>>focus;
        if(key=="Date") { std::string format; s>>format; if(format=="MJD") s>>candidate.mjd; }
    }
    file.clear(); file.seekg(0);
    while(std::getline(file,line)) {
        std::istringstream s(line); std::string key; s>>key;
        if(key=="BEGIN_SHIPS") { ships=true; continue; }
        if(!ships) continue;
        if(key=="END_SHIPS") break;
        auto colon=key.find(':');
        if(colon!=std::string::npos) {
            blockName=key.substr(0,colon);
            selected=(focus.empty() ? !found : blockName==focus) && key.substr(colon+1)=="DeltaGlider";
            if(selected) { found=true; candidate.name=blockName; }
            continue;
        }
        if(key=="END") { selected=false; continue; }
        if(!selected) continue;
        if(key=="STATUS") { std::string state,body; s>>state>>body; orbiting=state=="Orbiting"&&body=="Earth"; }
        if(key=="RPOS") gotPos=bool(s>>candidate.position.x>>candidate.position.y>>candidate.position.z);
        if(key=="RVEL") gotVel=bool(s>>candidate.velocity.x>>candidate.velocity.y>>candidate.velocity.z);
        if(key=="ELEMENTS") { gotElements=true; for(double &v: vals) if(!(s>>v)) gotElements=false; }
        if(key=="VROT") s>>vrot.x>>vrot.y>>vrot.z;
        if(key=="AROT") hasArot=bool(s>>arot.x>>arot.y>>arot.z);
        if(key=="PRPLEVEL") { std::string token; while(s>>token) {
            auto c=token.find(':'); if(c==std::string::npos) continue;
            try { double value=std::stod(token.substr(c+1));
                if(token.substr(0,c)=="0") candidate.fuel=MainCapacity*value;
                if(token.substr(0,c)=="1") candidate.rcs=RcsCapacity*value;
            } catch(...) { throw std::runtime_error("Invalid propellant value."); }
        }}
    }
    if(!found||!orbiting) throw std::runtime_error("Choose an Earth-orbit scenario focused on a DeltaGlider. Other vessels and surface flight are not ported yet.");
    if(!(gotPos&&gotVel)) {
        if(!gotElements) throw std::runtime_error("The focused vessel needs RPOS/RVEL or ELEMENTS.");
        td.Reset(candidate.mjd);
        Elements e(vals[0],vals[1],Rad(vals[2]),Rad(vals[3]),Rad(vals[4]),Rad(vals[5]),vals[6]);
        e.Setup(0,EarthMass,candidate.mjd); e.PosVel(candidate.position,candidate.velocity,0);
    }
    if(!std::isfinite(candidate.position.length2())||!std::isfinite(candidate.velocity.length2())||
       !std::isfinite(candidate.mjd)||candidate.altitude()<=0||candidate.position.length()>1e10||
       candidate.velocity.length()>1e6||!std::isfinite(candidate.fuel)||!std::isfinite(candidate.rcs)||
       !std::isfinite(arot.length2())||!std::isfinite(vrot.length2())||
       crossp(candidate.position,candidate.velocity).length2()<1||
       candidate.fuel<0||candidate.fuel>MainCapacity||
       candidate.rcs<0||candidate.rcs>RcsCapacity)
        throw std::runtime_error("Scenario contains invalid orbital state or fuel quantities.");
    candidate.align(candidate.velocity);
    if(hasArot) {
        Matrix m; m.Set(Vector(Rad(arot.x),Rad(arot.y),Rad(arot.z)));
        candidate.right=mul(m,Vector(1,0,0)); candidate.up=mul(m,Vector(0,1,0));
        candidate.forward=mul(m,Vector(0,0,1));
    }
    candidate.angularVelocity=vrot*RAD;
    *this=candidate;
}
void Flight::save(const std::filesystem::path &path) const {
    std::ofstream f(path); if(!f) throw std::runtime_error("Cannot write scenario at that location.");
    Vector angles(atan2(forward.y,forward.z),-asin(std::clamp(forward.x,-1.,1.)),atan2(up.x,right.x));
    f<<std::setprecision(16)<<"BEGIN_ENVIRONMENT\n  System Sol\n  Date MJD "<<mjd+elapsed/86400.0
     <<"\nEND_ENVIRONMENT\n\nBEGIN_FOCUS\n  Ship "<<name<<"\nEND_FOCUS\n\nBEGIN_SHIPS\n"<<name
     <<":DeltaGlider\n  STATUS Orbiting Earth\n  RPOS "<<position.x<<' '<<position.y<<' '<<position.z
     <<"\n  RVEL "<<velocity.x<<' '<<velocity.y<<' '<<velocity.z
     <<"\n  AROT "<<Deg(angles.x)<<' '<<Deg(angles.y)<<' '<<Deg(angles.z)
     <<"\n  VROT "<<Deg(angularVelocity.x)<<' '<<Deg(angularVelocity.y)<<' '<<Deg(angularVelocity.z)
     <<"\n  PRPLEVEL 0:"<<fuel/MainCapacity<<" 1:"<<rcs/RcsCapacity<<"\nEND\nEND_SHIPS\n";
    f.flush(); if(!f) throw std::runtime_error("Writing the scenario failed.");
}
Elements Flight::orbit() const {
    td.Reset(mjd); Elements e; e.Setup(0,EarthMass,mjd); e.Calculate(position,velocity,elapsed); return e;
}
void Flight::coast(double dt) {
    auto e=orbit();
    // Kepler elements become singular at the parabolic boundary.
    if(fabs(e.e-1)<1e-8) {
        int steps=std::max(1,(int)ceil(dt*20));
        for(int i=0;i<steps;++i) step(dt/steps,{});
    } else e.PosVel(position,velocity,elapsed+dt);
}
void Flight::step(double dt,const Input &input) {
    Vector control(input.pitch,input.yaw,input.roll);
    if(assist==Assist::Prograde||assist==Assist::Retrograde) {
        align(assist==Assist::Prograde?velocity:-velocity); angularVelocity={};
    } else {
        if(rcs>0) {
            angularVelocity+=control*(.22*dt);
            double demand=control.length();
            if(assist==Assist::KillRotation) {
                demand+=angularVelocity.length(); angularVelocity*=exp(-4*dt);
            }
            rcs=std::max(0.0,rcs-demand*dt*1.0);
        }
        // Bound manual angular rates; original RCS thruster topology is a later milestone.
        double rate=angularVelocity.length(); if(rate>1.5) angularVelocity*=1.5/rate;
        Vector axis=right*angularVelocity.x+up*angularVelocity.y+forward*angularVelocity.z;
        if(axis.length2()>1e-20) {
            double angle=axis.length()*dt; axis.unify();
            forward=rotate(forward,axis,angle).unit(); up=rotate(up,axis,angle).unit();
            right=crossp(up,forward).unit(); up=crossp(forward,right).unit();
        }
    }
    double force=fuel>0?400000.0*throttle:0;
    // Limit impulse to actual fuel available, including the final partial burn.
    double consumed=std::min(fuel,force*dt/ExhaustVelocity);
    force=consumed*ExhaustVelocity/dt;
    Vector thrust=forward*(force/mass()); acceleration=thrust.length();
    fuel-=consumed;
    double rcsForce=rcs>0?5000.0*input.translate:0;
    double rcsUsed=std::min(rcs,fabs(rcsForce)*dt/ExhaustVelocity);
    if(rcsForce) thrust+=forward*(copysign(rcsUsed*ExhaustVelocity/dt,rcsForce)/mass());
    rcs-=rcsUsed;
    auto gravity=[](const Vector &p) { double r=p.length(); return p*(-Mu/(r*r*r)); };
    Vector k1p=velocity, k1v=gravity(position)+thrust;
    Vector k2p=velocity+k1v*(dt*.5), k2v=gravity(position+k1p*(dt*.5))+thrust;
    Vector k3p=velocity+k2v*(dt*.5), k3v=gravity(position+k2p*(dt*.5))+thrust;
    Vector k4p=velocity+k3v*dt, k4v=gravity(position+k3p*dt)+thrust;
    position+=(k1p+k2p*2+k3p*2+k4p)*(dt/6);
    velocity+=(k1v+k2v*2+k3v*2+k4v)*(dt/6);
}
void Flight::advance(double realSeconds,const Input &input) {
    if(paused||impacted||realSeconds<=0||!std::isfinite(realSeconds)) return;
    bool maneuver=throttle>0||input.pitch||input.yaw||input.roll||input.translate||angularVelocity.length2()>1e-16;
    if(maneuver) warp=1;
    double dt=std::min(realSeconds,.1)*std::clamp(warp,1.0,1000.0);
    if(!maneuver) {
        coast(dt); acceleration=0;
        if(assist==Assist::Prograde||assist==Assist::Retrograde) align(assist==Assist::Prograde?velocity:-velocity);
    } else {
        int steps=std::max(1,(int)ceil(dt*120));
        for(int i=0;i<steps;++i) step(dt/steps,input);
    }
    elapsed+=dt;
    if(altitude()<=0) { impacted=true; paused=true; throttle=0; }
}
}
