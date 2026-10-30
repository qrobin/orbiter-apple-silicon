#include "Mesh.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <sstream>
#include <stdexcept>
namespace native {
Mesh loadMesh(const std::filesystem::path &path) {
    std::ifstream f(path); if(!f) throw std::runtime_error("Cannot open spacecraft mesh: "+path.string());
    auto line=[&]() { std::string s; while(std::getline(f,s)) {
        auto c=s.find(';'); if(c!=std::string::npos) s.resize(c);
        if(s.find_first_not_of(" \r\t")!=std::string::npos) return s;
    } throw std::runtime_error("Truncated spacecraft mesh."); };
    if(line()!="MSHX1") throw std::runtime_error("Unsupported mesh format.");
    Mesh mesh; std::string tag; size_t count; std::string header=line();
    if(header=="STATICMESH") header=line();
    std::istringstream(header)>>tag>>count;
    if(tag!="GROUPS"||count>10000) throw std::runtime_error("Invalid mesh group count.");
    for(size_t n=0;n<count;++n) {
        MeshGroup g; size_t nv=0,nt=0; bool noNormal=false;
        while(true) {
            std::istringstream s(line()); s>>tag;
            if(tag=="MATERIAL") { s>>g.material; if(g.material) --g.material; }
            if(tag=="TEXTURE") s>>g.texture;
            if(tag=="LABEL") std::getline(s,g.label);
            if(tag=="NONORMAL") noNormal=true;
            if(tag=="GEOM") { s>>nv>>nt; break; }
        }
        if(nv>1000000||nt>1000000) throw std::runtime_error("Mesh geometry exceeds limits.");
        g.vertices.reserve(nv); g.indices.reserve(nt*3);
        for(size_t j=0;j<nv;++j) {
            Vertex v{}; std::istringstream s(line());
            if(!(s>>v.x>>v.y>>v.z)) throw std::runtime_error("Invalid mesh vertex.");
            if(noNormal) s>>v.u>>v.v;
            else s>>v.nx>>v.ny>>v.nz>>v.u>>v.v;
            g.vertices.push_back(v);
        }
        for(size_t j=0;j<nt;++j) {
            uint32_t a,b,c; std::istringstream s(line());
            if(!(s>>a>>b>>c)||a>=nv||b>=nv||c>=nv) throw std::runtime_error("Invalid mesh triangle.");
            g.indices.insert(g.indices.end(),{a,b,c});
        }
        if(noNormal) {
            for(size_t j=0;j<g.indices.size();j+=3) {
                auto &a=g.vertices[g.indices[j]],&b=g.vertices[g.indices[j+1]],&c=g.vertices[g.indices[j+2]];
                float ux=b.x-a.x,uy=b.y-a.y,uz=b.z-a.z,vx=c.x-a.x,vy=c.y-a.y,vz=c.z-a.z;
                float nx=uy*vz-uz*vy,ny=uz*vx-ux*vz,nz=ux*vy-uy*vx;
                for(auto *v:{&a,&b,&c}){v->nx+=nx;v->ny+=ny;v->nz+=nz;}
            }
            for(auto &v:g.vertices){float len=std::sqrt(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz);if(len>1e-12f){v.nx/=len;v.ny/=len;v.nz/=len;}else v.ny=1;}
        }
        mesh.groups.push_back(std::move(g));
    }
    std::istringstream(line())>>tag>>count;
    if(tag!="MATERIALS"||count>10000) throw std::runtime_error("Missing mesh materials.");
    for(size_t j=0;j<count;++j) line(); // material name list
    for(size_t j=0;j<count;++j) {
        line(); Material m; std::istringstream s(line());
        for(float &v:m.diffuse) s>>v;
        line(); line(); line(); mesh.materials.push_back(m);
    }
    if(mesh.materials.empty()) mesh.materials.emplace_back(); // Original base meshes may use MATERIAL 0.
    std::istringstream(line())>>tag>>count;
    if(tag!="TEXTURES"||count>10000) throw std::runtime_error("Missing mesh textures.");
    for(size_t j=0;j<count;++j) { std::string name; std::istringstream(line())>>name;
        std::replace(name.begin(),name.end(),'\\','/'); mesh.textures.push_back(name); }
    for(auto &g:mesh.groups) {
        // The original ISS mesh repeats two material slots and numbers its
        // last two slots beyond MATERIALS 36. Its texture slots identify the
        // matching original materials for these six groups.
        if(path.filename()=="ProjectAlpha_ISS.msh"&&g.texture>0&&g.texture<=mesh.materials.size()&&g.material!=g.texture-1)
            g.material=g.texture-1;
        if(g.material>=mesh.materials.size()||g.texture>mesh.textures.size())
            throw std::runtime_error("Mesh references an invalid material or texture: "+path.string());
    }
    return mesh;
}
static uint32_t u32(const uint8_t *p) { return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24; }
static std::array<uint8_t,4> rgb565(uint16_t n) {
    return {uint8_t(((n>>11)&31)*255/31),uint8_t(((n>>5)&63)*255/63),uint8_t((n&31)*255/31),255};
}
Image loadDDS(const std::filesystem::path &path) {
    std::ifstream f(path,std::ios::binary); if(!f) throw std::runtime_error("Missing texture: "+path.string());
    std::vector<uint8_t> data((std::istreambuf_iterator<char>(f)),{});
    if(data.size()<128||std::memcmp(data.data(),"DDS ",4)||u32(data.data()+4)!=124)
        throw std::runtime_error("Invalid DDS header.");
    Image img; img.height=u32(data.data()+12); img.width=u32(data.data()+16);
    if(!img.width||!img.height||img.width>8192||img.height>8192) throw std::runtime_error("Invalid DDS dimensions.");
    img.rgba.resize(size_t(img.width)*img.height*4);
    uint32_t fourcc=u32(data.data()+84); size_t offset=128;
    const uint32_t DXT1=0x31545844,DXT3=0x33545844,DXT5=0x35545844;
    if(fourcc==DXT1||fourcc==DXT3||fourcc==DXT5) {
        size_t blockSize=fourcc==DXT1?8:16;
        for(uint32_t by=0;by<img.height;by+=4) for(uint32_t bx=0;bx<img.width;bx+=4) {
            if(offset+blockSize>data.size()) throw std::runtime_error("Truncated DDS block.");
            const uint8_t *b=data.data()+offset; offset+=blockSize;
            uint8_t alpha[16]; std::fill(alpha,alpha+16,255);
            if(fourcc==DXT3) { for(int i=0;i<16;++i) alpha[i]=((b[i/2]>>(4*(i%2)))&15)*17; b+=8; }
            if(fourcc==DXT5) {
                uint8_t a[8]={b[0],b[1]};
                if(a[0]>a[1]) for(int i=2;i<8;++i) a[i]=((8-i)*a[0]+(i-1)*a[1])/7;
                else { for(int i=2;i<6;++i) a[i]=((6-i)*a[0]+(i-1)*a[1])/5; a[6]=0; a[7]=255; }
                uint64_t bits=0; for(int i=0;i<6;++i) bits|=uint64_t(b[2+i])<<(8*i);
                for(int i=0;i<16;++i) alpha[i]=a[(bits>>(3*i))&7]; b+=8;
            }
            uint16_t c0=b[0]|b[1]<<8,c1=b[2]|b[3]<<8;
            std::array<uint8_t,4> colors[4]={rgb565(c0),rgb565(c1),{}, {}};
            for(int ch=0;ch<3;++ch) {
                if(c0>c1||fourcc!=DXT1) { colors[2][ch]=(2*colors[0][ch]+colors[1][ch])/3; colors[3][ch]=(colors[0][ch]+2*colors[1][ch])/3; }
                else { colors[2][ch]=(colors[0][ch]+colors[1][ch])/2; colors[3][ch]=0; }
            }
            colors[2][3]=255; colors[3][3]=(c0>c1||fourcc!=DXT1)?255:0;
            uint32_t bits=u32(b+4);
            for(int i=0;i<16;++i) {
                uint32_t x=bx+i%4,y=by+i/4; if(x>=img.width||y>=img.height) continue;
                auto c=colors[(bits>>(2*i))&3]; c[3]=uint8_t(unsigned(c[3])*alpha[i]/255);
                std::copy(c.begin(),c.end(),img.rgba.begin()+(size_t(y)*img.width+x)*4);
            }
        }
    } else if(fourcc==0) {
        uint32_t bits=u32(data.data()+88), bytes=bits/8;
        if(bits!=24&&bits!=32) throw std::runtime_error("Unsupported DDS pixel format.");
        uint32_t masks[4]; for(int i=0;i<4;++i) masks[i]=u32(data.data()+92+i*4);
        size_t stride=std::max(size_t(img.width)*bytes,size_t(u32(data.data()+20)));
        if(stride>size_t(img.width)*bytes+4096||128+stride*img.height>data.size()) throw std::runtime_error("Truncated DDS pixels.");
        for(uint32_t y=0;y<img.height;++y) for(uint32_t x=0;x<img.width;++x) {
            const uint8_t *p=data.data()+128+y*stride+x*bytes;
            uint32_t value=0; for(uint32_t j=0;j<bytes;++j) value|=uint32_t(p[j])<<(8*j);
            for(int c=0;c<4;++c) {
                uint32_t mask=masks[c]; uint8_t v=c==3?255:0;
                if(mask) { unsigned shift=__builtin_ctz(mask); v=uint8_t(((value&mask)>>shift)*255/(mask>>shift)); }
                img.rgba[(size_t(y)*img.width+x)*4+c]=v;
            }
        }
    } else throw std::runtime_error("Unsupported DDS compression.");
    return img;
}
}
