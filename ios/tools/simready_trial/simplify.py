"""Blender step: simplify converted portable USD while retaining named moving parts.

blender -b --factory-startup --python ios/tools/simready_trial/simplify.py
"""
from pathlib import Path
import json
import bpy

ROOT=Path(__file__).resolve().parents[3]
WORK=ROOT/"tmp/simready-trial/converted"
OUT=ROOT/"ios/Salini/InsightAssets/SimReady"
stats={}
for role in ["forklift","rack","pallet"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=str(WORK/(role+".usdc")),import_cameras=False,import_lights=False,
                         import_textures_mode="IMPORT_NONE",support_scene_instancing=False,
                         merge_parent_xform=False)
    before=after=0
    for ob in list(bpy.data.objects):
        if ob.type!="MESH": continue
        bpy.context.view_layer.objects.active=ob
        n=sum(len(p.vertices)-2 for p in ob.data.polygons)
        before+=n
        if n>1500:
            modifier=ob.modifiers.new("Mobile detail",'DECIMATE')
            # Keep silhouettes and animation parts; body and racking have dense hidden detail.
            modifier.ratio=.18 if role=="forklift" else .15 if role=="rack" else .8
            modifier.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        after+=sum(len(p.vertices)-2 for p in ob.data.polygons)
    # Convert back from Blender Z-up to the Y-up frame expected by the scene.
    bpy.ops.wm.usd_export(filepath=str(OUT/(role+".usdc")),check_existing=False,
                         export_animation=False,export_lights=False,export_cameras=False,
                         export_textures_mode="KEEP",relative_paths=True,
                         convert_orientation=True,export_global_up_selection="Y",
                         export_global_forward_selection="NEGATIVE_Z",root_prim_path="/Asset",
                         generate_preview_surface=True,generate_materialx_network=False,
                         export_custom_properties=False,triangulate_meshes=True,
                         convert_scene_units="METERS")
    stats[role]={"triangles_before":before,"triangles_after":after}
(OUT/"geometry-stats.json").write_text(json.dumps(stats,indent=2)+"\n")
print(json.dumps(stats,indent=2))
