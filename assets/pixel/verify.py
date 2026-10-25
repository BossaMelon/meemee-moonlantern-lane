#!/usr/bin/env python3
"""Check the shipping PNG contract, not gameplay or subjective visual quality."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parent
m=json.loads((ROOT/"manifest.json").read_text())
allowed={tuple(bytes.fromhex(c[1:])) for c in m["palette"]}
checks=0

def require(ok, message):
    global checks
    checks+=1
    if not ok:
        raise AssertionError(message)

for kind in ("sprites","backgrounds"):
    for name,rec in m[kind].items():
        path=ROOT/rec["file"]
        require(path.is_file(),f"Missing {path}")
        require(hashlib.sha256(path.read_bytes()).hexdigest()==rec["sha256"],f"Stale checksum {name}")
        im=Image.open(path)
        require(im.mode=="RGBA" and list(im.size)==rec["size"],f"Format/dimensions {name}")
        pixels={color for count,color in im.getcolors(maxcolors=im.width*im.height)}
        require(all(p[3] in (0,255) for p in pixels),f"Soft alpha {name}")
        require(all(p[:3] in allowed for p in pixels if p[3]),f"Palette drift {name}")
        require(all(p==(0,0,0,0) for p in pixels if not p[3]),f"Hidden RGB fringe {name}")
        require(bool(im.getbbox()),f"Empty asset {name}")
        if kind=="sprites":
            require(im.getchannel("A").getextrema()[0]==0,f"Opaque background {name}")
            atlas=Image.open(ROOT/rec["atlas"])
            x,y,w,h=rec["region"]
            require(x>=0 and y>=0 and x+w<=atlas.width and y+h<=atlas.height,f"Invalid region {name}")
            require(atlas.crop((x,y,x+w,y+h)).tobytes()==im.tobytes(),f"Atlas mismatch {name}")
            require(0<=rec["pivot"][0]<=w and 0<=rec["pivot"][1]<=h,f"Invalid pivot {name}")
            require(list(im.getbbox())==rec["opaque_bounds"],f"Stale bounds {name}")
for name,rec in m["sources"].items():
    require(hashlib.sha256((ROOT/"source"/name).read_bytes()).hexdigest()==rec["sha256"],f"Changed source {name}")
for name,animation in m["animations"].items():
    require(all(frame in m["sprites"] for frame in animation["frames"]),f"Missing animation frame {name}")
    require(len(animation["frames"])==len(animation["duration_ms"]),f"Timing mismatch {name}")
    require(all(t>0 for t in animation["duration_ms"]),f"Invalid frame duration {name}")
layout=json.loads((ROOT/"restaurant-layout.json").read_text())
require(layout["background"] in m["backgrounds"],"Missing room shell")
for entry in layout["draw_order"]:
    require(entry["sprite"] in m["sprites"],f"Missing layout sprite {entry['sprite']}")
    require(0<=entry["foot"][0]<384 and 0<=entry["foot"][1]<256,"Invalid room anchor")
print(json.dumps({"passed":True,"checks":checks,"sprites":len(m["sprites"]),"backgrounds":len(m["backgrounds"]),"palette_colors":len(allowed),"scope":"asset encoding, references and packaging only"},indent=2))
