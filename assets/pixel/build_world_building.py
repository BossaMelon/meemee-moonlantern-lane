#!/usr/bin/env python3
"""Export only the A01 construction kit from its preserved ImageGen sheet.

All visible artwork comes from source crops. Rectangular plane registration,
nearest resizing, repeat, palette reduction and assembly are mechanical.
This script does not re-export any legacy asset or modify gameplay geometry.
"""
import json
import shutil
from PIL import Image, ImageDraw
from build import ROOT, hard_alpha, palette_export, sha

SOURCE = "world-building-kit-v1.png"
TOP_SOURCE = "world-wood-top-v2.png"
SET = "world_building_kit_v1"
BASE = "639ea819565434114df26b950a672186e197c6b2"
EVIDENCE = ROOT / "evidence/world-building-kit"
PADDING = 2
KIT_COLORS = "25283f 332d36 70483c a5714f d2a06d f0c18b f8e4b6 374568 596a88 8796aa".split()
KIT_PALETTE = Image.new("P", (1, 1))
KIT_PALETTE.putpalette([v for color in KIT_COLORS for v in bytes.fromhex(color)] + list(bytes.fromhex(KIT_COLORS[0])) * (256-len(KIT_COLORS)))

# Source rectangles exclude the generated soft outline. Each plane is resized
# separately; no change in footprint can scale the fixed 24/64px elevations.
PLANES = {
    "wall_h_cap": ([78, 251, 588, 302], [96, 24]),
    "wall_h_face": ([78, 309, 588, 573], [96, 64]),
    "wall_v_cap": ([678, 54, 767, 302], [24, 96]),
    "wall_v_face": ([678, 309, 767, 573], [24, 64]),
    "wall_corner_cap": ([959, 251, 1055, 302], [24, 24]),
    "wall_corner_face": ([959, 309, 1055, 573], [24, 64]),
    "top": ([200, 150, 1744, 702], [32, 16]),
    "front": ([175, 773, 406, 927], [32, 24]),
    "end": ([608, 771, 656, 927], [8, 24]),
    "foot": ([887, 771, 926, 927], [8, 24]),
}
POSITIONS = [(0, 0), (104, 0), (136, 0), (168, 0), (168, 24), (208, 24), (224, 24)]


def plane(source, key):
    box, size = PLANES[key]
    result = palette_export(source.crop(box).resize(size, Image.Resampling.NEAREST), KIT_PALETTE)
    assert result.getchannel("A").getextrema() == (255, 255), key
    return result


def build():
    source = hard_alpha(Image.open(ROOT / "source" / SOURCE))
    top_source = hard_alpha(Image.open(ROOT / "source" / TOP_SOURCE))
    parts = {key: plane(top_source if key=="top" else source, key) for key in PLANES}
    top = parts["top"]
    exports = []
    for direction, width, depth in [("h", 96, 24), ("v", 24, 96), ("corner", 24, 24)]:
        cap, face = parts[f"wall_{direction}_cap"], parts[f"wall_{direction}_face"]
        body = Image.new("RGBA", (width, depth + 64))
        body.paste(cap, (0, 0)); body.paste(face, (0, depth))
        exports.append((f"world_wall_{direction}", body, {
            "role": "wall", "ground_size": [width, depth], "elevation_px": 64,
            "cap_region": [2, 2, width, depth], "face_region": [2, 2 + depth, width, 64],
            "ground_rect": [2, 66, width, depth],
            "planes": [f"wall_{direction}_cap", f"wall_{direction}_face"],
        }))
    for name, body, role, planes in [
        ("world_wood_top", top, "repeatable_top", ["top"]),
        ("world_wood_front", parts["front"], "fixed_height_front", ["front"]),
        ("world_wood_end", parts["end"], "end_post", ["end"]),
        ("world_wood_foot", parts["foot"], "shelf_foot", ["foot"]),
    ]:
        exports.append((name, body, {"role": role, "planes": planes, "elevation_px": 24}))
    m = json.loads((ROOT / "manifest.json").read_text())
    atlas = Image.new("RGBA", (256, 168))
    for (name, body, info), (ax, ay) in zip(exports, POSITIONS):
        im = Image.new("RGBA", (body.width + 4, body.height + 4))
        im.paste(body, (2, 2))
        path = ROOT / "sprites" / (name + ".png"); im.save(path)
        atlas.paste(im, (ax, ay))
        ground = info.get("ground_rect")
        rec = {"file": f"sprites/{name}.png", "size": list(im.size),
               "pivot": [im.width / 2, 2 + body.height - (ground[3] / 2 if ground else 0)],
               "atlas": "atlases/world_building_kit.png", "region": [ax, ay, *im.size],
               "opaque_bounds": list(im.getbbox()), "content_region": [2, 2, *body.size],
               "source": "source/" + (TOP_SOURCE if name=="world_wood_top" else SOURCE), "asset_set": SET, "sha256": sha(path),
               "export_palette_subset": ["#"+c for c in KIT_COLORS],
               "construction": info, "export": {"filter": "nearest", "alpha_threshold": 128,
                    "planes": {k: {"source_crop": PLANES[k][0], "size": PLANES[k][1]} for k in info["planes"]}}}
        if ground:
            x, y, w, h = ground
            rec["footprint"] = {"polygon": [[x,y], [x+w-1,y], [x+w-1,y+h-1], [x,y+h-1]],
                                "meaning": "exact visible ground coverage, not a new collider"}
        if name == "world_wood_top":
            rec["export"]["repeat"] = "whole quiet surface crop; matching opposing edge pixels, no mirroring"
        m["sprites"][name] = rec
    atlas.save(ROOT / "atlases/world_building_kit.png")
    for name in [SOURCE, TOP_SOURCE]:
        raw = Image.open(ROOT / "source" / name)
        m["sources"][name] = {"size": list(raw.size), "mode": raw.mode, "sha256": sha(ROOT/"source"/name), "runtime": False}
    (ROOT / "manifest.json").write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
    previews(m)
    print("Appended seven construction modules and one atlas; no legacy asset re-export.")


def content(m, name):
    rec = m["sprites"][name]
    x, y, w, h = rec["content_region"]
    return Image.open(ROOT/rec["file"]).crop((x,y,x+w,y+h))


def tile(im, size):
    out = Image.new("RGBA", size)
    for y in range(0, size[1], im.height):
        for x in range(0, size[0], im.width):
            out.paste(im, (x, y))
    return out


def furniture(m, width, depth, support="cabinet"):
    """QA reference composition. Origin is ground upper-left minus (0,24)."""
    im = Image.new("RGBA", (width, depth + 24))
    im.paste(tile(content(m,"world_wood_top"), (width, depth)), (0,0))
    im.paste(tile(content(m,"world_wood_front"), (width,24)), (0,depth))
    post = content(m, "world_wood_foot" if support == "shelf" else "world_wood_end")
    for x in [0, width-8]: im.paste(post, (x,depth))
    return im


def wall(m, width, depth):
    """Stretch neither height nor texels. Repeat/crop planes; 64px front last."""
    direction = "h" if depth == 24 else "v"
    rec = m["sprites"][f"world_wall_{direction}"]
    source = Image.open(ROOT / rec["file"])
    def cut(key):
        x,y,w,h=rec["construction"][key];return source.crop((x,y,x+w,y+h))
    im=Image.new("RGBA",(width,depth+64))
    im.paste(tile(cut("cap_region"),(width,depth)),(0,0))
    im.paste(tile(cut("face_region"),(width,64)),(0,depth))
    return im


def legacy(m, name): return Image.open(ROOT/m["sprites"][name]["file"])


def previews(m):
    EVIDENCE.mkdir(parents=True,exist_ok=True); (EVIDENCE.parent/".gdignore").write_text("")
    board=Image.new("RGB",(784,240),"#3c514c"); d=ImageDraw.Draw(board)
    names=[x for x,r in m["sprites"].items() if r.get("asset_set")==SET]
    for i,name in enumerate(names):
        x=8+i*112; im=legacy(m,name);board.paste(im,(x,8),im)
        d.text((x,178),name.replace("world_","").replace("_","\n"),fill="#f8e4b6")
        d.text((x,214),str(tuple(im.size)),fill="#a1baa0")
    board.save(EVIDENCE/"contact-native.png")
    board.resize((2352,720),Image.Resampling.NEAREST).save(EVIDENCE/"contact-3x.png")
    # Same-scale comparison: actual collider footprints, no furniture scaling.
    board=Image.new("RGB",(800,580),"#25283f");d=ImageDraw.Draw(board)
    entries=[("pantry",96,112,20,72), ("prep",128,80,180,104), ("stove",112,80,380,104),
             ("pass",144,64,560,120), ("table",96,64,20,326), ("recipe",40,32,240,358)]
    footprints=[]
    for name,w,h,x,y in entries:
        im=furniture(m,w,h,"shelf" if name=="pantry" else "cabinet")
        board.paste(im,(x,y-24),im)
        d.text((x,y-42),f"{name} {w}x{h}",fill="#f8e4b6")
        d.text((x,y+h+70),"front=24px",fill="#a1baa0")
        character=legacy(m,"meemee_walk_ne")
        board.paste(character,(x+w//2-24,y+h+13-61),character)
        footprints.append((x,y,w,h))
        if name=="recipe":
            book=legacy(m,"world_recipe_book").resize((32,24),Image.Resampling.NEAREST)
            board.paste(book,(x+4,y-24+4),book)
        elif name=="stove":
            pot=legacy(m,"cauldron_stir_left")
            board.paste(pot,(x+32,y+4-24),pot)
        elif name=="pantry":
            for j,item in enumerate(["flour","pumpkin","cream"]):
                prop=legacy(m,item);board.paste(prop,(x+j*30+3,y-20),prop)
        elif name in ("prep","pass","table"):
            prop=legacy(m,"comet_pie");board.paste(prop,(x+w//2-16,y+h//2-40),prop)
    d.text((380,330),"48x64 actor, native pixels\nFeet are 13px south; radius12 stays clear.\nSurface repeats 32x16; no whole-object scaling.\nRecipe book display is 32x24 on its 40x32 support.\nThis is asset layout QA, not a game screenshot.",fill="#f8e4b6",spacing=8)
    board.save(EVIDENCE/"scale-native.png")
    board.resize((1600,1160),Image.Resampling.NEAREST).save(EVIDENCE/"scale-2x.png")
    for x,y,w,h in footprints:
        d.rectangle((x,y,x+w-1,y+h-1),outline="#c46588")
        for xx in range(x+32,x+w,32):d.line((xx,y-24,xx,y+h),fill="#596a88")
        for yy in range(y-8,y+h-24,16):d.line((x,yy,x+w-1,yy),fill="#596a88")
    board.save(EVIDENCE/"scale-footprints.png")
    # Wall QA: exact coordinates from the frozen fixture. No invented doorway.
    layout=json.loads((ROOT.parent.parent/"tests/fixtures/world-slice-scenarios.json").read_text())["configuration"]["layout"]
    for region_name in ["shop","lane"]:
        region=layout["regions"][region_name]
        # Crops: shop real east gap (x=1256..1280,y=520..640), lane west portal.
        view=(1080,416,320,352) if region_name=="shop" else (0,128,320,352)
        vx,vy,vw,vh=view
        page=Image.new("RGB",(vw,vh),"#3c514c" if region_name=="shop" else "#374568")
        pd=ImageDraw.Draw(page)
        for c in sorted(region["colliders"],key=lambda c:c["y"]+c["height"]/2):
            if c["width"]!=24 and c["height"]!=24:continue
            w,h=c["width"],c["height"];x,y=c["x"]-w//2,c["y"]-h//2
            im=wall(m,w,h);page.paste(im,(x-vx,y-vy-64),im)
        if region_name=="lane":
            # Wall-mounted portal leaf. Its interaction anchor remains (80,256).
            door=legacy(m,"door");page.paste(door,(0,256-vy-62),door)
            anchor=(80-vx,256-vy)
            pd.text((62,18),"lane-home / wall mount\nanchor remains (80,256)",fill="#f8e4b6")
        else:
            anchor=(1224-vx,580-vy)
            pd.text((8,18),"shop-exit / real east gap\n120px opening: y=520..640\nno added jamb or collider",fill="#f8e4b6")
            pd.line((1256-vx,520-vy,1256-vx,640-vy-1),fill="#c46588")
        char=legacy(m,"meemee_walk_se");page.paste(char,(anchor[0]-24,anchor[1]-61),char)
        pd.ellipse((anchor[0]-2,anchor[1]-2,anchor[0]+2,anchor[1]+2),fill="#edc46e")
        pd.text((8,vh-30),"Fixture coordinates; asset QA only",fill="#f8e4b6")
        page.save(EVIDENCE/f"walls-{region_name}-native.png")
        page.resize((vw*3,vh*3),Image.Resampling.NEAREST).save(EVIDENCE/f"walls-{region_name}-3x.png")
    # Joined directions/corner, with no double-drawn corner footprint.
    page=Image.new("RGB",(320,240),"#3c514c");pd=ImageDraw.Draw(page)
    for name,pos in [("world_wall_h",(30,72)),("world_wall_h",(126,72)),
                     ("world_wall_corner",(222,72)),("world_wall_v",(222,96))]:
        rec=m["sprites"][name];im=legacy(m,name)
        page.paste(im,(pos[0]-2,pos[1]-66),im)
    char=legacy(m,"meemee_walk_se");page.paste(char,(130,100),char)
    pd.text((8,208),"H + H + corner + V / same 64px wall height",fill="#f8e4b6")
    page.save(EVIDENCE/"walls-join-native.png")
    page.resize((960,720),Image.Resampling.NEAREST).save(EVIDENCE/"walls-join-3x.png")
    # Full shop assembly at fixture positions, then its 640x360 spawn camera crop.
    region=layout["regions"]["shop"]
    room=Image.new("RGB",(region["width"],region["height"]+64),"#332d36")
    for c in sorted(region["colliders"],key=lambda c:c["y"]+c["height"]/2):
        w,h=c["width"],c["height"];x,y=c["x"]-w//2,c["y"]-h//2
        is_wall=w==24 or h==24
        im=wall(m,w,h) if is_wall else furniture(m,w,h)
        room.paste(im,(x,y+64-(64 if is_wall else 24)),im)
        if not is_wall:
            if c["id"]=="recipe-body":
                prop=legacy(m,"world_recipe_book").resize((32,24),Image.Resampling.NEAREST)
            elif c["id"]=="stove-body":prop=legacy(m,"cauldron_stir_left")
            elif c["id"]=="storage-body":prop=legacy(m,"flour")
            elif c["id"]=="ledger-body":prop=legacy(m,"world_ledger").resize((32,32),Image.Resampling.NEAREST)
            elif c["id"]=="menu-body":prop=legacy(m,"world_menu_board")
            else:prop=legacy(m,"comet_pie")
            room.paste(prop,(c["x"]-prop.width//2,y+64-20),prop)
    spawn=region["spawn"];char=legacy(m,"meemee_walk_se")
    room.paste(char,(spawn["x"]-24,spawn["y"]+64-61),char)
    room.save(EVIDENCE/"shop-layout-native.png")
    room.crop((0,264,640,624)).save(EVIDENCE/"shop-spawn-640x360.png")
    # Keep the reviewable artifact with the PR; raw logs remain ignored evidence.
    retained=ROOT/"preview/world-building-kit"
    retained.mkdir(parents=True,exist_ok=True)
    (retained/".gdignore").write_text("")
    for name in ["contact-native.png","contact-3x.png","scale-native.png","scale-2x.png",
                 "scale-footprints.png","walls-join-3x.png","walls-shop-3x.png","walls-lane-3x.png",
                 "shop-layout-native.png","shop-spawn-640x360.png"]:
        shutil.copyfile(EVIDENCE/name,retained/name)


if __name__=="__main__": build()
