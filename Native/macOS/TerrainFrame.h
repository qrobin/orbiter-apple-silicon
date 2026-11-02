#pragma once
#include "VisualTypes.h"
#include "Vecmat.h"
#include <cmath>

// Subtract planet-sized positions in the rotating frame before converting
// small relative displacements to world coordinates. Keeping the residual
// separate preserves sub-metre camera motion on the GPU.
inline void setTerrainFrame(FrameUniforms &f,const Vector &camera,
    const Vector &axisX,const Vector &pole,const Vector &axisZ){
    Vector fixed(dotp(camera,axisX),dotp(camera,pole),dotp(camera,axisZ));
    Vector high(std::floor(fixed.x/4096)*4096,std::floor(fixed.y/4096)*4096,std::floor(fixed.z/4096)*4096);
    Vector low=fixed-high;
    f.terrainOriginHigh={(float)high.x,(float)high.y,(float)high.z,1};
    f.terrainOriginLow={(float)low.x,(float)low.y,(float)low.z,0};
    f.terrainAxisX={(float)axisX.x,(float)axisX.y,(float)axisX.z,0};
    f.terrainAxisZ={(float)axisZ.x,(float)axisZ.y,(float)axisZ.z,0};
}
