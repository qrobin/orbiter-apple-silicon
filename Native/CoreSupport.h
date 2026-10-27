#pragma once
#include <algorithm>
#include <fstream>
#include <sstream>
#include <string>
#include "TimeData.h"
// The native orbit library needs only the scalar configuration reader, not Orbiter's UI.
inline bool GetItemReal(std::ifstream &f, const char *key, double &v) {
    f.clear(); f.seekg(0); std::string line;
    while (std::getline(f,line)) {
        auto end=line.find(';'); if(end!=std::string::npos) line.resize(end);
        auto eq=line.find('='); if(eq==std::string::npos) continue;
        std::istringstream lhs(line.substr(0,eq)); std::string name; lhs>>name;
        if(name==key) return bool(std::istringstream(line.substr(eq+1))>>v);
    }
    return false;
}
