#!/usr/bin/env python3
"""Deterministic export/packing of ImageGen originals; no procedural artwork.

Run with Python + Pillow. Sources remain untouched. Crops, nearest-neighbour
export, one shared palette and binary alpha make the generated art game-ready.
"""
from pathlib import Path
import hashlib
import json
import sys
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
GARDEN_COLORS = """304646 364d4b 3a514f 3d5654 465b53 4c6156 566650 636b50
080f28 142344 233657 374568 4e5d78 6b7885 2d4744 4e6759
708462 9b9855 302a37 4d3940 70483c 93684c b38757 d2a06d
edc46e f8e4b6 7e794b a79458 c4a456 3d405c 596a88 a1baa0""".split()
GARDEN_PALETTE = Image.new("P", (1,1))
garden_values = [v for c in GARDEN_COLORS for v in bytes.fromhex(c)]
GARDEN_PALETTE.putpalette(garden_values + garden_values[:3] * (256-len(GARDEN_COLORS)))

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
    "world_ui_v2": ("world-ui-v2", (64,64), [
        ("world_recipe_book", (50,130,775,615), (64,48), "fit"),
        ("world_order_note", (785,80,1230,620), (32,48), "fit"),
        ("world_ledger", (45,640,670,1200), (48,48), "fit"),
        ("world_menu_board", (700,630,1240,1210), (48,64), "fit"),
    ]),
    "plain_ui_v2": ("plain-ui-v2", (128,72), [
        ("ui_paper_panel", (25,155,570,455), (128,64), "stretch"),
        ("ui_button_plain", (575,265,1035,450), (96,32), "stretch"),
        ("ui_button_plain_focus", (1045,265,1515,450), (96,32), "stretch"),
        ("ui_coin", (130,550,425,855), (20,20), "fit"),
        ("ui_day", (625,550,915,855), (20,20), "fit"),
        ("ui_pause", (1165,580,1395,850), (20,20), "fit"),
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


def palette_export(im, palette=PALETTE):
    alpha = im.getchannel("A")
    out = im.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
    out.putalpha(alpha)
    # Transparent RGB must be zero as well: avoids colored fringes in consumers.
    empty = Image.new("RGBA", out.size)
    empty.paste(out, (0,0), alpha)
    return empty


def export_region(source, box, size, method, palette=PALETTE):
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
    return palette_export(out,palette), [box[0]+bounds[0],box[1]+bounds[1],box[0]+bounds[2],box[1]+bounds[3]]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_background(name):
    is_garden = name == "mushroom-garden"
    source_name = "mushroom-garden-v3" if is_garden else name
    source = Image.open(ROOT/"source"/(source_name+".png")).convert("RGBA")
    dimensions = (480,270) if is_garden else (384,256)
    out = palette_export(source.resize(dimensions,Image.Resampling.NEAREST), GARDEN_PALETTE if is_garden else PALETTE)
    path=ROOT/"backgrounds"/(name+".png"); out.save(path)
    record={"file":str(path.relative_to(ROOT)),"size":list(dimensions),"source":"source/"+source_name+".png","sha256":sha(path),"purpose":"complete static environment; no collision implied"}
    if is_garden:
        record.update({"art_revision":3,"logical_size":[960,540],"palette":["#"+c for c in GARDEN_COLORS],"playfield":"continuous quiet moss-earth plane; edge-cast shadows and source-linked lamp pools"})
    return record


def garden_preview(manifest):
    garden=Image.open(ROOT/"backgrounds/mushroom-garden.png").convert("RGBA")
    for name,foot in [("meemee_cast_se",(160,165)),("sparkcap_windup",(260,160)),("moonheart_guard",(355,170))]:
        record=manifest["sprites"][name]; im=Image.open(ROOT/record["file"]); p=record["pivot"]
        garden.alpha_composite(im,(foot[0]-p[0],foot[1]-p[1]))
    scaled=garden.resize((1440,810),Image.Resampling.NEAREST)
    scaled.save(ROOT/"preview/garden-composite.png")
    scaled.save(ROOT/"preview/garden-v3-concept.png")


def update_garden_only():
    manifest=json.loads((ROOT/"manifest.json").read_text())
    manifest["backgrounds"]["mushroom-garden"]=export_background("mushroom-garden")
    path=ROOT/"source/mushroom-garden-v3.png"
    im=Image.open(path)
    manifest["sources"][path.name]={"size":list(im.size),"mode":im.mode,"sha256":sha(path),"runtime":False}
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    garden_preview(manifest)
    print("Updated mushroom-garden only; existing sprite/UI exports untouched.")


def update_rain_assets():
    """Append six mechanism assets; never re-export existing sprites or atlases."""
    manifest=json.loads((ROOT/"manifest.json").read_text())
    definitions=[
        ("garden_stump", (64,64), "fit", [32,56]),
        ("sporecaster_idle", (40,40), "scale:0.045", [20,36]),
        ("sporecaster_windup", (40,40), "scale:0.045", [20,36]),
        ("sporecaster_release", (40,40), "scale:0.045", [20,36]),
        ("spore_cloud", (64,40), "fit", [32,33]),
        ("water_ripple", (32,16), "fit", [16,8]),
    ]
    atlas=Image.new("RGBA",(192,128))
    # Keep the hazard in the existing palette's plum/indigo family, not wood brown.
    spore_colors=["25283f","202438","374568","596a88","c46588","ea9ab1","492f34","332d36"]
    spore_palette=Image.new("P",(1,1))
    values=[v for c in spore_colors for v in bytes.fromhex(c)]
    spore_palette.putpalette(values+values[:3]*(256-len(spore_colors)))
    for i,(name,size,method,pivot) in enumerate(definitions):
        source_name="water-ripple-v2" if name=="water_ripple" else name.replace("_","-")
        source_path=ROOT/"source"/(source_name+".png")
        source=Image.open(source_path).convert("RGBA")
        box=(0,0,*source.size)
        sprite,bounds=export_region(source,box,size,method,spore_palette if name=="spore_cloud" else PALETTE)
        if name=="water_ripple":
            # Recenter the generated ring, preserving its pixels and open center.
            ring=sprite.crop(sprite.getbbox())
            sprite=Image.new("RGBA",size)
            sprite.paste(ring,((size[0]-ring.width)//2,(size[1]-ring.height)//2))
        path=ROOT/"sprites"/(name+".png")
        sprite.save(path)
        x,y=(i%3)*64,(i//3)*64
        atlas.paste(sprite,(x,y))
        record={"file":str(path.relative_to(ROOT)),"size":list(size),
                "source":str(source_path.relative_to(ROOT)),"source_crop":list(box),
                "source_opaque_bounds":bounds,"export_method":method,
                "atlas":"atlases/rain_garden.png","region":[x,y,*size],
                "pivot":pivot,"opaque_bounds":list(sprite.getbbox()),
                "sha256":sha(path),"asset_set":"rain_garden"}
        if name=="garden_stump":
            record.update({"usage":"solid stump; sort at contact-base pivot",
                           "footprint":{"space":"native sprite pixels; origin top-left",
                                        "kind":"visible_contact_base_hint",
                                        "polygon":[[9,51],[20,48],[43,48],[55,52],[46,57],[18,57]],
                                        "authority":"visual base only; gameplay owner defines collision from visible base, never full canopy rectangle"}})
        elif name.startswith("sporecaster_"):
            record.update({"enemy_kind":"sporecaster","pose":name.removeprefix("sporecaster_"),
                           "usage":"state-selected pose; shared foot pivot; gameplay owns telegraph/release timing"})
        elif name=="spore_cloud":
            record.update({"usage":"grounded hazardous spore cluster; never a collectible",
                           "export_palette_subset":["#"+c for c in spore_colors],
                           "motion_hint":"small grounded pulse with fixed pivot; spawn/dissolve by game hazard state, no floating pickup bob or glitter",
                           "boundary_note":"scalloped lower contour is visible ground edge; art does not define damage radius or lifetime"})
        else:
            record.update({"usage":"reusable shallow-water footstep ring; transparent center reveals terrain below",
                           "export_alignment":"centered after fit",
                           "motion_hint":"brief expanding ring at foot contact; stop when step ends; no collision",
                           "terrain_note":"water and light shoreline come from map implementation, not this effect"})
        manifest["sprites"][name]=record
        manifest["sources"][source_path.name]={"size":list(source.size),"mode":source.mode,"sha256":sha(source_path),"runtime":False}
    recovery=ROOT/"source/water-ripple.png"
    original=Image.open(recovery)
    manifest["sources"][recovery.name]={"size":list(original.size),"mode":original.mode,"sha256":sha(recovery),"runtime":False}
    atlas.save(ROOT/"atlases/rain_garden.png")
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    rain_preview(manifest,[d[0] for d in definitions])
    print("Exported six rain_garden assets and dedicated atlas; existing assets untouched.")


def rain_preview(manifest,names):
    # QA contact sheet uses native-size sprites, plus a nearest 4x inspection copy.
    board=Image.new("RGB",(480,250),"#3c514c")
    d=ImageDraw.Draw(board)
    for i,name in enumerate(names):
        x,y=(i%3)*160,(i//3)*125
        rec=manifest["sprites"][name]; sprite=Image.open(ROOT/rec["file"])
        # Light and dark backing exposes alpha fringes without changing assets.
        d.rectangle((x,y,x+159,y+98),fill="#c3d1ad" if i%2 else "#374568")
        p=(x+(160-sprite.width)//2,y+72-rec["pivot"][1])
        board.paste(sprite,p,sprite)
        d.text((x+3,y+103),name,fill="#f8e4b6")
        d.text((x+3,y+115),f"{sprite.width}x{sprite.height}; pivot {rec['pivot']}",fill="#c3d1ad")
    board.save(ROOT/"preview/rain-garden-contact-native.png")
    board.resize((1920,1000),Image.Resampling.NEAREST).save(ROOT/"preview/rain-garden-contact-4x.png")
    garden=Image.open(ROOT/"backgrounds/mushroom-garden.png").convert("RGBA")
    entries=[("garden_stump",(111,155)),("sporecaster_idle",(216,149)),
             ("sporecaster_windup",(278,149)),("sporecaster_release",(341,149)),
             ("spore_cloud",(282,211)),("water_ripple",(162,217)),
             ("meemee_walk_se",(162,217)),("sparkcap_idle",(390,194))]
    for name,foot in entries:
        rec=manifest["sprites"][name]; sprite=Image.open(ROOT/rec["file"]); pivot=rec["pivot"]
        garden.alpha_composite(sprite,(foot[0]-pivot[0],foot[1]-pivot[1]))
    garden.save(ROOT/"preview/rain-garden-concept-native.png")
    garden.resize((1440,810),Image.Resampling.NEAREST).save(ROOT/"preview/rain-garden-concept.png")
    # Only the actual three discrete poses, aligned by the shared pivot; no runtime claim.
    frames=[]
    for pose in ("idle","windup","release","idle"):
        frame=Image.new("RGB",(96,80),"#3c514c")
        rec=manifest["sprites"]["sporecaster_"+pose]; sprite=Image.open(ROOT/rec["file"])
        frame.paste(sprite,(48-rec["pivot"][0],60-rec["pivot"][1]),sprite)
        frames.append(frame.resize((384,320),Image.Resampling.NEAREST))
    frames[0].save(ROOT/"preview/sporecaster-poses.gif",save_all=True,append_images=frames[1:],duration=[600,600,300,600],loop=0)
    rec=manifest["sprites"]["garden_stump"]
    base=Image.new("RGBA",(64,64),"#3c514c")
    base.alpha_composite(Image.open(ROOT/rec["file"]))
    outline=ImageDraw.Draw(base)
    outline.polygon([tuple(p) for p in rec["footprint"]["polygon"]],outline="#a9d6ce")
    px,py=rec["pivot"]
    outline.line((px-2,py,px+2,py),fill="#fff3d0")
    outline.line((px,py-2,px,py+2),fill="#fff3d0")
    base.resize((512,512),Image.Resampling.NEAREST).save(ROOT/"preview/garden-stump-footprint.png")


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
            if group == "plain_ui_v2":
                record["pivot"] = [0,0]
                if name == "ui_paper_panel":
                    record["nine_slice_margins"] = [6,12,16,6]
                    record["content_margins"] = [10,14,18,10]
                elif name.startswith("ui_button_plain"):
                    record["nine_slice_margins"] = [10,6,10,6]
                    record["content_margins"] = [12,8,12,8]
            if group in ("world_ui_v2", "plain_ui_v2"):
                record["art_revision"] = 2
                record["usage"] = "contextual world object" if group == "world_ui_v2" else "short paper overlay; render text live"
            manifest["sprites"][name]=record
        sheet.save(ROOT/"atlases"/(group+".png"))
    for name in ["restaurant-interior","restaurant-lane","restaurant-shell","mushroom-garden"]:
        manifest["backgrounds"][name]=export_background(name)
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
    update_rain_assets()
    from build_rain_scene import build_scene
    build_scene()
    from build_meemee_walk import build_walk
    build_walk()


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
    garden_preview(manifest)
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
    v2=[(name,record) for name,record in sprites if record.get("art_revision")==2]
    board2=Image.new("RGB",(640,((len(v2)+1)//2)*210),"#3c514c")
    d2=ImageDraw.Draw(board2)
    for i,(name,record) in enumerate(v2):
        x,y=(i%2)*320,(i//2)*210
        im=Image.open(ROOT/record["file"])
        scale=min(4,300//im.width,175//im.height)
        im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
        board2.paste(im,(x+(320-im.width)//2,y+8),im)
        d2.text((x+12,y+190),name,fill="#f8e4b6")
    board2.save(ROOT/"preview/world-ui-v2-contact.png")


if __name__=="__main__":
    if sys.argv[1:] == ["--garden-only"]:
        update_garden_only()
    elif sys.argv[1:] == ["--rain-only"]:
        update_rain_assets()
    elif sys.argv[1:] == ["--rain-scene-only"]:
        from build_rain_scene import build_scene
        build_scene()
    elif sys.argv[1:] == ["--walk-only"]:
        from build_meemee_walk import build_walk
        build_walk()
    elif not sys.argv[1:]:
        build()
    else:
        raise SystemExit("Usage: build.py [--garden-only|--rain-only|--rain-scene-only|--walk-only]")
