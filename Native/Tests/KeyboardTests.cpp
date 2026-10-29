#include "Keyboard.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){try{
    std::array<bool,256> keys{};keys[13]=true;Input down=flightKeyboardInput(keys);
    check(down.pitch==1&&down.translate==0,"W commands pitch down without forward translation");
    keys={};keys[1]=true;Input up=flightKeyboardInput(keys);check(up.pitch==-1,"S commands pitch up");
    Flight f;f.clearAssist();f.angularVelocity={};double initial=f.pitch();Flight other=f;
    for(int i=0;i<30;++i){f.advance(.01,down);other.advance(.01,up);}
    check(f.pitch()<initial&&other.pitch()>initial,"W lowers and S raises the nose in flight");
    keys={};keys[0]=true;check(flightKeyboardInput(keys).yaw==-1,"A yaws left");
    keys={};keys[2]=true;check(flightKeyboardInput(keys).yaw==1,"D yaws right");
    keys={};keys[126]=true;check(flightKeyboardInput(keys).translate==1&&flightKeyboardInput(keys).pitch==0,"Up arrow translates forward");
    keys={};keys[125]=true;check(flightKeyboardInput(keys).translate==-1,"Down arrow translates backward");
    keys={};keys[123]=true;check(flightKeyboardInput(keys).lateral==-1,"Left arrow translates left");
    keys={};keys[124]=true;check(flightKeyboardInput(keys).lateral==1,"Right arrow translates right");
    keys={};keys[12]=true;keys[6]=true;check(flightKeyboardInput(keys).roll==1&&flightKeyboardInput(keys).vertical==1,"Roll and vertical translation remain available");
    ModifierThrottle throttle;throttle.update(true,false,false,false);check(throttle.demand()==1,"Shift increases main throttle");
    throttle.update(false,true,false,false);check(throttle.demand()==-1,"Control decreases main throttle");
    throttle.update(true,true,false,false);check(throttle.demand()==0,"Opposite throttle modifiers cancel");
    throttle.update(true,false,true,false);check(throttle.demand()==0,"Option shortcuts cannot command throttle");
    throttle.update(true,false,false,true);check(throttle.demand()==0,"Command shortcuts cannot command throttle");
    throttle.update(true,false,false,false);throttle.inhibit();check(throttle.demand()==0,"Cutoff latches a held throttle key");
    throttle.update(false,false,false,false);throttle.update(true,false,false,false);check(throttle.demand()==1,"Releasing and pressing Shift re-enables throttle");
    std::cout<<"flight keyboard controls verified\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
