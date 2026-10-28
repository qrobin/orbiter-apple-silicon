"""Rebuild generated Unreal assets from versioned sources (UE 5.8 Python)."""
import unreal
import json
from pathlib import Path
assets = unreal.AssetToolsHelpers.get_asset_tools()
lib = unreal.MaterialEditingLibrary
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
    lib.connect_material_expressions(sample, 'RGB', multiply, 'A')
    lib.connect_material_expressions(tint, 'RGB', multiply, 'B')
    lib.connect_material_property(multiply, '', unreal.MaterialProperty.MP_BASE_COLOR)
    roughness = lib.create_material_expression(material, unreal.MaterialExpressionConstant, -200, 250)
    roughness.set_editor_property('r', .65)
    lib.connect_material_property(roughness, '', unreal.MaterialProperty.MP_ROUGHNESS)
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
    lib.connect_material_property(sample, 'RGB', unreal.MaterialProperty.MP_BASE_COLOR)
    rough = lib.create_material_expression(m, unreal.MaterialExpressionConstant, -200, 150)
    rough.set_editor_property('r', .75)
    lib.connect_material_property(rough, '', unreal.MaterialProperty.MP_ROUGHNESS)
    lib.recompile_material(m)
    unreal.EditorAssetLibrary.save_loaded_asset(m)
