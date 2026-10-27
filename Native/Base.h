#pragma once
#include "Mesh.h"
#include "Vecmat.h"
namespace native {
struct SurfaceBase {
    double latitude=0,longitude=0;
    size_t pads=0,runways=0,buildings=0,omitted=0;
    Mesh mesh;
};
// Supported primitives retain their original base-local coordinates (south/up/east).
SurfaceBase loadSurfaceBase(const std::filesystem::path &config,const std::filesystem::path &meshDirectory);
Vector wrapBasePoint(const Vector &point);
}
