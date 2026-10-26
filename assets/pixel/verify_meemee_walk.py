#!/usr/bin/env python3
"""Walk packaging/registration checks, not game movement acceptance."""
import json
from PIL import Image, ImageOps
from build import ROOT, sha
from build_meemee_walk import DIRECTIONS, PHASES, EVIDENCE, PIVOT, SIZE

m=json.loads((ROOT/"manifest.json").read_text())
results={}
for direction in DIRECTIONS:
    clip=m["animations"][f"meemee_walk_{direction}_cycle"]
    expected=[f"meemee_walk_{direction}_{i:02d}" for i in range(1,5)]
    assert clip["frames"]==expected and clip["loop"] and clip["facing"]==direction
    assert clip["duration_ms"]==[125]*4 and clip["stop_frame"]==f"meemee_walk_{direction}"
    images=[]; heads=[]; boots=[]; source_scales=[]
    for name,phase in zip(expected,PHASES):
        r=m["sprites"][name]; im=Image.open(ROOT/r["file"])
        assert r["size"]==list(SIZE) and r["pivot"]==PIVOT
        assert r["facing"]==direction and r["phase"]==phase
        b=im.getbbox()
        assert b[0]>0 and b[2]<48 and b[1]>0 and b[3]==61, f"Clipping or ground jitter: {name}"
        source=Image.open(ROOT/r["source"])
        x0,y0,x1,y1=r["source_crop"]
        assert 0<=x0<x1<=source.width and 0<=y0<y1<=source.height
        crop=source.crop((x0,y0,x1,y1)).getchannel("A").point(lambda a:255 if a>=128 else 0)
        cb=crop.getbbox()
        assert cb[0]>0 and cb[1]>0 and cb[2]<crop.width and cb[3]<crop.height,"Source crop cuts silhouette"
        source_scales.append(r["export"]["uniform_clip_scale"])
        head=im.getchannel("A").crop((0,0,48,28)).getbbox()
        heads.append(((head[0]+head[2])/2,head[1],head[2]-head[0]))
        low=[x for y in range(57,61) for x in range(48) if im.getpixel((x,y))[3]]
        assert low
        boots.append(sum(low)/len(low))
        if "derived_from" in r:
            primary=Image.open(ROOT/m["sprites"][r["derived_from"]]["file"])
            assert im.tobytes()==ImageOps.mirror(primary).tobytes(),name
        images.append(im)
    assert len(set(source_scales))==1,"Per-frame resizing hides size drift"
    assert len({im.tobytes() for im in images})==4,"Repeated poses masquerading as four frames"
    assert max(h[0] for h in heads)-min(h[0] for h in heads)<=1
    assert max(h[1] for h in heads)-min(h[1] for h in heads)<=2
    assert max(h[2] for h in heads)-min(h[2] for h in heads)<=2
    assert abs(boots[0]-boots[2])>=7,"Contact poses do not alternate feet"
    differences=[]
    for a,b in zip(images,images[1:]+images[:1]):
        roi_a=a.crop((0,45,48,61)); roi_b=b.crop((0,45,48,61))
        count=sum(roi_a.getpixel((x,y))!=roi_b.getpixel((x,y)) for y in range(16) for x in range(48))
        assert count>=20,"Adjacent lower-body phases are effectively static"
        differences.append(count)
    results[direction]={"frames":expected,"head_x_range_px":max(h[0] for h in heads)-min(h[0] for h in heads),
                        "head_y_range_px":max(h[1] for h in heads)-min(h[1] for h in heads),
                        "ground_edge_y":[im.getbbox()[3] for im in images],
                        "low_boot_x_centroid":[round(x,2) for x in boots],
                        "adjacent_lower_body_changed_pixels_including_loop":differences}
for name in ("meemee-walk-se-v1.png","meemee-walk-se-v2.png","meemee-walk-ne.png"):
    assert sha(ROOT/"source"/name)==m["sources"][name]["sha256"]
report={"passed":True,"frame_count":16,"clip_count":4,"pivot":PIVOT,"directions":results,
        "scope":"source crop, stable registration, alternate lower-body shapes and mirroring; not runtime feel or foot planting in world space"}
EVIDENCE.mkdir(parents=True,exist_ok=True)
(EVIDENCE/"verification.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
