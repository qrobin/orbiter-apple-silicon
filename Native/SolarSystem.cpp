// Native adapters to the original VSOP87, ELP82, GALSAT and TASS17 solutions.
#include "SolarSystem.h"
#include <vector>
#include <fstream>
#include <stdexcept>
#include <algorithm>
void ELP82_init();void ELP82_exit();int ELP82_read(double);int ELP82(double,double*);
int cd2com(const char*);void chkgal();void galsat(double*,double*,double,int,int);
void ReadData(const char*,int);int posired(double,int,double*,double*);
namespace {std::string moonFile;}
const char *NativeMoonDataFile(){return moonFile.c_str();}
namespace native {
double solarIrradiance(double distance){
    if(!std::isfinite(distance)||distance<=0)return 0;
    double ratio=AU/distance;return std::min(64.0,ratio*ratio);
}
double solarDiscVisibility(double sunRadius,double occluderRadius,double separation){
    if(!std::isfinite(sunRadius)||!std::isfinite(occluderRadius)||!std::isfinite(separation)||sunRadius<=0||occluderRadius<=0||separation<0)return 1;
    if(separation>=sunRadius+occluderRadius)return 1;
    if(separation<=fabs(occluderRadius-sunRadius))return occluderRadius>=sunRadius?0:1-(occluderRadius*occluderRadius)/(sunRadius*sunRadius);
    double a=std::clamp((separation*separation+sunRadius*sunRadius-occluderRadius*occluderRadius)/(2*separation*sunRadius),-1.,1.);
    double b=std::clamp((separation*separation+occluderRadius*occluderRadius-sunRadius*sunRadius)/(2*separation*occluderRadius),-1.,1.);
    double area=sunRadius*sunRadius*acos(a)+occluderRadius*occluderRadius*acos(b)-.5*sqrt(std::max(0.,(-separation+sunRadius+occluderRadius)*(separation+sunRadius-occluderRadius)*(separation-sunRadius+occluderRadius)*(separation+sunRadius+occluderRadius)));
    return std::clamp(1-area/(Pi*sunRadius*sunRadius),0.,1.);
}
namespace {
struct Term {double a,b,c;};
struct Series {std::array<std::array<std::vector<Term>,6>,3> terms;};
std::array<Series,BodyCount> series;
struct Sample {double date=-1e50;BodyState first,second;};
std::array<Sample,BodyCount> samples;
bool loaded=false;
const std::pair<BodyId,const char*> planetFiles[]={
    {BodyId::Mercury,"mer"},{BodyId::Venus,"ven"},{BodyId::Earth,"ear"},{BodyId::Mars,"mar"},
    {BodyId::Jupiter,"jup"},{BodyId::Saturn,"sat"},{BodyId::Uranus,"ura"},{BodyId::Neptune,"nep"}};
BodyState rawState(BodyId id,double mjd){
    const auto &b=body(id);if(id==BodyId::Sun)return {};
    auto &model=series[(size_t)id];
    if(!model.terms[0][0].empty()){
        double t=(mjd-51544.5)/365250.,value[3]={},rate[3]={};
        for(int coordinate=0;coordinate<3;++coordinate)for(int power=0;power<6;++power){
            double sum=0,derivative=0,tp=power?pow(t,power):1;
            for(auto &term:model.terms[coordinate][power]){double a=term.b+term.c*t;sum+=term.a*cos(a);derivative-=term.a*term.c*sin(a);}
            value[coordinate]+=tp*sum;rate[coordinate]+=tp*derivative+(power?power*pow(t,power-1)*sum:0);
        }
        double lon=value[0],lat=value[1],r=value[2]*AU,scale=1/(365250.*86400.);
        double dl=rate[0]*scale,db=rate[1]*scale,dr=rate[2]*AU*scale;
        double cl=cos(lon),sl=sin(lon),cb=cos(lat),sb=sin(lat);
        return {{r*cb*cl,r*sb,r*cb*sl},{dr*cb*cl-r*sb*db*cl-r*cb*sl*dl,dr*sb+r*cb*db,dr*cb*sl-r*sb*db*sl+r*cb*cl*dl}};
    }
    double p[6]={};
    if(id==BodyId::Moon){ELP82(mjd,p);return {{p[0],p[1],p[2]},{p[3],p[4],p[5]}};}
    if(id>=BodyId::Io&&id<=BodyId::Callisto){double unused[6];galsat(p,unused,mjd+2400000.5,(int)id-(int)BodyId::Io+1,2);return {{p[0]*AU,p[2]*AU,p[1]*AU},{p[3]*AU/86400,p[5]*AU/86400,p[4]*AU/86400}};}
    if(id>=BodyId::Mimas&&id<=BodyId::Iapetus){posired(mjd+2400000.5,(int)id-(int)BodyId::Mimas,p,p+3);double v=AU/(86400.*365.25);return {{p[0]*AU,p[2]*AU,p[1]*AU},{p[3]*v,p[5]*v,p[4]*v}};}
    auto &el=b.elements;double a=el[0],e=el[1];if(a<=0)throw std::runtime_error(std::string("Missing orbital elements for ")+b.name);
    double n=sqrt(body(b.parent).mu()/(a*a*a)),M=remainder(el[5]-el[4]+n*(mjd-el[6])*86400,Pi2),E=M;
    for(int i=0;i<30;++i){double d=(E-e*sin(E)-M)/(1-e*cos(E));E-=d;if(fabs(d)<1e-14)break;}
    double x=a*(cos(E)-e),z=a*sqrt(1-e*e)*sin(E),vx=-n*a*sin(E)/(1-e*cos(E)),vz=n*a*sqrt(1-e*e)*cos(E)/(1-e*cos(E));
    double w=el[4]-el[3],cw=cos(w),sw=sin(w),co=cos(el[3]),so=sin(el[3]),ci=cos(el[2]),si=sin(el[2]);
    auto rotate=[&](double x,double z){double xp=x*cw-z*sw,zp=x*sw+z*cw;return Vector(co*xp-so*ci*zp,si*zp,so*xp+co*ci*zp);};
    return {rotate(x,z),rotate(vx,vz)};
}
}
void loadEphemerides(const std::filesystem::path &directory){
    if(loaded)return;
    auto path=[&](std::string flat,std::string nested){auto p=directory/flat;return std::filesystem::exists(p)?p:directory/nested;};
    for(auto [id,name]:planetFiles){
        std::string file="Vsop87B_"+std::string(name)+".dat";std::ifstream input(path(file,"Vsop87/Data/"+file));
        int maxPower;if(!(input>>maxPower)||maxPower<0||maxPower>5)throw std::runtime_error("Missing or invalid ephemeris: "+file);
        for(int coordinate=0;coordinate<3;++coordinate)for(int power=0;power<=maxPower;++power){
            int count;if(!(input>>count)||count<0||count>100000)throw std::runtime_error("Invalid VSOP87 term count");
            auto &terms=series[(size_t)id].terms[coordinate][power];terms.resize(count);
            for(auto &term:terms)if(!(input>>term.a>>term.b>>term.c)||!std::isfinite(term.a+term.b+term.c))throw std::runtime_error("Invalid VSOP87 coefficient");
        }
    }
    moonFile=path("ELP82.dat","Moon/ELP82.dat").string();
    auto gal=path("ephem_e15.dat","Galsat/ephem_e15.dat"),sat=path("tass17.dat","Satsat/tass17.dat");
    if(!std::filesystem::exists(moonFile)||!std::filesystem::exists(gal)||!std::filesystem::exists(sat))throw std::runtime_error("Missing moon ephemerides");
    ELP82_init();if(ELP82_read(1e-6)<0)throw std::runtime_error("Cannot load lunar ephemeris");
    if(cd2com(gal.string().c_str())!=0)throw std::runtime_error("Cannot load Galilean ephemerides");chkgal();ReadData(sat.string().c_str(),0);
    loaded=true;
}
bool ephemeridesReady(){return loaded;}
BodyState relativeBodyState(BodyId id,double mjd){
    if(!loaded)throw std::runtime_error("Solar System ephemerides are not loaded");
    if(!std::isfinite(mjd)||fabs(mjd)>1e6)throw std::invalid_argument("Invalid ephemeris date");
    (void)body(id);auto &s=samples[(size_t)id];double seconds=floor((mjd-51544.5)*1440)*60,date=51544.5+seconds/86400.;
    if(s.date!=date){s.date=date;s.first=rawState(id,date);s.second=rawState(id,date+60./86400.);}
    double u=std::clamp((mjd-date)*1440.,0.,1.),u2=u*u,u3=u2*u;
    Vector p=s.first.position*(2*u3-3*u2+1)+s.first.velocity*((u3-2*u2+u)*60)+s.second.position*(-2*u3+3*u2)+s.second.velocity*((u3-u2)*60);
    Vector v=s.first.position*((6*u2-6*u)/60)+s.first.velocity*(3*u2-4*u+1)+s.second.position*((-6*u2+6*u)/60)+s.second.velocity*(3*u2-2*u);
    return {p,v};
}
BodyState bodyState(BodyId id,double mjd){if(id==BodyId::Sun)return {};auto local=relativeBodyState(id,mjd),parent=bodyState(body(id).parent,mjd);return {parent.position+local.position,parent.velocity+local.velocity};}
double sphereOfInfluence(BodyId id,double mjd){if(id==BodyId::Sun)return 1e30;auto &b=body(id);double distance=relativeBodyState(id,mjd).position.length();return std::max(b.radius*1.5,distance*pow(b.mass/body(b.parent).mass,.4));}
}
