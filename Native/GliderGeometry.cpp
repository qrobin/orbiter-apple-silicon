#include "GliderGeometry.h"
#include <algorithm>
#include <cmath>
#include <map>
#include <utility>

namespace native {
namespace {
void refineWheel(MeshGroup &group, float cy, float cz) {
    std::map<std::pair<uint32_t,uint32_t>,uint32_t> midpoints;
    auto midpoint = [&](uint32_t a, uint32_t b) {
        auto key=std::minmax(a,b);
        auto found=midpoints.find(key);
        if(found!=midpoints.end()) return found->second;
        const Vertex p=group.vertices[a], q=group.vertices[b];
        Vertex v{(p.x+q.x)*.5f,(p.y+q.y)*.5f,(p.z+q.z)*.5f,
                 (p.nx+q.nx)*.5f,(p.ny+q.ny)*.5f,(p.nz+q.nz)*.5f,
                 (p.u+q.u)*.5f,(p.v+q.v)*.5f};
        // The mesh uses concentric 12-sided rings. Bend only edges on the
        // same ring; radial edges, hubs and their UV seams remain intact.
        float py=p.y-cy,pz=p.z-cz,qy=q.y-cy,qz=q.z-cz;
        float pr=std::hypot(py,pz),qr=std::hypot(qy,qz),mr=std::hypot(v.y-cy,v.z-cz);
        if(std::abs(p.x-q.x)<1e-5f && std::abs(pr-qr)<1e-4f && pr>1e-4f && mr>1e-4f && (py*qy+pz*qz)/(pr*qr)>.8f) {
            float scale=(pr+qr)*.5f/mr;
            v.y=cy+(v.y-cy)*scale;v.z=cz+(v.z-cz)*scale;
        }
        float length=std::sqrt(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz);
        if(length>1e-6f){v.nx/=length;v.ny/=length;v.nz/=length;}
        uint32_t index=static_cast<uint32_t>(group.vertices.size());group.vertices.push_back(v);
        midpoints.emplace(key,index);return index;
    };
    auto old=group.indices; group.indices.clear();group.indices.reserve(old.size()*4);
    for(size_t i=0;i+2<old.size();i+=3) {
        uint32_t a=old[i],b=old[i+1],c=old[i+2],ab=midpoint(a,b),bc=midpoint(b,c),ca=midpoint(c,a);
        group.indices.insert(group.indices.end(),{a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca});
    }
}
}
void refineGliderWheels(Mesh &mesh) {
    // Group numbers and wheel centres come from the original non-SCRAM mesh.
    if(mesh.groups.size()!=122)return;
    refineWheel(mesh.groups[99],-1.995099f,-3.133083f);
    refineWheel(mesh.groups[100],-1.995099f,-3.133083f);
    refineWheel(mesh.groups[101],-2.320639f,8.545220f);
}
}
