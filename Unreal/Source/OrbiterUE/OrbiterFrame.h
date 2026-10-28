#pragma once
#include "OrbiterCore.h"
namespace OrbiterFrame {
inline FVector Point(const Vector &V){return FVector(V.z,V.x,V.y);}
inline FQuat Rotation(const native::Flight &Flight){
    const FVector X=Point(Flight.forward),Y=Point(Flight.right),Z=Point(Flight.up);
    FMatrix Basis=FMatrix::Identity;Basis.SetAxes(&X,&Y,&Z);return FQuat(Basis);
}
}
