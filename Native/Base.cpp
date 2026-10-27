// Native subset of Orbiter base primitives. Original data/geometry:
// Src/Orbiter/Baseobj.cpp, Copyright (c) Martin Schweiger, MIT License.
#include "Base.h"
#include "Flight.h"
#include <algorithm>
#include <cmath>
#include <cctype>
#include <iterator>
#include <fstream>
#include <map>
#include <sstream>
#include <stdexcept>
namespace native {
#include "BaseGeometry.inc"
Vector wrapBasePoint(const Vector &p) {
    double factor=EarthRadius/sqrt(EarthRadius*EarthRadius+p.x*p.x+p.z*p.z);
    return {p.x*factor,EarthRadius*(factor-1)+p.y,p.z*factor};
}
SurfaceBase loadSurfaceBase(const std::filesystem::path &config,const std::filesystem::path &meshDirectory) {
    std::ifstream file(config);if(!file)throw std::runtime_error("Cannot open surface base.");
    SurfaceBase base;
    base.mesh.materials={{{.65,.68,.64,1}},{{1,1,1,1}},{{.09,.10,.11,1}},{{.9,.9,.86,1}},{{.26,.32,.17,1}}};
    std::map<std::pair<size_t,size_t>,size_t> batches;
    auto group=[&](std::string texture,size_t material=1)->MeshGroup& {
        size_t ti=0;
        if(!texture.empty()) {
            std::transform(texture.begin(),texture.end(),texture.begin(),[](unsigned char c){return std::tolower(c);});
            auto &textures=base.mesh.textures;auto i=std::find(textures.begin(),textures.end(),texture+".dds");
            if(i==textures.end()){textures.push_back(texture+".dds");ti=textures.size();}else ti=i-textures.begin()+1;
        }
        auto key=std::make_pair(ti,material);auto i=batches.find(key);
        if(i==batches.end()) {
            batches[key]=base.mesh.groups.size();base.mesh.groups.emplace_back();
            auto &g=base.mesh.groups.back();g.texture=ti;g.material=material;return g;
        }
        return base.mesh.groups[i->second];
    };
    struct Object {
        std::string type,mesh,texture[3]; Vector pos,scale{1,1,1},end1,end2;
        double rotation=0,width=10,u[3]={1,1,1},v[3]={1,1,1};
    } object;
    auto emit=[&](MeshGroup &g,Vertex vertex) {
        double c=cos(object.rotation),s=sin(object.rotation);
        Vector p(vertex.x*c-vertex.z*s,vertex.y,vertex.x*s+vertex.z*c);
        p=wrapBasePoint(p+object.pos+Vector(0,.035,0));
        Vector n(vertex.nx*c-vertex.nz*s,vertex.ny,vertex.nx*s+vertex.nz*c);
        g.vertices.push_back({(float)p.x,(float)p.y,(float)p.z,(float)n.x,(float)n.y,(float)n.z,vertex.u,vertex.v});
    };
    auto quad=[&](MeshGroup &g,Vector a,Vector b,Vector c,Vector d,Vector normal,double u=1,double v=1) {
        uint32_t first=(uint32_t)g.vertices.size();Vector points[]={a,b,c,d};float uv[][2]={{0,0},{(float)u,0},{(float)u,(float)v},{0,(float)v}};
        for(int i=0;i<4;++i)emit(g,{(float)points[i].x,(float)points[i].y,(float)points[i].z,(float)normal.x,(float)normal.y,(float)normal.z,uv[i][0],uv[i][1]});
        g.indices.insert(g.indices.end(),{first,first+1,first+2,first,first+2,first+3});
    };
    auto finish=[&] {
        if(object.type=="LPAD2A") {
            auto vertices=std::vector<Vertex>(std::begin(padVertices),std::end(padVertices));
            // Original atlas layout for the two pad-number digits, repeated at each end.
            for(int digit=0;digit<2;++digit) {
                int ofs=21+digit*4,num=int(base.pads+1);num=(digit?num:num/10)%10;
                for(int end:{0,8}) {
                    if(num<6) {
                        float u0=num?(num-1)*.1875f:0,v0=num?.9957f:.2925f,v1=num?.7613f:.0582f;
                        vertices[ofs+end].u=vertices[ofs+end+2].u=u0;
                        vertices[ofs+end+1].u=vertices[ofs+end+3].u=u0+.1875f;
                        vertices[ofs+end].v=vertices[ofs+end+1].v=v0;
                        vertices[ofs+end+2].v=vertices[ofs+end+3].v=v1;
                    }else {
                        vertices[ofs+end].u=vertices[ofs+end+1].u=.9957f;
                        vertices[ofs+end+2].u=vertices[ofs+end+3].u=.7613f;
                        vertices[ofs+end+1].v=vertices[ofs+end+3].v=(num-6)*.1875f;
                        vertices[ofs+end].v=vertices[ofs+end+2].v=(num-5)*.1875f;
                    }
                }
            }
            auto &g=group(object.texture[0]);uint32_t first=(uint32_t)g.vertices.size();
            for(auto vertex:vertices){vertex.x*=object.scale.x;vertex.z*=object.scale.x;emit(g,vertex);}
            for(auto index:padIndices)g.indices.push_back(first+index);++base.pads;
        }else if(object.type=="BLOCK") {
            double x=object.scale.x*.5,y=object.scale.y,z=object.scale.z*.5;
            auto &gx=group(object.texture[0],object.texture[0].empty()?0:1);
            quad(gx,{-x,0,-z},{-x,0,z},{-x,y,z},{-x,y,-z},{-1,0,0},object.u[0],object.v[0]);
            quad(gx,{x,0,z},{x,0,-z},{x,y,-z},{x,y,z},{1,0,0},object.u[0],object.v[0]);
            auto &gz=group(object.texture[1],object.texture[1].empty()?0:1);
            quad(gz,{x,0,-z},{-x,0,-z},{-x,y,-z},{x,y,-z},{0,0,-1},object.u[1],object.v[1]);
            quad(gz,{-x,0,z},{x,0,z},{x,y,z},{-x,y,z},{0,0,1},object.u[1],object.v[1]);
            auto &roof=group(object.texture[2],object.texture[2].empty()?0:1);
            quad(roof,{-x,y,-z},{-x,y,z},{x,y,z},{x,y,-z},{0,1,0},object.u[2],object.v[2]);++base.buildings;
        }else if(object.type=="RUNWAY") {
            Vector axis=object.end2-object.end1;double length=axis.length();if(length<1||object.width<=0)return;
            Vector side(axis.z,0,-axis.x);side*=object.width*.5/length;
            auto &g=group("",2);int segments=(int)ceil(length/80);
            for(int i=0;i<segments;++i) {
                Vector a=object.end1+axis*(double(i)/segments),b=object.end1+axis*(double(i+1)/segments);
                quad(g,a-side,a+side,b+side,b-side,{0,1,0});
            }
            auto &marks=group("",3);Vector unit=axis/length,edge=side*.95;
            for(double x=60;x<length-60;x+=60) {
                Vector a=object.end1+unit*x+Vector(0,.025,0),b=a+unit*30,w=side*(1.2/object.width);
                quad(marks,a-w,a+w,b+w,b-w,{0,1,0});
            }
            for(int sign:{-1,1})for(int i=0;i<segments;++i) {
                Vector a=object.end1+axis*(double(i)/segments)+edge*sign+Vector(0,.025,0),b=a+axis/segments,w=side*(.8/object.width);
                quad(marks,a-w,a+w,b+w,b-w,{0,1,0});
            }
            ++base.runways;
        }else if(object.type=="MESH"&&object.mesh=="Tarmac2") {
            auto mesh=loadMesh(meshDirectory/"Tarmac2.msh");auto &g=group(object.texture[0]);
            for(auto &source:mesh.groups) {
                uint32_t first=(uint32_t)g.vertices.size();for(auto vertex:source.vertices)emit(g,vertex);
                for(auto index:source.indices)g.indices.push_back(first+index);
            }
        }else if(!object.type.empty()&&object.type!="RUNWAYLIGHTS")++base.omitted;
    };
    // Fallback ground cover for the supplied archive's missing local terrain tiles.
    // This rectangle supports visual orientation; it is not Florida coast/elevation data.
    auto &terrain=group("noise1",4);
    for(double x=-6500;x<15000;x+=250)for(double z=-6500;z<10500;z+=250)
        quad(terrain,{x,-.02,z},{x+250,-.02,z},{x+250,-.02,z+250},{x,-.02,z+250},{0,1,0},12,12);
    bool objects=false;std::string line;
    while(std::getline(file,line)) {
        line.resize(line.find(';')==std::string::npos?line.size():line.find(';'));
        std::replace(line.begin(),line.end(),'=',' ');std::istringstream s(line);std::string key;s>>key;
        if(key.empty())continue;
        if(key=="Location"){s>>base.longitude>>base.latitude;base.latitude*=RAD;base.longitude*=RAD;}
        if(key=="BEGIN_OBJECTLIST"){objects=true;continue;}
        if(key=="END_OBJECTLIST")break;
        if(!objects)continue;
        if(object.type.empty()){object=Object{};object.type=key;continue;}
        if(key=="END"){finish();object=Object{};continue;}
        if(key=="POS")s>>object.pos.x>>object.pos.y>>object.pos.z;
        if(key=="SCALE") { s>>object.scale.x;if(!(s>>object.scale.y>>object.scale.z))object.scale.y=object.scale.z=object.scale.x; }
        if(key=="ROT"){s>>object.rotation;object.rotation*=RAD;}
        if(key=="FILE")s>>object.mesh;
        if(key=="WIDTH")s>>object.width;
        if(key=="END1")s>>object.end1.x>>object.end1.y>>object.end1.z;
        if(key=="END2")s>>object.end2.x>>object.end2.y>>object.end2.z;
        if(key=="TEX")s>>object.texture[0];
        if(key=="TEX1"||key=="TEX2"||key=="TEX3"){int i=key.back()-'1';s>>object.texture[i]>>object.u[i]>>object.v[i];}
    }
    return base;
}
}
