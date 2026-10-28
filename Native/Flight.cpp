#include "Flight.h"
#include "TimeData.h"
#include "Aerodynamics.h"
#include "Surface.h"
#include "SolarSystem.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
TimeData td;
char DBG_MSG[256] = {};
namespace native {
Assist navButtonMode(int button) {
    static const Assist modes[]={Assist::KillRotation,Assist::Retrograde,Assist::Prograde,Assist::AntiNormal,Assist::Normal,Assist::HorizonLevel};
    return button>=0&&button<6?modes[button]:Assist::Free;
}
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
void Flight::placeOnEarth(double latitude,double longitude,double headingAngle,double clearance) {reference=BodyId::Earth;placeOnBody(latitude,longitude,headingAngle,clearance);}
void Flight::placeOnBody(double latitude,double longitude,double headingAngle,double clearance) {
    if(!centralBody().solid)throw std::invalid_argument("This body has no solid surface");
    auto frame=bodySurface(reference,latitude,longitude,mjd,elapsed);
    position=frame.up*(centralBody().radius+clearance);up=frame.up;
    forward=(frame.north*cos(headingAngle)+frame.east*sin(headingAngle)).unit();right=crossp(up,forward).unit();
    velocity=crossp(centralBody().spin(),position);
    angularVelocity={dotp(centralBody().spin(),right),dotp(centralBody().spin(),up),dotp(centralBody().spin(),forward)};
    glider.part(Part::Gear).position=glider.part(Part::Gear).target=1;
    groundContact=true;wheelContacts=3;paused=false;impacted=false;clearAssist();
}
double Flight::pitch() const { return asin(std::clamp(dotp(forward,position.unit()),-1.,1.)); }
double Flight::bank() const { auto n=position.unit();return atan2(-dotp(right,n),dotp(up,n)); }
double Flight::heading() const {
    double lat,lng;bodyCoordinates(reference,position,mjd,elapsed,lat,lng);auto frame=bodySurface(reference,lat,lng,mjd,elapsed);
    double h=atan2(dotp(forward,frame.east),dotp(forward,frame.north));return h<0?h+Pi2:h;
}
double Flight::surfaceVerticalSpeed() const { return dotp(velocity-crossp(centralBody().spin(),position),position.unit()); }
bool Flight::setHoverHold(int mode,double target) {
    if(!centralBody().solid||altitude()>120000||fuel<=0||impacted||!std::isfinite(target)||
       (mode!=1&&mode!=2)||(mode==1&&(target<0||target>120000))||(mode==2&&fabs(target)>20))return false;
    auto &h=glider.hoverControl;h.holdMode=mode;
    if(mode==1)h.altitudeTarget=target;else h.verticalSpeedTarget=target;
    h.holdActive=true;h.resetFeedback();clearAssist();
    if(!h.attitudeMode)h.attitudeMode=1;
    return true;
}
void Flight::setHoverThrottle(double level) {
    glider.hover=std::clamp(level,0.,1.);glider.hoverControl.holdActive=false;glider.hoverControl.resetFeedback();
}
void Flight::cutEngines() {
    throttle=glider.hover=glider.retro=0;glider.mainLevel=glider.hoverLevel=glider.retroLevel=0;
    glider.hoverControl.holdActive=false;glider.hoverControl.resetFeedback();glider.hoverControl.levels.fill(0);
}
void Flight::clearAssist() {assist=Assist::Free;killRotationWithLevel=false;}
bool Flight::assistActive(Assist mode) const {
    return mode!=Assist::Free&&(assist==mode||(mode==Assist::KillRotation&&assist==Assist::HorizonLevel&&killRotationWithLevel));
}
void Flight::toggleAssist(Assist mode) {
    if(mode==Assist::Free){clearAssist();return;}
    // The original nav computer permits KILL-R to coexist with HRLVL.
    if(mode==Assist::KillRotation&&assist==Assist::HorizonLevel){killRotationWithLevel=!killRotationWithLevel;if(killRotationWithLevel)warp=1;return;}
    if(assist==mode){clearAssist();return;}
    assist=mode;killRotationWithLevel=false;warp=1;
}
void Flight::load(const std::filesystem::path &path) {
    std::ifstream file(path); if(!file) throw std::runtime_error("Cannot open scenario.");
    Flight candidate; std::string line, focus, blockName;
    bool ships=false, selected=false, found=false, orbiting=false, landed=false, gotPos=false, gotVel=false, gotSurface=false, gearSpecified=false, gotVrot=false;
    double longitude=0,latitude=0,headingAngle=0,clearance=2.53;
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
        if(key=="GEAR") gearSpecified=true;
        if(candidate.glider.parse(line)) continue;
        if(key=="STATUS") { std::string state,body; s>>state>>body; candidate.reference=findBody(body);orbiting=state=="Orbiting";landed=state=="Landed"&&candidate.centralBody().solid; }
        if(key=="POS") gotSurface=bool(s>>longitude>>latitude);
        if(key=="HEADING") s>>headingAngle;
        if(key=="ALT") s>>clearance;
        if(key=="RCSMODE") s>>candidate.glider.rcsMode;
        if(key=="HUDMode") s>>candidate.hud.mode;
        if(key=="HUDBrightness") s>>candidate.hud.brightness;
        if(key=="HUDColour") s>>candidate.hud.colour;
        if(key=="DGMAIN") s>>candidate.throttle;
        if(key=="RPOS") gotPos=bool(s>>candidate.position.x>>candidate.position.y>>candidate.position.z);
        if(key=="RVEL") gotVel=bool(s>>candidate.velocity.x>>candidate.velocity.y>>candidate.velocity.z);
        if(key=="ELEMENTS") { gotElements=true; for(double &v: vals) if(!(s>>v)) gotElements=false; }
        if(key=="VROT") gotVrot=bool(s>>vrot.x>>vrot.y>>vrot.z);
        if(key=="AROT") hasArot=bool(s>>arot.x>>arot.y>>arot.z);
        if(key=="PRPLEVEL") { std::string token; while(s>>token) {
            auto c=token.find(':'); if(c==std::string::npos) continue;
            try { double value=std::stod(token.substr(c+1));
                if(token.substr(0,c)=="0") candidate.fuel=MainCapacity*value;
                if(token.substr(0,c)=="1") candidate.rcs=RcsCapacity*value;
            } catch(...) { throw std::runtime_error("Invalid propellant value."); }
        }}
    }
    if(!found||(!orbiting&&!landed)) throw std::runtime_error("Choose a Solar System scenario focused on a DeltaGlider. Landed flights require a solid body and POS coordinates.");
    bool nativeCartesian=gotPos&&gotVel;
    if(landed&&!nativeCartesian) {
        if(!gotSurface||!std::isfinite(latitude)||!std::isfinite(longitude)||!std::isfinite(headingAngle)||!std::isfinite(clearance)||fabs(latitude)>90||clearance<0||clearance>1000)
            throw std::runtime_error("The landed scenario needs valid POS, HEADING and ALT values.");
        auto originalGear=candidate.glider.part(Part::Gear);
        candidate.placeOnBody(Rad(latitude),Rad(longitude),Rad(headingAngle),std::max(.1,clearance));
        if(gearSpecified) candidate.glider.part(Part::Gear)=originalGear;
    } else if(!nativeCartesian) {
        if(!gotElements) throw std::runtime_error("The focused vessel needs RPOS/RVEL or ELEMENTS.");
        td.Reset(candidate.mjd);
        Elements e(vals[0],vals[1],Rad(vals[2]),Rad(vals[3]),Rad(vals[4]),Rad(vals[5]),vals[6]);
        e.Setup(0,candidate.centralBody().mass,candidate.mjd); e.PosVel(candidate.position,candidate.velocity,0);
    }
    if(!std::isfinite(candidate.position.length2())||!std::isfinite(candidate.velocity.length2())||
       !std::isfinite(candidate.mjd)||candidate.altitude()<=0||candidate.position.length()>1e14||
       candidate.velocity.length()>1e6||!std::isfinite(candidate.fuel)||!std::isfinite(candidate.rcs)||
       !std::isfinite(arot.length2())||!std::isfinite(vrot.length2())||
       (!landed&&crossp(candidate.position,candidate.velocity).length2()<1)||
       candidate.fuel<0||candidate.fuel>MainCapacity||
       candidate.rcs<0||candidate.rcs>RcsCapacity||!candidate.glider.valid()||!candidate.hud.valid()||!std::isfinite(candidate.throttle)||candidate.throttle<0||candidate.throttle>1)
        throw std::runtime_error("Scenario contains invalid orbital state or fuel quantities.");
    if(!landed) candidate.align(candidate.velocity);
    if(hasArot&&(!landed||nativeCartesian)) {
        Matrix m; m.Set(Vector(Rad(arot.x),Rad(arot.y),Rad(arot.z)));
        candidate.right=mul(m,Vector(1,0,0)); candidate.up=mul(m,Vector(0,1,0));
        candidate.forward=mul(m,Vector(0,0,1));
    }
    if(!landed||nativeCartesian||gotVrot) candidate.angularVelocity=vrot*RAD;
    candidate.groundContact=landed;
    *this=candidate;
}
void Flight::save(const std::filesystem::path &path) const {
    std::ofstream f(path); if(!f) throw std::runtime_error("Cannot write scenario at that location.");
    Vector angles(atan2(forward.y,forward.z),-asin(std::clamp(forward.x,-1.,1.)),atan2(up.x,right.x));
    f<<std::setprecision(16)<<"BEGIN_ENVIRONMENT\n  System Sol\n  Date MJD "<<mjd+elapsed/86400.0
     <<"\nEND_ENVIRONMENT\n\nBEGIN_FOCUS\n  Ship "<<name<<"\nEND_FOCUS\n\nBEGIN_SHIPS\n"<<name
     <<":DeltaGlider\n  STATUS "<<(groundContact?"Landed":"Orbiting")<<' '<<centralBody().name<<"\n  RPOS "<<position.x<<' '<<position.y<<' '<<position.z
     <<"\n  RVEL "<<velocity.x<<' '<<velocity.y<<' '<<velocity.z
     <<"\n  AROT "<<Deg(angles.x)<<' '<<Deg(angles.y)<<' '<<Deg(angles.z)
     <<"\n  VROT "<<Deg(angularVelocity.x)<<' '<<Deg(angularVelocity.y)<<' '<<Deg(angularVelocity.z)
     <<"\n  PRPLEVEL 0:"<<fuel/MainCapacity<<" 1:"<<rcs/RcsCapacity
     <<"\n  HUDMode "<<hud.mode<<"\n  HUDBrightness "<<hud.brightness<<"\n  HUDColour "<<hud.colour<<'\n';
    if(groundContact) {double lat,lng;bodyCoordinates(reference,position,mjd,elapsed,lat,lng);f<<"  POS "<<Deg(lng)<<' '<<Deg(lat)<<"\n  HEADING "<<Deg(heading())<<"\n  ALT "<<altitude()<<'\n';}
    f<<"  DGMAIN "<<throttle<<'\n';
    glider.save(f);
    f<<"END\nEND_SHIPS\n";
    f.flush(); if(!f) throw std::runtime_error("Writing the scenario failed.");
}
Elements Flight::orbit() const {
    td.Reset(mjd); Elements e; e.Setup(0,centralBody().mass,mjd); e.Calculate(position,velocity,elapsed); return e;
}
void Flight::startOrbit(BodyId id){
    double date=mjd+elapsed/86400;bool automatic=automaticReferenceChanges;*this=Flight();mjd=date;reference=id;automaticReferenceChanges=automatic;
    const auto &b=centralBody();double altitude=std::max(b.radius*.06,b.atmosphereLimit+20000.);
    if(b.radius<100000)altitude=b.radius*.08;
    double radius=id==BodyId::Sun?AU*.5:!b.solid?b.radius*4:b.radius+altitude;
    Vector sun=ephemeridesReady()&&id!=BodyId::Sun?(-bodyState(id,mjd).position).unit():Vector(.32,.84,-.44).unit();
    Vector radial=(sun*.95+b.pole()*.25).unit();position=radial*radius;
    velocity=crossp(b.pole(),radial).unit()*sqrt(b.mu()/radius);align(velocity);assist=Assist::Prograde;
}
void Flight::changeReference(BodyId next){
    if(next==reference)return;double date=mjd+elapsed/86400;auto old=bodyState(reference,date),target=bodyState(next,date);
    position+=old.position-target.position;velocity+=old.velocity-target.velocity;reference=next;glider.hoverControl.resetFeedback();
}
void Flight::updateReference(){
    double date=mjd+elapsed/86400;
    for(int pass=0;pass<4;++pass){
        BodyId next=reference;
        if(reference!=BodyId::Sun&&position.length()>sphereOfInfluence(reference,date)*1.03)next=centralBody().parent;
        else{
            auto center=bodyState(reference,date);double closest=1;
            for(const auto &b:bodies())if(b.id!=reference&&b.parent==reference){
                auto state=bodyState(b.id,date);double ratio=(center.position+position-state.position).length()/(sphereOfInfluence(b.id,date)*.95);
                if(ratio<closest){closest=ratio;next=b.id;}
            }
        }
        if(next==reference)break;changeReference(next);
    }
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
    auto &hover=glider.hoverControl;
    if(fuel<=0||altitude()>120000){hover.holdActive=false;hover.resetFeedback();}
    hover.updateHold(dt,altitude(),surfaceVerticalSpeed(),MaxHoverThrust/mass(),glider.hover);
    Vector control(input.pitch,input.yaw,input.roll);
    Vector translation(input.lateral,input.vertical,input.translate);
    if(glider.rcsMode==2) { translation.x+=input.yaw; translation.y-=input.pitch; control={}; }
    if(assistActive(Assist::KillRotation)&&angularVelocity.length()<1e-5) {
        if(assist==Assist::KillRotation)clearAssist();else killRotationWithLevel=false;
    }
    if(assist==Assist::KillRotation) {
        Vector limit(40000/(mass()*15.5),30000/(mass()*22.1),30000/(mass()*7.7));
        control={-angularVelocity.x/limit.x*3,-angularVelocity.y/limit.y*3,-angularVelocity.z/limit.z*3};
    } else if(assist!=Assist::Free) {
        Vector radial=position.unit(), normal=crossp(velocity,position).unit();
        Vector target,desiredUp;bool controlRoll=false;
        if(assist==Assist::Maneuver)target=maneuverDirection.unit();
        else if(assist==Assist::Prograde||assist==Assist::Retrograde){
            target=(assist==Assist::Prograde?velocity:-velocity).unit();
            desiredUp=normal;controlRoll=normal.length2()>1e-12;
        } else if(assist==Assist::Normal||assist==Assist::AntiNormal){
            target=assist==Assist::Normal?normal:-normal;
            desiredUp=(assist==Assist::Normal?-velocity:velocity).unit();controlRoll=target.length2()>1e-12;
        } else if(assist==Assist::HorizonLevel){
            Vector horizontal=forward-radial*dotp(forward,radial);
            if(horizontal.length2()<1e-12)horizontal=velocity-radial*dotp(velocity,radial);
            if(horizontal.length2()<1e-12){double lat,lng;bodyCoordinates(reference,position,mjd,elapsed,lat,lng);horizontal=bodySurface(reference,lat,lng,mjd,elapsed).north;}
            target=horizontal.unit();desiredUp=radial;controlRoll=true;
        }
        if(target.length2()<1e-12)target=forward;
        Vector error=crossp(forward,target);
        // A 180-degree target needs an explicit axis: the cross product is zero there.
        if(dotp(forward,target)<-.98&&error.length()<.05) error=up;
        Vector desired(dotp(error,right),dotp(error,up),0);
        desired*=.6;
        if(controlRoll){
            Vector projected=desiredUp-forward*dotp(desiredUp,forward);
            if(projected.length2()>1e-12){projected.unify();desired.z=std::clamp(atan2(dotp(forward,crossp(up,projected)),dotp(up,projected))*.6,-.6,.6);}
        }
        control={(desired.x-angularVelocity.x)*mass()*15.5/40000*3,
                 (desired.y-angularVelocity.y)*mass()*22.1/30000*3,
                 (desired.z-angularVelocity.z)*mass()*7.7/30000*3};
        if(killRotationWithLevel)control.y=-angularVelocity.y*mass()*22.1/30000*3;
    }
    for(int i=0;i<3;++i) { control(i)=std::clamp(control(i),-1.,1.); translation(i)=std::clamp(translation(i),-1.,1.); }
    // The manual RCS dial does not disable the original nav computer.
    if(glider.rcsMode==0) {if(assist==Assist::Free)control={};translation={};}
    // In hover attitude mode these axes request bounded pitch/bank targets.
    // Keep yaw/translation available without firing competing pitch/roll jets.
    if(hover.attitudeMode&&glider.hover>0&&altitude()<120000&&assist==Assist::Free)control.x=control.z=0;
    glider.rcsRotation=control; glider.rcsTranslation=translation;
    glider.elevator=std::clamp(-input.pitch,-1.,1.); glider.rudder=input.yaw; glider.aileron=input.roll;
    // Original DG thruster locations, directions and easy-model vacuum ratings.
    Vector force,torque;
    auto engine=[&](Vector position,Vector direction,double thrust) {
        Vector f=direction*thrust; force+=f; torque+=crossp(position,f);
    };
    double left=throttle*std::clamp(1-glider.mainBalance,0.,1.)*200000;
    double rightEngine=throttle*std::clamp(1+glider.mainBalance,0.,1.)*200000;
    Vector mainDirection(glider.gimbalYaw/7.7,tan(5*RAD)*glider.gimbalPitch,1); mainDirection.unify();
    double retro=glider.retroLevel*34000;
    hover.balance(glider.hover,glider.hoverBalance,pitch(),bank(),-angularVelocity.x,-angularVelocity.z,
                  glider.rcsMode==2?0:input.pitch,glider.rcsMode==2?0:input.roll);
    double hf=hover.levels[0]*140000,hl=hover.levels[1]*140000*(3./4.55)*.5,hr=hover.levels[2]*140000*(3./4.55)*.5;
    double demand=(left+rightEngine+retro*2+hf+hl+hr)*dt/ExhaustVelocity;
    double scale=demand>0?std::min(1.,fuel/demand):1;
    engine({-1,0,-7.7},mainDirection,left*scale); engine({1,0,-7.7},mainDirection,rightEngine*scale);
    engine({-3,-.236,5.6},{0,.04210548,-.99911317},retro*scale);
    engine({3,-.236,5.6},{0,.04210548,-.99911317},retro*scale);
    engine({0,0,3},{0,1,0},hf*scale); engine({-3,0,-4.55},{0,1,0},hl*scale); engine({3,0,-4.55},{0,1,0},hr*scale);
    fuel=demand>=fuel?0:fuel-demand;
    glider.mainLevel=throttle*scale; glider.retroLevel*=scale; glider.hoverLevel=(hf+hl+hr)*scale/MaxHoverThrust;
    for(auto &level:hover.levels)level*=scale;
    double rcsDemand=5000*(fabs(control.x)+fabs(control.y)+fabs(control.z)+fabs(translation.x)+fabs(translation.y)+fabs(translation.z))*dt/ExhaustVelocity;
    double rcsScale=rcsDemand>0?std::min(1.,rcs/rcsDemand):1;
    torque+=Vector(control.x*40000,control.y*30000,control.z*30000)*rcsScale;
    force+=translation*(5000*rcsScale); rcs=rcsDemand>=rcs?0:rcs-rcsDemand;
    glider.rcsRotation*=rcsScale; glider.rcsTranslation*=rcsScale;
    auto air=bodyAtmosphere(reference,altitude());
    Vector spin=centralBody().spin();
    Vector airVelocity=velocity-crossp(spin,position);
    double airspeed=airVelocity.length();
    dynamicPressure=.5*air.rho*airspeed*airspeed;
    mach=air.T>0?airspeed/sqrt(centralBody().gamma*(reference==BodyId::Earth?286.91:centralBody().gasConstant)*air.T):0;
    Vector localVelocity(dotp(airVelocity,right),dotp(airVelocity,up),dotp(airVelocity,forward));
    angleOfAttack=atan2(-localVelocity.y,localVelocity.z);
    if(air.rho>0&&airspeed>1&&(reference!=BodyId::Earth||altitude()<120000)) {
        double cl,cm,cd,hcl,hcm,hcd;
        verticalLift(angleOfAttack,mach,&cl,&cm,&cd);
        horizontalLift(atan2(-localVelocity.x,localVelocity.z),mach,&hcl,&hcm,&hcd);
        Vector vertical(0,localVelocity.z,-localVelocity.y),horizontal(localVelocity.z,0,-localVelocity.x);
        if(vertical.length2()>1) force+=vertical.unit()*(dynamicPressure*90*cl);
        if(horizontal.length2()>1) force+=horizontal.unit()*(dynamicPressure*15*hcl);
        double extra=.8*glider.part(Part::Gear).position+.2*glider.part(Part::RetroCover).position+
            3*glider.part(Part::Nose).position+glider.part(Part::Radiator).position+4*glider.part(Part::Airbrake).position;
        force-=localVelocity.unit()*(dynamicPressure*(90*cd+15*hcd+extra));
        torque.x+=dynamicPressure*(90*5*cm-glider.elevator*1.4*1.7*7.2-glider.trim*.3*1.7*7.2);
        torque.y+=dynamicPressure*glider.rudder*.8*1.7*7.2;
        torque.z+=dynamicPressure*glider.aileron*.3*1.7*15;
        torque-=Vector(angularVelocity.x*.10,angularVelocity.y*.13,angularVelocity.z*.04)*(dynamicPressure*100);
    }
    GroundResponse ground;
    if(centralBody().solid&&altitude()<15) ground=groundForces(position,velocity,right,up,forward,angularVelocity,mass(),
        glider.part(Part::Gear).open(),input.yaw,
        glider.parkingBrake?1:std::clamp(input.leftBrake,0.,1.),glider.parkingBrake?1:std::clamp(input.rightBrake,0.,1.),dt,reference);
    groundContact=ground.contacts>0;wheelContacts=ground.wheels;contactLoad=ground.load;
    force+=Vector(dotp(ground.force,right),dotp(ground.force,up),dotp(ground.force,forward));
    torque+=ground.torque;
    if(ground.maximumClosingSpeed>12&&ground.contacts>0) {
        impacted=true;paused=true;cutEngines();return;
    }
    Vector inertia=Vector(15.5,22.1,7.7)*mass();
    Vector w=angularVelocity;
    Vector angularAcceleration((torque.x+(inertia.y-inertia.z)*w.y*w.z)/inertia.x,
                               (torque.y+(inertia.z-inertia.x)*w.z*w.x)/inertia.y,
                               (torque.z+(inertia.x-inertia.y)*w.x*w.y)/inertia.z);
    angularVelocity+=angularAcceleration*dt;
    Vector axis=right*angularVelocity.x+up*angularVelocity.y+forward*angularVelocity.z;
    if(axis.length2()>1e-20) {
        double angle=axis.length()*dt; axis.unify();
        forward=rotate(forward,axis,angle).unit(); up=rotate(up,axis,angle).unit();
        right=crossp(up,forward).unit(); up=crossp(forward,right).unit();
    }
    Vector thrust=(right*force.x+up*force.y+forward*force.z)/mass(); acceleration=thrust.length();
    auto gravity=[this](const Vector &p) { double r=p.length(); return p*(-gravityMu()/(r*r*r)); };
    Vector k1p=velocity, k1v=gravity(position)+thrust;
    Vector k2p=velocity+k1v*(dt*.5), k2v=gravity(position+k1p*(dt*.5))+thrust;
    Vector k3p=velocity+k2v*(dt*.5), k3v=gravity(position+k2p*(dt*.5))+thrust;
    Vector k4p=velocity+k3v*dt, k4v=gravity(position+k3p*dt)+thrust;
    position+=(k1p+k2p*2+k3p*2+k4p)*(dt/6);
    velocity+=(k1v+k2v*2+k3v*2+k4v)*(dt/6);
}
void Flight::advance(double realSeconds,const Input &input) {
    if(paused||impacted||realSeconds<=0||!std::isfinite(realSeconds)) return;
    bool atmosphericFlight=(reference==BodyId::Earth?altitude()<120000:bodyAtmosphere(reference,altitude()).rho>1e-12)||(centralBody().solid&&altitude()<20);
    bool maneuver=assist==Assist::Maneuver||throttle>0||glider.hover>0||glider.hoverControl.holdActive||glider.retro>0||input.pitch||input.yaw||input.roll||input.translate||input.lateral||input.vertical||angularVelocity.length2()>1e-16;
    if(warp>1&&centralBody().solid&&orbit().PeDist()<centralBody().radius+20){warp=1;atmosphericFlight=true;}
    if(maneuver||atmosphericFlight) warp=1;
    double dt=std::min(realSeconds,.1)*std::clamp(warp,1.0,1000.0);
    glider.elevator=-input.pitch;glider.rudder=input.yaw;glider.aileron=input.roll;
    glider.advance(dt,throttle,bodyAtmosphere(reference,altitude()).p);
    if(!maneuver&&!atmosphericFlight&&(assist==Assist::Free||warp>1)) {
        coast(dt); acceleration=0;
        // At accelerated time the finite-torque nav programs are suspended;
        // do not teleport the vessel's attitude or bypass RCS fuel limits.
    } else {
        int steps=std::max(1,(int)ceil(dt*(altitude()<20?480:120)));
        for(int i=0;i<steps&&!impacted;++i) step(dt/steps,input);
    }
    elapsed+=dt;
    if(automaticReferenceChanges&&ephemeridesReady())updateReference();
    Vector relativeVelocity=velocity-crossp(centralBody().spin(),position);
    groundSpeed=(relativeVelocity-position.unit()*dotp(relativeVelocity,position.unit())).length();
    if(altitude()<-10) { impacted=true; paused=true; cutEngines(); }
}
}
