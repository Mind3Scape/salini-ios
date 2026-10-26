"""Prepare three NVIDIA assets as portable, textured USD for the Salini trial.

Run with usd-core, numpy and Pillow. No MDL/physics runtime is required in the app.
USD instance proxies are expanded, UDIM textures become a single horizontal atlas,
and texture inputs are reconstructed as standard UsdPreviewSurface networks.
"""
from pathlib import Path
import hashlib
import json
import shutil
import math
import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdShade, Gf, Sdf, Vt

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "tmp/simready-trial/source"
OUT = ROOT / "ios/Salini/InsightAssets/SimReady"
WORK = ROOT / "tmp/simready-trial/converted"
NAMES = {"forklift": "vehicle_forklift_red_c01", "rack": "rack_bulk_storage_a03", "pallet": "pallet_a01"}
TEXTURES = {}

def portable_texture(asset, pattern, channel=None):
    key = (asset, pattern, channel)
    if key in TEXTURES:
        return TEXTURES[key]
    name = Path(pattern).name
    files = sorted((SOURCE / asset / "simready_usd/source_assets").glob(name.replace("<UDIM>", "*")))
    if not files:
        files = sorted((SOURCE / asset / "simready_usd/Textures").glob(name.replace("<UDIM>", "*")))
    if not files:
        raise FileNotFoundError((asset, name))
    udim = "<UDIM>" in name
    count = max(int(f.stem.split('.')[-1])-1000 for f in files) if udim else 1
    # Eight forklift tiles fit a 4096 × 512 atlas. Other objects use 1024 maps.
    size = min(1024, 4096 // count)
    canvas = Image.new("RGB", (size * count, size))
    for f in files:
        im = Image.open(f).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
        if channel is not None:
            im = im.getchannel(channel).convert("RGB")
        tile = int(f.stem.split('.')[-1])-1001 if udim else 0
        canvas.paste(im, (tile * size, 0))
    stem = name.replace('.<UDIM>', '').replace('.png','') + ("_"+channel if channel else "")
    dest = OUT / "textures" / (stem + ".jpg")
    canvas.save(dest, quality=92, subsampling=0)
    TEXTURES[key] = (dest, count)
    return dest, count

def source_material(mat):
    shader = UsdShade.Shader(mat.GetPrim().GetChild("Principled_BSDF"))
    mdl = UsdShade.Shader(mat.GetPrim().GetChild("OmniPBR_Shader"))
    def value(key, default):
        inp = shader.GetInput(key)
        return inp.Get() if inp and inp.Get() is not None else default
    color = value("diffuseColor", (0.5, 0.5, 0.5))
    if mdl and mdl.GetInput("diffuse_color_constant"):
        color = mdl.GetInput("diffuse_color_constant").Get()
    maps = {}
    for key in ["Albedo", "ORM", "Normal"]:
        node = UsdShade.Shader(mat.GetPrim().GetChild(key))
        if node and node.GetInput("file"):
            maps[key] = node.GetInput("file").Get().path
    mapping = UsdShade.Shader(mat.GetPrim().GetChild("Mapping"))
    scale = mapping.GetInput("scale").Get() if mapping and mapping.GetInput("scale") else (1, 1)
    return {"color":tuple(color), "roughness":value("roughness",0.65), "metallic":value("metallic",0),
            "opacity":value("opacity",1), "maps":maps,"uvScale":tuple(scale)}

def author_material(stage, asset, name, spec):
    mat = UsdShade.Material.Define(stage, "/Asset/Materials/" + name)
    surf = UsdShade.Shader.Define(stage, mat.GetPath().AppendChild("Surface"))
    surf.CreateIdAttr("UsdPreviewSurface")
    surf.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*spec["color"]))
    for key in ["roughness","metallic","opacity"]:
        surf.CreateInput(key,Sdf.ValueTypeNames.Float).Set(float(spec[key]))
    mat.CreateSurfaceOutput().ConnectToSource(surf.ConnectableAPI(),"surface")
    uv = UsdShade.Shader.Define(stage, mat.GetPath().AppendChild("UV"))
    uv.CreateIdAttr("UsdPrimvarReader_float2")
    uv.CreateInput("varname",Sdf.ValueTypeNames.Token).Set("st")
    atlas_count = 1
    for key, pattern in spec["maps"].items():
        channels = [("roughness","G"),("metallic","B")] if key == "ORM" else [("diffuseColor" if key == "Albedo" else "normal",None)]
        for target, channel in channels:
            path,count = portable_texture(asset,pattern,channel)
            atlas_count = max(atlas_count,count)
            tex = UsdShade.Shader.Define(stage,mat.GetPath().AppendChild(target+"Texture"))
            tex.CreateIdAttr("UsdUVTexture")
            tex.CreateInput("file",Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(str(path)))
            tex.CreateInput("sourceColorSpace",Sdf.ValueTypeNames.Token).Set("sRGB" if key=="Albedo" else "raw")
            tex.CreateInput("wrapS",Sdf.ValueTypeNames.Token).Set("repeat")
            tex.CreateInput("wrapT",Sdf.ValueTypeNames.Token).Set("repeat")
            tex.CreateInput("st",Sdf.ValueTypeNames.Float2).ConnectToSource(uv.ConnectableAPI(),"result")
            if key == "Normal":
                tex.CreateInput("scale",Sdf.ValueTypeNames.Float4).Set((2,2,2,2))
                tex.CreateInput("bias",Sdf.ValueTypeNames.Float4).Set((-1,-1,-1,-1))
            typ = Sdf.ValueTypeNames.Float if channel else Sdf.ValueTypeNames.Normal3f if key=="Normal" else Sdf.ValueTypeNames.Color3f
            surf.CreateInput(target,typ).ConnectToSource(tex.ConnectableAPI(),"r" if channel else "rgb")
    return mat,atlas_count

def transform_points(points, role):
    p = points.copy()
    if role == "forklift":
        # Forward is source −Y. Fork heel y=−1.328. All source geometry scales uniformly;
        # the carriage is lowered to its rest pose (the timeline adds the current lift).
        x=(-p[:,1]-1.328)*.88
        # Adapt the chassis behind the front axle to the existing 2 m swept envelope.
        # The forward mast/fork geometry is unchanged; rear wheelbase becomes ~1.22 m.
        x=np.where(x < -.45, -.45+(x+.45)*.837, x)
        return np.column_stack((x,p[:,2]*.88,-p[:,0]*.88))
    if role == "rack":
        return np.column_stack((p[:,0],p[:,2],-p[:,1]))
    # Match the demonstration's existing transport cradle footprint and deck height.
    return np.column_stack((p[:,1]/.800385773, p[:,2]*(.14/.208645657), p[:,0]*(1.8/1.204201818)))

def build(role, asset):
    src = SOURCE / asset / "simready_usd" / ("sm_"+asset+"_01.usd")
    source = Usd.Stage.Open(str(src))
    dest = WORK/(role+".usdc")
    stage = Usd.Stage.CreateNew(str(dest))
    root = UsdGeom.Xform.Define(stage,"/Asset")
    stage.SetDefaultPrim(root.GetPrim())
    UsdGeom.SetStageUpAxis(stage,UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage,1)
    cache = UsdGeom.XformCache()
    materials = {}
    parts = []
    points_total = faces_total = 0
    for prim in Usd.PrimRange.Stage(source,Usd.TraverseInstanceProxies()):
        if not prim.IsA(UsdGeom.Mesh): continue
        mesh = UsdGeom.Mesh(prim)
        pos = np.asarray(mesh.GetPointsAttr().Get(),dtype=np.float64)
        world = np.asarray(cache.GetLocalToWorldTransform(prim))
        pos = (np.column_stack((pos,np.ones(len(pos)))) @ world)[:,:3]
        pos = transform_points(pos,role)
        name = prim.GetName()
        moving_carriage = role=="forklift" and any(k in name for k in ["sm_fork1_","sm_fork2_","sm_mast_stage3_","sm_mast_stage4_"])
        if moving_carriage:
            # Fork underside 0.104 m, heel/deck top ~0.16: shift so the top is 0.06 at rest.
            pos[:,1] -= .08
        counts = np.asarray(mesh.GetFaceVertexCountsAttr().Get(),dtype=np.int32)
        indices = np.asarray(mesh.GetFaceVertexIndicesAttr().Get(),dtype=np.int32)
        starts = np.r_[0,np.cumsum(counts)]
        pv = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
        uv = np.asarray(pv.ComputeFlattened(),dtype=np.float32) if pv else np.zeros((len(indices),2),dtype=np.float32)
        if pv and pv.GetInterpolation() in ["vertex","varying"]: uv=uv[indices]
        normals=mesh.GetNormalsAttr().Get()
        transformed_normals=None
        if normals:
            normals=np.asarray(normals,dtype=np.float64)
            if mesh.GetNormalsInterpolation() in ["vertex","varying"]: normals=normals[indices]
            conversion=(np.array([[0,0,-.88],[-.88,0,0],[0,.88,0]]) if role=="forklift" else
                        transform_points(np.eye(3),role)-transform_points(np.zeros((3,3)),role))
            transformed_normals=normals @ np.linalg.inv(world[:3,:3] @ conversion).T
            if role=="forklift":
                transformed_normals[pos[indices,0] < -.45,0]/=.837
            transformed_normals/=np.maximum(np.linalg.norm(transformed_normals,axis=1,keepdims=True),1e-9)
        default_mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        grouped = []
        assigned = set()
        for subset in UsdGeom.Subset.GetAllGeomSubsets(mesh):
            mat = UsdShade.MaterialBindingAPI(subset.GetPrim()).ComputeBoundMaterial()[0]
            if not mat: continue
            face_ids = list(subset.GetIndicesAttr().Get())
            grouped.append((mat,face_ids)); assigned.update(face_ids)
        remainder=[i for i in range(len(counts)) if i not in assigned]
        if remainder:
            if not default_mat: raise ValueError('Unbound faces: '+str(prim.GetPath()))
            grouped.append((default_mat,remainder))
        parent = UsdGeom.Xform.Define(stage,"/Asset/"+name)
        parts.append(name)
        for k,(mat,face_ids) in enumerate(grouped):
            mat_name=mat.GetPrim().GetName()
            if mat_name not in materials:
                spec=source_material(mat)
                material,n=author_material(stage,asset,mat_name,spec)
                materials[mat_name]=(material,n,spec)
            material,n,spec=materials[mat_name]
            corners=np.concatenate([np.arange(starts[f],starts[f+1]) for f in face_ids])
            old_idx=indices[corners]
            unique, new_idx=np.unique(old_idx,return_inverse=True)
            pts=pos[unique].astype(np.float32)
            uvs=uv[corners].copy()*np.asarray(spec['uvScale'])
            uvs[:,0]/=n
            target=UsdGeom.Mesh.Define(stage,parent.GetPath().AppendChild("part_"+str(k)))
            target.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(pts))
            target.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(counts[face_ids]))
            target.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(new_idx.astype(np.int32)))
            target.CreateSubdivisionSchemeAttr("none")
            target.CreateDoubleSidedAttr(True)
            if transformed_normals is not None:
                target.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(transformed_normals[corners].astype(np.float32)))
                target.SetNormalsInterpolation("faceVarying")
            UsdGeom.PrimvarsAPI(target).CreatePrimvar("st",Sdf.ValueTypeNames.TexCoord2fArray,"faceVarying").Set(Vt.Vec2fArray.FromNumpy(uvs.astype(np.float32)))
            UsdShade.MaterialBindingAPI.Apply(target.GetPrim()).Bind(material)
            points_total+=len(pts); faces_total+=len(face_ids)
    stage.GetRootLayer().Save()
    license_dest=OUT/(asset+"-LICENSE.txt")
    shutil.copyfile(SOURCE/asset/".metadata/LICENSE.txt",license_dest)
    return {"asset":asset,"role":role,"source_points":points_total,"source_polygons":faces_total,"parts":parts,
            "license":"CC-BY-4.0","license_file":license_dest.name,"changes":"Expanded instances; converted axes and materials to UsdPreviewSurface; atlas/resized textures; mobile geometry simplification. Forklift scaled 0.88 with chassis shortened behind front axle to fit the existing 2 m route envelope; this adapted model is not an equipment specification. Pallet resized to existing transport cradle."}

def main():
    (OUT/"textures").mkdir(parents=True,exist_ok=True)
    WORK.mkdir(parents=True,exist_ok=True)
    result=[build(role,asset) for role,asset in NAMES.items()]
    revision=json.loads((SOURCE.parent/"download-manifest.json").read_text())["revision"]
    for r in result: r["source"]=f'https://huggingface.co/datasets/nvidia/simready-assets/tree/{revision}/{r["asset"]}'
    (OUT/"ASSETS.json").write_text(json.dumps({"author":"NVIDIA","revision":revision,"assets":result},indent=2)+"\n")
    print(json.dumps(result,indent=2))

if __name__ == "__main__": main()
