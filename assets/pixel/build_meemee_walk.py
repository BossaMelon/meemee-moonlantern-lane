#!/usr/bin/env python3
"""Append four real walk clips from generated poses; never rewrite legacy PNGs.

SE/NE are generated alternate-step sequences. SW/NW mirror whole sequences,
never alternate directions within a clip. Evidence stays in ignored evidence/.
"""
import json
from PIL import Image, ImageDraw, ImageOps
from build import ROOT, hard_alpha, palette_export, sha

SIZE=(48,64)
PIVOT=[24,61]
DIRECTIONS=("se","sw","ne","nw")
PHASES=("contact_a","passing_a","contact_b","passing_b")
EVIDENCE=ROOT/"evidence/meemee-walk"
SOURCES={"se":"meemee-walk-se-v2.png","ne":"meemee-walk-ne.png"}
BOXES=[(0,0,543,750),(543,0,1086,750),(0,750,543,1448),(543,750,1086,1448)]


def build_walk():
    m=json.loads((ROOT/"manifest.json").read_text())
    atlas=Image.new("RGBA",(192,256))
    for primary,source_name in SOURCES.items():
        source=hard_alpha(Image.open(ROOT/"source"/source_name))
        cells=[source.crop(box) for box in BOXES]
        bounds=[cell.getbbox() for cell in cells]
        # One scale for all four frames of a clip: no frame-by-frame size normalization.
        scale=53/max(b[3]-b[1] for b in bounds)
        mirror={"se":"sw","ne":"nw"}[primary]
        for i,(cell,b,box) in enumerate(zip(cells,bounds,BOXES)):
            head=cell.crop((0,b[1],cell.width,b[1]+round((b[3]-b[1])*.38))).getbbox()
            head_center=(head[0]+head[2])/2
            crop=cell.crop(b)
            small=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST)
            offset=[round(PIVOT[0]-(head_center-b[0])*scale),PIVOT[1]-small.height]
            assert offset[0]>=0 and offset[0]+small.width<=SIZE[0] and offset[1]>=0
            frame=Image.new("RGBA",SIZE); frame.paste(small,tuple(offset))
            frame=palette_export(frame)
            for direction,image in [(primary,frame),(mirror,ImageOps.mirror(frame))]:
                name=f"meemee_walk_{direction}_{i+1:02d}"
                path=ROOT/"sprites"/(name+".png"); image.save(path)
                x,y=i*48,DIRECTIONS.index(direction)*64
                atlas.paste(image,(x,y))
                record={"file":str(path.relative_to(ROOT)),"size":list(SIZE),"pivot":PIVOT[:],
                        "atlas":"atlases/meemee_walk_cycle.png","region":[x,y,48,64],
                        "opaque_bounds":list(image.getbbox()),"source":"source/"+source_name,
                        "source_crop":list(box),"source_opaque_bounds":[box[0]+b[0],box[1]+b[1],box[0]+b[2],box[1]+b[3]],
                        "export":{"uniform_clip_scale":scale,"placement_offset_before_mirror":offset,
                                  "head_anchor_source_x":box[0]+head_center,"ground_anchor_source_y":box[1]+b[3],
                                  "horizontal_mirror":direction==mirror,"filter":"nearest","alpha_threshold":128},
                        "asset_set":"meemee_walk_cycle_v1","facing":direction,"phase":PHASES[i],
                        "sha256":sha(path),"purpose":"movement-driven walk frame; no baked translation"}
                if direction==mirror:
                    record["derived_from"]=f"meemee_walk_{primary}_{i+1:02d}"
                m["sprites"][name]=record
    atlas.save(ROOT/"atlases/meemee_walk_cycle.png")
    for direction in DIRECTIONS:
        m["animations"][f"meemee_walk_{direction}_cycle"]={
            "frames":[f"meemee_walk_{direction}_{i:02d}" for i in range(1,5)],
            "duration_ms":[125,125,125,125],"loop":True,"facing":direction,
            "pivot":PIVOT[:],"trigger":"actual displacement; stop when stationary or paused",
            "stop_frame":f"meemee_walk_{direction}","pause_policy":"freeze current phase",
            "usage":"4-frame alternate-step loop; UI controls playback rate and world movement independently"}
    for source_name in ["meemee-walk-se-v1.png",*SOURCES.values()]:
        path=ROOT/"source"/source_name; im=Image.open(path)
        m["sources"][source_name]={"size":list(im.size),"mode":im.mode,"sha256":sha(path),"runtime":False}
    old_note="Pose frames are discrete poses, not a complete interpolated walking cycle."
    new_note="Legacy action IDs remain single poses; meemee_walk_*_cycle adds four-frame diagonal walk loops, not eight-direction interpolated animation."
    m["integration_limits"]=[new_note if note==old_note else note for note in m["integration_limits"]]
    (ROOT/"manifest.json").write_text(json.dumps(m,ensure_ascii=False,indent=2)+"\n")
    previews(m)
    print("Appended 16 walk frames, 4 clips and one atlas; legacy PNGs unchanged.")


def previews(m):
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    (EVIDENCE.parent/".gdignore").write_text("")
    board=Image.new("RGB",(480,360),"#3c514c"); d=ImageDraw.Draw(board)
    for row,direction in enumerate(DIRECTIONS):
        names=[f"meemee_walk_{direction}"]+[f"meemee_walk_{direction}_{i:02d}" for i in range(1,5)]
        for col,name in enumerate(names):
            x,y=col*96,row*90
            d.rectangle((x,y,x+95,y+89),fill="#374568" if (row+col)%2 else "#c3d1ad")
            rec=m["sprites"][name]; im=Image.open(ROOT/rec["file"])
            board.paste(im,(x+24,y+4),im)
            d.line((x+46,y+68,x+50,y+68),fill="#c46588")
            d.text((x+4,y+72),direction+(" legacy" if col==0 else f" {col} "+PHASES[col-1][:4]),fill="#202438" if not (row+col)%2 else "#f8e4b6")
    board.save(EVIDENCE/"contact-native.png")
    board.resize((1440,1080),Image.Resampling.NEAREST).save(EVIDENCE/"contact-3x.png")
    frames=[]
    for i in range(1,5):
        board=Image.new("RGB",(192,160),"#3c514c");d=ImageDraw.Draw(board)
        for j,direction in enumerate(DIRECTIONS):
            x,y=(j%2)*96,(j//2)*80
            r=m["sprites"][f"meemee_walk_{direction}_{i:02d}"]
            im=Image.open(ROOT/r["file"]);board.paste(im,(x+24,y+2),im)
            d.line((x+45,y+64,x+51,y+64),fill="#668578")
            d.text((x+4,y+67),direction+f" frame {i}",fill="#f8e4b6")
        frames.append(board.resize((576,480),Image.Resampling.NEAREST))
    frames[0].save(EVIDENCE/"four-directions.gif",save_all=True,append_images=frames[1:],duration=125,loop=0)
    for i,frame in enumerate(frames):frame.save(EVIDENCE/f"phase-{i+1}.png")


if __name__=="__main__":
    build_walk()
