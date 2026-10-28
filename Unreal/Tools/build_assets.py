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
