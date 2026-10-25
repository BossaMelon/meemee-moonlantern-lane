#!/usr/bin/env python3
"""Deterministic export/packing of ImageGen originals; no procedural artwork.

Run with Python + Pillow. Sources remain untouched. Crops, nearest-neighbour
export, one shared palette and binary alpha make the generated art game-ready.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
COLORS = """25283f 202438 374568 596a88 8796aa c46588
332d36 8e9849 70483c a5714f d2a06d f0c18b
bf8a43 edc46e f8e4b6 fff3d0 3c514c 668578 a1baa0 c3d1ad
492f34 773d35 a94f35 d77843 a86855 d98f68 f2b388 f6d2a3
4e697d 6e9da9 a9d6ce ea9ab1""".split()
RGB = [tuple(bytes.fromhex(c)) for c in COLORS]
PALETTE = Image.new("P", (1, 1))
PALETTE.putpalette([v for c in RGB for v in c] + list(RGB[0]) * (256-len(RGB)))

# (id, original crop x0 y0 x1 y1, final canvas width height, fitting method)
SHEETS = {
    "environment": ("furniture", (96, 80), [
        ("floor_wood", (0,90,311,310), (64,32), "tile"),
        ("floor_stone", (314,90,623,310), (64,32), "tile"),
        ("wall_right", (640,0,935,315), (64,64), "fit"),
        ("wall_left", (950,0,1254,315), (64,64), "fit"),
        ("moon_window", (0,315,302,668), (48,64), "fit"),
        ("stool", (40,680,280,914), (32,32), "fit"),
        ("rug", (303,675,640,926), (64,32), "fit"),
        ("door", (0,915,305,1254), (48,64), "fit"),
    ]),
    "kitchen": ("kitchen", (96, 80), [
        ("stove", (20,40,420,583), (64,80), "fit"),
        ("prep_table", (425,180,875,575), (80,64), "fit"),
        ("sink", (877,130,1146,560), (48,64), "fit"),
        ("dining_table", (1150,115,1536,560), (64,64), "fit"),
        ("serving_counter", (10,584,545,1000), (96,64), "fit"),
        ("warming_hood", (548,590,947,995), (64,64), "fit"),
        ("herb_shelf", (948,580,1285,1010), (64,64), "fit"),
        ("floating_plates", (1288,620,1536,980), (32,32), "fit"),
    ]),
    "characters": ("characters", (48,64), []),
    "actions": ("actions", (48,64), []),
    "guests": ("hagrid", (64,80), [
        ("hagrid_idle", (0,0,768,1024), (64,80), "cell"),
        ("hagrid_thanks", (768,0,1536,1024), (64,80), "cell"),
    ]),
    "cooking": ("cauldron", (48,48), [
        ("cauldron_stir_left", (50,150,755,850), (48,48), "fit"),
        ("cauldron_stir_right", (780,150,1485,850), (48,48), "fit"),
    ]),
    "food": ("food", (32,32), [
        ("flour", (0,0,384,350), (32,32), "fit"),
        ("pumpkin", (384,0,768,350), (32,32), "fit"),
        ("cream", (768,0,1152,350), (32,32), "fit"),
        ("ember_herb", (1152,0,1536,350), (32,32), "fit"),
        ("sparkcap", (0,350,384,655), (32,32), "fit"),
        ("moonheart", (384,350,768,655), (32,32), "fit"),
        ("floating_pie", (768,350,1152,655), (32,32), "fit"),
        ("ember_soup", (1152,350,1536,655), (32,32), "fit"),
        ("moon_stew", (0,655,421,985), (32,32), "fit"),
        ("star_soup", (425,665,770,985), (32,32), "fit"),
        ("comet_pie", (775,655,1170,985), (32,32), "fit"),
        ("takeaway_basket", (1172,665,1536,985), (32,32), "fit"),
    ]),
    "combat": ("combat", (64,64), [
        ("sparkcap_idle", (20,145,370,510), (32,32), "scale:0.09"),
        ("sparkcap_windup", (390,180,725,510), (32,32), "scale:0.09"),
        ("moonheart_guard", (745,120,1095,515), (64,64), "scale:0.145"),
        ("moonheart_exposed", (1105,120,1536,515), (64,64), "scale:0.145"),
        ("bolt_wand", (40,540,365,945), (32,32), "fit"),
        ("fan_wand", (390,540,755,945), (32,32), "fit"),
        ("gust_small", (760,630,1100,960), (64,48), "fit"),
        ("gust_large", (1105,610,1536,975), (64,48), "fit"),
    ]),
    "ui": ("ui", (128,80), [
        ("dialogue_panel", (10,210,720,620), (128,72), "stretch"),
        ("button_normal", (725,310,1225,540), (96,40), "stretch"),
        ("button_focus", (100,770,700,1040), (96,40), "stretch"),
        ("inventory_slot", (825,690,1180,1055), (48,48), "stretch"),
    ]),
}
for group, names in {
    "characters": ["meemee_idle","meemee_blink","meemee_serve","meemee_stir",
                   "student_idle","student_thanks","neighbor_idle","neighbor_thanks"],
    "actions": ["meemee_walk_se","meemee_walk_sw","meemee_walk_ne","meemee_walk_nw",
                "meemee_cast_se","meemee_cast_nw","meemee_dodge_sw","meemee_dodge_se"],
}.items():
    for i, name in enumerate(names):
        x, y = (i % 4) * 384, (i // 4) * 512
        SHEETS[group][2].append((name, (x,y,x+384,y+512), (48,64), "cell"))


def hard_alpha(im):
    im = im.convert("RGBA")
    im.putalpha(im.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
    return im


def palette_export(im):
    alpha = im.getchannel("A")
    out = im.convert("RGB").quantize(palette=PALETTE, dither=Image.Dither.NONE).convert("RGBA")
    out.putalpha(alpha)
    # Transparent RGB must be zero as well: avoids colored fringes in consumers.
    empty = Image.new("RGBA", out.size)
    empty.paste(out, (0,0), alpha)
    return empty


def export_region(source, box, size, method):
    assert box[2] <= source.width and box[3] <= source.height, box
    crop = hard_alpha(source.crop(box))
    bounds = crop.getbbox()
    assert bounds, box
    if method != "cell":
        crop = crop.crop(bounds)
    if method in ("cell", "tile", "stretch"):
        out = crop.resize(size, Image.Resampling.NEAREST)
    else:
        scale = float(method.split(":")[1]) if method.startswith("scale:") else min((size[0]-4)/crop.width, (size[1]-4)/crop.height)
        small = crop.resize((max(1, round(crop.width*scale)), max(1, round(crop.height*scale))), Image.Resampling.NEAREST)
        assert small.width <= size[0] and small.height <= size[1], (box, size, small.size)
        out = Image.new("RGBA", size)
        out.paste(small, ((size[0]-small.width)//2,size[1]-2-small.height))
    return palette_export(out), [box[0]+bounds[0],box[1]+bounds[1],box[0]+bounds[2],box[1]+bounds[3]]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    for folder in ("sprites","atlases","backgrounds","preview"):
        (ROOT/folder).mkdir(exist_ok=True)
    manifest = {
        "schema_version": 1,
        "title": "咩咩与月灯巷 · 三日魔法饭店像素资产",
        "source": "OpenAI built-in image_gen, original generated raster artwork; see SOURCES.md",
        "native_pixel_grid": 1,
        "palette": ["#"+c for c in COLORS],
        "alpha": "binary 0/255; transparent RGB is 0/0/0",
        "texture_filter": "nearest", "mipmaps": False,
        "camera": "three-quarter elevated orthographic; visible fronts; roofless interior",
        "light": "upper left; indigo shadows",
        "sprites": {}, "backgrounds": {}, "sources": {},
        "content_contract_revision":"4d06f599b40663b3910a215f89b1bd1a26343b48",
        "aliases":{"meemee":"meemee_idle","hagrid":"hagrid_idle","stirring_cauldron":"cauldron_stir_left","gust":"gust_small"},
        "animations": {
            "meemee_idle": {"frames":["meemee_idle","meemee_blink","meemee_idle"],"duration_ms":[2400,140,1800],"loop":True},
            "serve": {"frames":["meemee_idle","meemee_serve","meemee_idle"],"duration_ms":[80,400,100],"loop":False,"trigger":"actual successful dish sale"},
            "self_stir": {"frames":["cauldron_stir_left","cauldron_stir_right"],"duration_ms":[260,260],"loop":True,"trigger":"actual cooking effect; UI must stop when effect ends"},
            "hagrid_thanks": {"frames":["hagrid_idle","hagrid_thanks","hagrid_idle"],"duration_ms":[100,750,100],"loop":False,"trigger":"actual quest completion, never preview/decline"},
            "gust": {"frames":["gust_small","gust_large"],"duration_ms":[100,140],"loop":False,"trigger":"actual skill event; visual only, never damage or radius authority"},
        },
        "integration_limits": [
            "Pose frames are discrete poses, not a complete interpolated walking cycle.",
            "Art does not implement gameplay, collision, input, cooking effects or UI focus.",
            "Environment floor pieces are modular decorative diamonds; not certified seamless Wang tiles.",
            "Background furniture is baked in; use either background composition or modular furniture, not both over the same furniture.",
        ],
    }
    for group, (source_name, cell, definitions) in SHEETS.items():
        original = Image.open(ROOT/"source"/(source_name+".png")).convert("RGBA")
        cols = 2 if group == "ui" else 4
        sheet = Image.new("RGBA", (cell[0]*cols,cell[1]*((len(definitions)+cols-1)//cols)))
        for i,(name,box,size,method) in enumerate(definitions):
            sprite,bounds = export_region(original,box,size,method)
            x,y = (i%cols)*cell[0],(i//cols)*cell[1]
            sheet.paste(sprite,(x,y))
            path=ROOT/"sprites"/(name+".png")
            sprite.save(path)
            b=sprite.getbbox()
            record={
                "file":str(path.relative_to(ROOT)), "size":list(size),
                "atlas":"atlases/"+group+".png", "region":[x,y,*size],
                "pivot":[size[0]//2,b[3]], "opaque_bounds":list(b),
                "source":"source/"+source_name+".png", "source_crop":list(box),
                "source_opaque_bounds":bounds, "export":method,
                "purpose":group, "sha256":sha(path),
            }
            if method=="tile":
                record["pivot"]=[32,16]
                record["ground_step"]=[[32,16],[-32,16]]
            if group=="ui":
                record["pivot"]=[0,0]
                record["nine_slice_margins"]=[14,14,14,14] if name=="dialogue_panel" else [12,12,12,12]
                record["content_margins"]=[18,16,18,16] if name=="dialogue_panel" else [14,12,14,12]
            manifest["sprites"][name]=record
        sheet.save(ROOT/"atlases"/(group+".png"))
    for name in ["restaurant-interior","restaurant-lane","restaurant-shell","mushroom-garden"]:
        source=Image.open(ROOT/"source"/(name+".png")).convert("RGBA")
        dimensions=(480,270) if name=="mushroom-garden" else (384,256)
        out=palette_export(source.resize(dimensions,Image.Resampling.NEAREST))
        path=ROOT/"backgrounds"/(name+".png"); out.save(path)
        manifest["backgrounds"][name]={"file":str(path.relative_to(ROOT)),"size":list(dimensions),"source":"source/"+name+".png","sha256":sha(path),"purpose":"complete static environment; no collision implied"}
    for path in sorted((ROOT/"source").glob("*.png")):
        im=Image.open(path)
        manifest["sources"][path.name]={"size":list(im.size),"mode":im.mode,"sha256":sha(path),"runtime":False}
    layout={
        "schema_version":1,"canvas":[384,256],"background":"restaurant-shell",
        "sorting":"explicit draw_order; actor foot positions in native pixels",
        "walk_area_hint":[[78,164],[171,125],[325,173],[251,231]],
        "anchors":{"chef":[171,169],"serve":[236,180],"customer":[261,220],"kitchen":[104,152],"table":[298,157]},
        "draw_order":[
            {"sprite":"herb_shelf","foot":[245,110]},
            {"sprite":"stove","foot":[58,160]},
            {"sprite":"cauldron_stir_left","foot":[57,123],"role":"cooking_overlay"},
            {"sprite":"prep_table","foot":[118,155]},
            {"sprite":"sink","foot":[177,133]},
            {"sprite":"dining_table","foot":[298,160]},
            {"sprite":"stool","foot":[273,171]},
            {"sprite":"stool","foot":[325,180]},
            {"sprite":"meemee_idle","foot":[171,169],"role":"actor"},
            {"sprite":"serving_counter","foot":[271,216]},
            {"sprite":"warming_hood","foot":[274,187]},
            {"sprite":"student_idle","foot":[220,227],"role":"actor"},
        ],
        "note":"Visual placement only. UI/core owner defines collision, interaction and runtime depth changes; do not treat this as game state. Counter is an independent transparent sprite.",
    }
    (ROOT/"restaurant-layout.json").write_text(json.dumps(layout,ensure_ascii=False,indent=2)+"\n")
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    preview(manifest)
    print(f"Exported {len(manifest['sprites'])} sprites and {len(manifest['backgrounds'])} backgrounds; 32-color palette.")


def preview(manifest):
    # QA compositions only: never treated as additional shipping art.
    room=Image.open(ROOT/"backgrounds/restaurant-interior.png").convert("RGBA")
    for name,foot in [("meemee_idle",(171,182)),("student_idle",(244,235))]:
        sprite=Image.open(ROOT/manifest["sprites"][name]["file"])
        pivot=manifest["sprites"][name]["pivot"]
        room.alpha_composite(sprite,(foot[0]-pivot[0],foot[1]-pivot[1]))
    room.resize((1152,768),Image.Resampling.NEAREST).save(ROOT/"preview/restaurant-composite.png")
    layout=json.loads((ROOT/"restaurant-layout.json").read_text())
    modular=Image.open(ROOT/"backgrounds/restaurant-shell.png").convert("RGBA")
    for entry in layout["draw_order"]:
        record=manifest["sprites"][entry["sprite"]]
        im=Image.open(ROOT/record["file"])
        p=record["pivot"]; foot=entry["foot"]
        modular.alpha_composite(im,(foot[0]-p[0],foot[1]-p[1]))
    modular.resize((1152,768),Image.Resampling.NEAREST).save(ROOT/"preview/restaurant-layered.png")
    garden=Image.open(ROOT/"backgrounds/mushroom-garden.png").convert("RGBA")
    for name,foot in [("meemee_cast_se",(160,165)),("sparkcap_windup",(260,160)),("moonheart_guard",(355,170))]:
        record=manifest["sprites"][name]; im=Image.open(ROOT/record["file"]); p=record["pivot"]
        garden.alpha_composite(im,(foot[0]-p[0],foot[1]-p[1]))
    garden.resize((1440,810),Image.Resampling.NEAREST).save(ROOT/"preview/garden-composite.png")
    sprites=list(manifest["sprites"].items())
    cw,ch,cols=288,280,4
    board=Image.new("RGB",(cw*cols,ch*((len(sprites)+cols-1)//cols)),"#c5d0ca")
    d=ImageDraw.Draw(board)
    for i,(name,record) in enumerate(sprites):
        x,y=(i%cols)*cw,(i//cols)*ch
        bg="#374568" if i%2 else "#c5d0ca"
        d.rectangle((x,y,x+cw-1,y+ch-1),fill=bg)
        im=Image.open(ROOT/record["file"])
        scale=min(3,(cw-20)//im.width,(ch-35)//im.height)
        im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
        board.paste(im,(x+(cw-im.width)//2,y+10),im)
        d.text((x+8,y+ch-22),name,fill="#edc46e" if i%2 else "#25283f")
    board.save(ROOT/"preview/contact-sheet.png")


if __name__=="__main__":
    build()
