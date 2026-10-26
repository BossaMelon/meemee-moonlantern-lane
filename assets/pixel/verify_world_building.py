#!/usr/bin/env python3
"""Bounded geometry/seam/preservation checks for the seven new art modules."""
import hashlib
import json
import subprocess
from PIL import Image
from build_world_building import ROOT, BASE, SET, EVIDENCE, furniture, wall, content

checks=0
def require(ok,message):
    global checks
    checks+=1
    if not ok:raise AssertionError(message)

m=json.loads((ROOT/"manifest.json").read_text())
new={n:r for n,r in m["sprites"].items() if r.get("asset_set")==SET}
require(len(new)==7,"Expected exactly seven kit modules")
top=content(m,"world_wood_top")
require(top.size==(32,16),"Top grid")
require(all(top.getpixel((0,y))==top.getpixel((31,y)) for y in range(16)),"Top horizontal seam")
require(all(top.getpixel((x,0))==top.getpixel((x,15)) for x in range(32)),"Top vertical seam")
require(len(top.getcolors())<=3,"Quiet top palette")
require(max(n for n,c in top.getcolors())>=32*16*.85,"Top must remain mostly quiet")
layout_path=ROOT.parent.parent/"tests/fixtures/world-slice-scenarios.json"
layout=json.loads(layout_path.read_text())["configuration"]["layout"]
examples={"storage-body":(96,112),"prep-body":(128,80),"stove-body":(112,80),"pass-body":(144,64),"table-1":(96,64),"recipe-body":(40,32),"ledger-body":(60,48)}
colliders={c["id"]:c for c in layout["regions"]["shop"]["colliders"]}
for key,(w,h) in examples.items():
    c=colliders[key]
    require((c["width"],c["height"])==(w,h),f"Fixture dimensions changed: {key}")
    im=furniture(m,w,h)
    require(im.size==(w,h+24),f"Fixed front height: {key}")
    require(im.getchannel("A").getextrema()==(255,255),f"Visible surface/base coverage: {key}")
    # Footprint local y starts at24. It must have zero invisible collider area.
    require(im.crop((0,24,w,h+24)).getchannel("A").getextrema()==(255,255),f"Footprint holes: {key}")
for region in layout["regions"].values():
    for c in region["colliders"]:
        w,h=c["width"],c["height"]
        if w!=24 and h!=24:continue
        im=wall(m,w,h)
        require(im.size==(w,h+64),f"Fixed wall height: {c['id']}")
        require(im.getchannel("A").getextrema()==(255,255),f"Wall seam/hole: {c['id']}")
        # Arbitrary lengths crop repeat tiles; they never scale the64px front.
        require(im.crop((0,h,w,h+64)).height==64,f"Wall front: {c['id']}")
n,s=colliders["shop-e-n"],colliders["shop-e-s"]
require(s["y"]-s["height"]/2-(n["y"]+n["height"]/2)==120,"Real east opening changed")
old=json.loads(subprocess.check_output(["git","show",BASE+":assets/pixel/manifest.json"]))
for section in ["sprites","backgrounds","animations","sources"]:
    for name,rec in old[section].items():require(m[section][name]==rec,f"Legacy record changed: {section}/{name}")
for key in old:
    if key not in ["sprites","sources"]:require(m[key]==old[key],f"Legacy top-level manifest field: {key}")
preserved=[]
entries=subprocess.check_output(["git","ls-tree","-rz",BASE,"--","assets/pixel"]).split(b"\0")
for entry in entries:
    if not entry:continue
    meta,name=entry.split(b"\t",1); path=name.decode()
    if path=="assets/pixel/manifest.json":continue
    mode,kind,expected=meta.decode().split()
    data=(ROOT.parent.parent/path).read_bytes()
    actual=hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
    require(actual==expected,f"Legacy bytes changed: {path}")
    preserved.append(path)
report={"passed":True,"checks":checks,"base":BASE,"asset_ids":sorted(new),
        "legacy_files_byte_identical":len(preserved),"legacy_sprite_records":len(old["sprites"]),
        "legacy_source_records":len(old["sources"]),"fixture_sha256":hashlib.sha256(layout_path.read_bytes()).hexdigest(),
        "scope":"asset geometry, seams, footprint coverage and preservation; not UI input/runtime/fullscreen proof"}
EVIDENCE.mkdir(parents=True,exist_ok=True)
(EVIDENCE/"verification.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
