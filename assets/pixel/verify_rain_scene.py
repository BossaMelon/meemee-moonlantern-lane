#!/usr/bin/env python3
"""Check asset registration against the supplied frozen E02 map, read-only."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from PIL import Image, ImageFilter
from build_rain_scene import ROOT, ROUTES

parser=argparse.ArgumentParser()
parser.add_argument("--map-source",required=True,type=Path)
args=parser.parse_args()
raw=args.map_source.read_bytes()
provenance=json.loads((ROOT/"rain-scene-provenance.json").read_text())
assert hashlib.sha256(raw).hexdigest()==provenance["geometry_reference"]["sha256"],"Map differs from reviewed geometry reference"
source=raw.decode()
def constant(name):
    tail=re.split(r"const "+name+r"\s*=\s*",source,maxsplit=1)[1]
    return json.JSONDecoder().raw_decode(tail)[0]
obstacles={o["id"]:o for o in constant("OBSTACLES")}
water=constant("WATER")[0]
routes=json.JSONDecoder().raw_decode(source.split('"routes":',1)[1])[0]
assert routes=={name:[list(p) for p in points] for name,points in ROUTES.items()},"Preview routes drifted from map"
m=json.loads((ROOT/"manifest.json").read_text())
assert m["backgrounds"]["rain_canal_shallow"]["logical_rect"]==[water["x"]-water["width"]/2,water["y"]-water["height"]/2,water["width"],water["height"]]
for name in ("garden_root_log_50","garden_root_log_45"):
    r=m["sprites"][name]; model=obstacles[r["placement_hint"]["model_id"]]
    assert r["placement_hint"]["model_center"]==[model["x"],model["y"]]
    x,y,w,h=r["footprint"]["rect"]; px,py=r["pivot"]
    assert [x-px,y-py,w,h]==[-model["width"]/2,-model["height"]/2,model["width"],model["height"]],name
    assert Image.open(ROOT/r["file"]).crop((x,y,x+w,y+h)).getchannel("A").getextrema()==(255,255),name
# Routes may have natural broken edges; their artwork stays within 8 logical px
# of every reference-line sample. This mask is QA only, never saved as art.
alpha=Image.open(ROOT/m["backgrounds"]["rain_ground_routes"]["file"]).getchannel("A")
near=alpha.filter(ImageFilter.MaxFilter(17)); samples=0
for points in ROUTES.values():
    for a,b in zip(points,points[1:]):
        steps=max(abs(b[0]-a[0]),abs(b[1]-a[1]))
        for i in range(steps+1):
            p=(round(a[0]+(b[0]-a[0])*i/steps),round(a[1]+(b[1]-a[1])*i/steps))
            assert near.getpixel(p),f"Route artwork too far from reference at {p}"
            samples+=1
print(json.dumps({"passed":True,"map_sha256":hashlib.sha256(raw).hexdigest(),"aligned_long_obstacles":2,"exact_water_rect":[340,335,340,120],"route_samples":samples,"max_allowed_route_edge_distance_px":8,"scope":"asset alignment only; no gameplay simulation"},indent=2))
