#pragma once
#include "SDK.h"
#include <memory>
namespace native {class Flight;}
namespace native::transx {
struct Frame {
    std::vector<oapi::DrawCommand> commands;
    std::vector<std::string> variables;
    std::string selected,help;
    int stage=1,view=2;
    bool ready=false;
};
class Session {
public:
    explicit Session(Flight &flight);
    ~Session();
    void tick();
    Frame frame(int display);
    void rotateGraph(int display,double horizontalPoints,double verticalPoints);
    void resetGraph(int display);
    void button(int display,int index,bool held=false);
    void selectVariable(int display,const std::string &name);
    bool enterValue(int display,const std::string &value);
    void save(const std::string &path);
    void load(const std::string &path);
    bool maneuverDirection(int display,VECTOR3 &direction);
private:
    struct Impl;std::unique_ptr<Impl> impl;
};
}
