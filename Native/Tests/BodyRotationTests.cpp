#include "Flight.h"
#include "Surface.h"
#include "SolarSystem.h"
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){try{
    Flight landed;landed.placeOnEarth(Rad(28),Rad(-80),Rad(90));
    double date=landed.mjd;auto earth=body(BodyId::Earth).rotation(date),moon=body(BodyId::Moon).rotation(date),mars=body(BodyId::Mars).rotation(date);
    Vector surface=bodySurface(BodyId::Earth,Rad(28),Rad(-80),date).up;
    check(landed.velocity.length()>100,"Surface initially rotates with Earth");
    landed.setRotationPaused(true);
    check(bodyRotationsPaused()&&body(BodyId::Earth).spin().length()==0&&body(BodyId::Moon).spin().length()==0,"Pause stops body spin rates");
    check(landed.velocity.length()<1e-8&&landed.angularVelocity.length()<1e-12,"A parked vessel remains stationary relative to the paused surface");
    landed.elapsed=7200;double now=date+landed.elapsed/86400.;
    check(fabs(std::remainder(body(BodyId::Earth).rotation(now)-earth,Pi2))<1e-10&&fabs(std::remainder(body(BodyId::Moon).rotation(now)-moon,Pi2))<1e-10&&fabs(std::remainder(body(BodyId::Mars).rotation(now)-mars,Pi2))<1e-10,"Every body's texture and surface orientation remain frozen");
    check(bodySurface(BodyId::Earth,Rad(28),Rad(-80),now).up.dist(surface)<1e-12,"Geographic surface positions remain frozen");
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    check(bodyState(BodyId::Earth,now).position.dist(bodyState(BodyId::Earth,date).position)>1000,"Planetary orbital motion continues while rotation is paused");
    auto save=std::filesystem::temp_directory_path()/"orbiter-body-rotation-test.scn";landed.save(save);
    landed.setRotationPaused(false);check(!bodyRotationsPaused(),"Rotation can be resumed before reloading");
    auto invalid=std::filesystem::temp_directory_path()/"orbiter-body-rotation-invalid-test.scn";
    {std::ifstream in(save);std::string contents((std::istreambuf_iterator<char>(in)),{});
     auto field=contents.find("  RPOS ");auto end=contents.find('\n',field);
     contents.replace(field,end-field,"  RPOS 0 0 0");std::ofstream(invalid)<<contents;}
    bool rejected=false;try{Flight bad;bad.load(invalid);}catch(const std::exception &){rejected=true;}
    check(rejected&&!bodyRotationsPaused(),"A failed scenario load restores the previous rotation state");std::filesystem::remove(invalid);
    Flight restored;restored.load(save);std::filesystem::remove(save);
    check(bodyRotationsPaused()&&fabs(std::remainder(body(BodyId::Earth).rotation(now)-earth,Pi2))<1e-10,"Saved scenarios restore the held body orientation");
    landed=restored;
    landed.setRotationPaused(false);
    check(!bodyRotationsPaused()&&fabs(std::remainder(body(BodyId::Earth).rotation(now)-earth,Pi2))<1e-10,"Resuming rotation does not jump the surface");
    check((landed.velocity-crossp(body(BodyId::Earth).spin(),landed.position)).length()<1e-8,"A parked vessel resumes at surface rotational speed");
    double later=now+60./86400.;
    check(fabs(std::remainder(body(BodyId::Earth).rotation(later)-earth,Pi2))>.004,"Rotation advances again after resuming");
    check(body(BodyId::Venus).spin().length()>0&&body(BodyId::Venus).period<0,"Retrograde spin resumes correctly");
    std::cout<<"body rotation pause checks passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
