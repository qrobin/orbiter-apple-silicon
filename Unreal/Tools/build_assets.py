"""Rebuild generated Unreal assets from versioned sources (UE 5.8 Python)."""
import unreal
import json
from pathlib import Path
assets = unreal.AssetToolsHelpers.get_asset_tools()
lib = unreal.MaterialEditingLibrary
def connect(source, output, destination, input_name):
    if not lib.connect_material_expressions(source, output, destination, input_name):
        raise RuntimeError('Material connection failed: %s -> %s.%s; inputs=%s' % (source.get_name(), destination.get_name(), input_name, lib.get_material_expression_input_names(destination)))

def property_link(source, output, property_name):
    if not lib.connect_material_property(source, output, property_name):
        raise RuntimeError('Material property connection failed: %s -> %s' % (source.get_name(), property_name))
# Upgrade only these generated materials; large imported textures remain cached.
generated_versions = {'M_Orbiter': '2', 'M_Earth': '2', 'M_Exhaust': '3', 'M_Flame': '1'}
for name, version in generated_versions.items():
    asset_path = '/Game/Materials/' + name
    previous = unreal.load_asset(asset_path)
    if previous and unreal.EditorAssetLibrary.get_metadata_tag(previous, 'OrbiterGeneratorVersion') != version:
        if not unreal.EditorAssetLibrary.delete_asset(asset_path):
            raise RuntimeError('Cannot upgrade generated material ' + asset_path)
path = '/Game/Materials/M_Orbiter'
material = unreal.load_asset(path)
if material is None:
    material = assets.create_asset('M_Orbiter', '/Game/Materials', unreal.Material, unreal.MaterialFactoryNew())
    material.set_editor_property('two_sided', True)
    sample = lib.create_material_expression(material, unreal.MaterialExpressionTextureSampleParameter2D, -500, -100)
    sample.set_editor_property('parameter_name', 'Diffuse')
    sample.set_editor_property('texture', unreal.load_asset('/Engine/EngineResources/WhiteSquareTexture'))
    tint = lib.create_material_expression(material, unreal.MaterialExpressionVectorParameter, -500, 150)
    tint.set_editor_property('parameter_name', 'Tint')
    tint.set_editor_property('default_value', unreal.LinearColor(1, 1, 1, 1))
    multiply = lib.create_material_expression(material, unreal.MaterialExpressionMultiply, -200, 0)
    connect(sample, '', multiply, 'A')
    connect(tint, '', multiply, 'B')
    property_link(multiply, '', unreal.MaterialProperty.MP_BASE_COLOR)
    roughness = lib.create_material_expression(material, unreal.MaterialExpressionConstant, -200, 250)
    roughness.set_editor_property('r', .65)
    property_link(roughness, '', unreal.MaterialProperty.MP_ROUGHNESS)
    lib.recompile_material(material)
    unreal.EditorAssetLibrary.save_loaded_asset(material)
cloud = unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst')
if cloud:
    parameters = {str(n): lib.get_material_instance_scalar_parameter_value(cloud, n) for n in lib.get_scalar_parameter_names(cloud)}
    output = Path(__file__).resolve().parents[1] / 'Content' / 'Generated'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'cloud_parameters.json').write_text(json.dumps(parameters, indent=2))
unreal.log('ORBITER_ASSETS_READY')

# Scientific source imagery stays versioned; Unreal import products are rebuilt.
earth = unreal.load_asset('/Game/Textures/T_Earth_Day')
if earth is None:
    task = unreal.AssetImportTask()
    task.filename = str(Path(__file__).resolve().parents[1] / 'SourceAssets' / 'Earth-May-8K.jpg')
    task.destination_path = '/Game/Textures'
    task.destination_name = 'T_Earth_Day'
    task.automated = True
    task.save = True
    assets.import_asset_tasks([task])
    earth = unreal.load_asset('/Game/Textures/T_Earth_Day')
    if earth is None:
        raise RuntimeError('NASA Earth texture import failed')
    earth.set_editor_property('max_texture_size', 8192)
    earth.set_editor_property('srgb', True)
    earth.set_editor_property('address_y', unreal.TextureAddress.TA_CLAMP)
    unreal.EditorAssetLibrary.save_loaded_asset(earth)
if unreal.load_asset('/Game/Materials/M_Earth') is None:
    m = assets.create_asset('M_Earth', '/Game/Materials', unreal.Material, unreal.MaterialFactoryNew())
    sample = lib.create_material_expression(m, unreal.MaterialExpressionTextureSample, -500, 0)
    sample.set_editor_property('texture', earth)
    property_link(sample, '', unreal.MaterialProperty.MP_BASE_COLOR)
    rough = lib.create_material_expression(m, unreal.MaterialExpressionConstant, -200, 150)
    rough.set_editor_property('r', .75)
    property_link(rough, '', unreal.MaterialProperty.MP_ROUGHNESS)
    lib.recompile_material(m)
    unreal.EditorAssetLibrary.save_loaded_asset(m)
if unreal.load_asset('/Game/Materials/M_Exhaust') is None:
    m = assets.create_asset('M_Exhaust', '/Game/Materials', unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property('blend_mode', unreal.BlendMode.BLEND_ADDITIVE)
    m.set_editor_property('shading_model', unreal.MaterialShadingModel.MSM_UNLIT)
    m.set_editor_property('two_sided', True)
    uv = lib.create_material_expression(m, unreal.MaterialExpressionTextureCoordinate, -900, 0)
    center = lib.create_material_expression(m, unreal.MaterialExpressionSubtract, -700, 0)
    center.set_editor_property('const_b', .5)
    connect(uv, '', center, 'A')
    radius = lib.create_material_expression(m, unreal.MaterialExpressionDotProduct, -500, 0)
    connect(center, '', radius, 'A')
    connect(center, '', radius, 'B')
    scale = lib.create_material_expression(m, unreal.MaterialExpressionMultiply, -350, 0)
    scale.set_editor_property('const_b', 4)
    connect(radius, '', scale, 'A')
    inverse = lib.create_material_expression(m, unreal.MaterialExpressionOneMinus, -200, 0)
    connect(scale, '', inverse, '')
    clamp = lib.create_material_expression(m, unreal.MaterialExpressionClamp, -50, 0)
    connect(inverse, '', clamp, '')
    falloff = lib.create_material_expression(m, unreal.MaterialExpressionPower, 100, 0)
    falloff.set_editor_property('const_exponent', 3)
    connect(clamp, '', falloff, 'Base')
    color = lib.create_material_expression(m, unreal.MaterialExpressionVertexColor, -200, 300)
    opacity = lib.create_material_expression(m, unreal.MaterialExpressionMultiply, 300, 0)
    connect(falloff, '', opacity, 'A')
    connect(color, 'A', opacity, 'B')
    depth = lib.create_material_expression(m, unreal.MaterialExpressionDepthFade, 500, 0)
    depth.set_editor_property('fade_distance_default', 6)
    connect(opacity, '', depth, 'Opacity')
    property_link(depth, '', unreal.MaterialProperty.MP_OPACITY)
    emission = lib.create_material_expression(m, unreal.MaterialExpressionMultiply, 100, 300)
    emission.set_editor_property('const_b', 70000)
    connect(color, '', emission, 'A')
    property_link(emission, '', unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    lib.recompile_material(m)
    unreal.EditorAssetLibrary.save_loaded_asset(m)

if unreal.load_asset('/Game/Materials/M_Flame') is None:
    m = assets.create_asset('M_Flame', '/Game/Materials', unreal.Material, unreal.MaterialFactoryNew())
    m.set_editor_property('blend_mode', unreal.BlendMode.BLEND_ADDITIVE)
    m.set_editor_property('shading_model', unreal.MaterialShadingModel.MSM_UNLIT)
    m.set_editor_property('two_sided', True)
    color = lib.create_material_expression(m, unreal.MaterialExpressionVertexColor, -400, 0)
    emission = lib.create_material_expression(m, unreal.MaterialExpressionMultiply, -150, 0)
    emission.set_editor_property('const_b', 120000)
    connect(color, '', emission, 'A')
    property_link(emission, '', unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    property_link(color, 'A', unreal.MaterialProperty.MP_OPACITY)
    lib.recompile_material(m)
    unreal.EditorAssetLibrary.save_loaded_asset(m)

for name, version in generated_versions.items():
    generated = unreal.load_asset('/Game/Materials/' + name)
    if generated is None:
        raise RuntimeError('Generated material missing: ' + name)
    unreal.EditorAssetLibrary.set_metadata_tag(generated, 'OrbiterGeneratorVersion', version)
    unreal.EditorAssetLibrary.save_loaded_asset(generated, only_if_is_dirty=False)
