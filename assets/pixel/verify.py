#!/usr/bin/env python3
"""Check the shipping PNG contract, not gameplay or subjective visual quality."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parent
m=json.loads((ROOT/"manifest.json").read_text())
allowed={tuple(bytes.fromhex(c[1:])) for c in m["palette"]}
checks=0
selected=set(sys.argv[1:])
checked={"sprites":0,"backgrounds":0}
source_names=set()

def require(ok, message):
    global checks
    checks+=1
    if not ok:
        raise AssertionError(message)

require(selected <= (set(m["sprites"]) | set(m["backgrounds"])), "Unknown selected asset ID")
for kind in ("sprites","backgrounds"):
    for name,rec in m[kind].items():
        if selected and name not in selected:
            continue
        checked[kind]+=1
        source_names.add(Path(rec["source"]).name)
        path=ROOT/rec["file"]
        require(path.is_file(),f"Missing {path}")
        require(hashlib.sha256(path.read_bytes()).hexdigest()==rec["sha256"],f"Stale checksum {name}")
        im=Image.open(path)
        require(im.mode=="RGBA" and list(im.size)==rec["size"],f"Format/dimensions {name}")
        pixels={color for count,color in im.getcolors(maxcolors=im.width*im.height)}
        asset_allowed={tuple(bytes.fromhex(c[1:])) for c in rec.get("palette",m["palette"])}
        require(all(p[3] in (0,255) for p in pixels),f"Soft alpha {name}")
        require(all(p[:3] in asset_allowed for p in pixels if p[3]),f"Palette drift {name}")
        require(all(p==(0,0,0,0) for p in pixels if not p[3]),f"Hidden RGB fringe {name}")
        require(bool(im.getbbox()),f"Empty asset {name}")
        if rec.get("asset_set")=="rain_scene" and kind=="backgrounds":
            x,y,w,h=rec["logical_rect"]
            require([w,h]==rec["size"] and x>=0 and y>=0 and x+w<=960 and y+h<=540,f"Invalid scene registration {name}")
            require(im.resize((w//2,h//2),Image.Resampling.NEAREST).resize((w,h),Image.Resampling.NEAREST).tobytes()==im.tobytes(),f"Broken 2px grid {name}")
            require(im.getchannel("A").getextrema()==((255,255) if name=="rain_canal_shallow" else (0,255)),f"Scene layer opacity {name}")
        if "export_palette_subset" in rec:
            subset={tuple(bytes.fromhex(c[1:])) for c in rec["export_palette_subset"]}
            require(subset <= asset_allowed,f"Palette subset outside declared palette {name}")
            require(all(p[:3] in subset for p in pixels if p[3]),f"Palette subset drift {name}")
        if kind=="sprites":
            require(im.getchannel("A").getextrema()[0]==0,f"Opaque background {name}")
            atlas=Image.open(ROOT/rec["atlas"])
            x,y,w,h=rec["region"]
            require(x>=0 and y>=0 and x+w<=atlas.width and y+h<=atlas.height,f"Invalid region {name}")
            require(atlas.crop((x,y,x+w,y+h)).tobytes()==im.tobytes(),f"Atlas mismatch {name}")
            require(0<=rec["pivot"][0]<=w and 0<=rec["pivot"][1]<=h,f"Invalid pivot {name}")
            require(list(im.getbbox())==rec["opaque_bounds"],f"Stale bounds {name}")
            if "footprint" in rec:
                polygon=rec["footprint"]["polygon"]
                require(len(polygon)>=3 and all(0<=x<w and 0<=y<h for x,y in polygon),f"Invalid footprint {name}")
                mask=Image.new("1",im.size)
                ImageDraw.Draw(mask).polygon([tuple(p) for p in polygon],fill=1)
                require(all(not mask.getpixel((x,y)) or im.getpixel((x,y))[3] for y in range(h) for x in range(w)),f"Footprint extends outside visible base {name}")
            for margin_kind in ("nine_slice_margins","content_margins"):
                if margin_kind in rec:
                    left,top,right,bottom=rec[margin_kind]
                    require(min(left,top,right,bottom)>=0 and left+right<w and top+bottom<h,f"Invalid {margin_kind} {name}")
for name,rec in m["sources"].items():
    if selected and name not in source_names:
        continue
    require(hashlib.sha256((ROOT/"source"/name).read_bytes()).hexdigest()==rec["sha256"],f"Changed source {name}")
for name,animation in m["animations"].items():
    if selected and not selected.intersection(animation["frames"]):
        continue
    require(all(frame in m["sprites"] for frame in animation["frames"]),f"Missing animation frame {name}")
    require(len(animation["frames"])==len(animation["duration_ms"]),f"Timing mismatch {name}")
    require(all(t>0 for t in animation["duration_ms"]),f"Invalid frame duration {name}")
if not selected:
    layout=json.loads((ROOT/"restaurant-layout.json").read_text())
    require(layout["background"] in m["backgrounds"],"Missing room shell")
    for entry in layout["draw_order"]:
        require(entry["sprite"] in m["sprites"],f"Missing layout sprite {entry['sprite']}")
        require(0<=entry["foot"][0]<384 and 0<=entry["foot"][1]<256,"Invalid room anchor")
print(json.dumps({"passed":True,"checks":checks,**checked,"selected_ids":sorted(selected),"palette_colors":len(allowed),"scope":"asset encoding, references and packaging only"},indent=2))
