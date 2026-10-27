#pragma once
#include <array>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>
namespace native {
struct Vertex { float x,y,z,nx,ny,nz,u,v; };
struct Material { std::array<float,4> diffuse{1,1,1,1}; };
struct MeshGroup { std::vector<Vertex> vertices; std::vector<uint32_t> indices; size_t material=0,texture=0; std::string label; };
struct Mesh { std::vector<MeshGroup> groups; std::vector<Material> materials; std::vector<std::string> textures; };
Mesh loadMesh(const std::filesystem::path &path);
struct Image { uint32_t width=0,height=0; std::vector<uint8_t> rgba; };
Image loadDDS(const std::filesystem::path &path);
}
