"""Write measured replacement locations and movable-part identities for the trial."""
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/"ios/Salini/InsightAssets/SimReady"
def transform(x=0,y=0,z=0,ry=0,scale=1):
    return {"translation":[x,y,z],"rotationDegrees":[0,ry,0],"scale":scale}
manifest={
    "forklift":{
        "file":"forklift.usdc","transform":transform(),
        "carriage":["sm_fork1_c01_mesh_00","sm_fork2_c01_mesh_00","sm_mast_stage3_c01_mesh_00","sm_mast_stage4_c01_mesh_00"],
        "mast":["sm_mast_stage1_c01_mesh_00","sm_mast_stage2_c01_mesh_00"],
        "wheels":[{"name":f"sm_wheel{i}_c01_mesh_00","steers":i in [1,2]} for i in range(1,5)],
        "mastPivot":[-.16,.15,0]
    },
    "batchPallet":{"file":"pallet.usdc","transform":transform(),"removeBelowY":.14001},
    "props":[
        {"id":"racks","file":"rack.usdc",
         "placements":[transform(3.95,1.2,z,90) for z in [12.25,14.95,17.65]],
         "removeRegions":[{"min":[3.30,1.205,10.80],"max":[4.60,7.40,19.10]}]},
        {"id":"pallet_stack","file":"pallet.usdc",
         "placements":[transform(7,1.2+i*.145,17.8) for i in range(6)],
         "removeRegions":[{"min":[6.49,1.205,17.19],"max":[7.51,2.08,18.41]}]}
    ]
}
(OUT/"simready.json").write_text(json.dumps(manifest,indent=2)+"\n")
(ROOT/"tmp/simready-trial/contract.json").write_text(json.dumps(manifest,indent=2)+"\n")
files=[{"path":str(f.relative_to(OUT)),"bytes":f.stat().st_size,"sha256":hashlib.sha256(f.read_bytes()).hexdigest()}
       for f in sorted(OUT.rglob('*')) if f.is_file() and f.name!='checksums.json']
(OUT/"checksums.json").write_text(json.dumps(files,indent=2)+"\n")
print('Wrote manifest and checksums:',len(files),'files')
