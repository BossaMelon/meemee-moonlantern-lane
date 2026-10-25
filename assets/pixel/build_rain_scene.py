#!/usr/bin/env python3
"""Export ImageGen scene layers and QA alignment previews, never gameplay geometry.

The coordinates below are a read-only preview snapshot of E02 map revision 1
(SHA in rain-scene-provenance.json). The E02 map remains the runtime authority.
"""
import json
from PIL import Image, ImageDraw
from build import ROOT, hard_alpha, palette_export, GARDEN_PALETTE, GARDEN_COLORS, sha

ROUTES={"dry":[(80,270),(230,130),(460,95),(650,110),(820,180)],
        "wet":[(80,270),(230,365),(365,385),(520,375),(670,405),(820,365)],
        "connector":[(460,95),(470,260),(520,375)]}
LONGS=[("garden_root_log_50",(395,187.5),50),
       ("garden_root_log_45",(727.5,262.5),45)]
WATER_RECT=[340,335,340,120]


def build_scene():
    manifest=json.loads((ROOT/"manifest.json").read_text())
    source=hard_alpha(Image.open(ROOT/"source/rain-ground-routes.png"))
    # Export on the existing scene's 2-logical-pixel grid, then integer nearest 2x.
    ground=palette_export(source.resize((480,270),Image.Resampling.NEAREST),GARDEN_PALETTE)
    ground=ground.resize((960,540),Image.Resampling.NEAREST)
    source_water=hard_alpha(Image.open(ROOT/"source/rain-canal-shallow-v2.png"))
    # Inner opaque rectangle: keeps the wet region exact, with no painted bank outside it.
    water_crop=[155,149,1957,597]
    water=source_water.crop(water_crop)
    assert water.getchannel("A").getextrema()==(255,255)
    water_colors=["3d5654","364d4b","4c6156","4e5d78"]
    water_palette=Image.new("P",(1,1))
    values=[v for c in water_colors for v in bytes.fromhex(c)]
    water_palette.putpalette(values+values[:3]*(256-len(water_colors)))
    water=palette_export(water.resize((170,60),Image.Resampling.NEAREST),water_palette)
    water=water.resize((340,120),Image.Resampling.NEAREST)
    for name,im,original,crop,rect in [
        ("rain_ground_routes",ground,"rain-ground-routes",[0,0,*source.size],[0,0,960,540]),
        ("rain_canal_shallow",water,"rain-canal-shallow-v2",water_crop,WATER_RECT),
    ]:
        path=ROOT/"backgrounds"/(name+".png"); im.save(path)
        manifest["backgrounds"][name]={
            "file":str(path.relative_to(ROOT)),"size":list(im.size),"logical_size":list(im.size),
            "source":"source/"+original+".png","source_crop":crop,"sha256":sha(path),
            "palette":["#"+c for c in GARDEN_COLORS],"asset_set":"rain_scene",
            "logical_rect":rect,"pivot":[0,0],"pixel_grid":2,
            "purpose":"flat visual layer; E02 map revision 1 owns movement and collisions",
            "draw_order":"after existing background, before dynamic obstacles/actors/hazards",
        }
    manifest["backgrounds"]["rain_ground_routes"]["usage"]="transparent low-contrast worn routes; replaces debug route polylines"
    manifest["backgrounds"]["rain_canal_shallow"]["usage"]="opaque shallow canal bottom; exact wet rectangle, flush bank inside boundary; replaces water debug fill/outline and tiled ripple grid"
    manifest["backgrounds"]["rain_canal_shallow"]["export_palette_subset"]=["#"+c for c in water_colors]
    atlas=Image.new("RGBA",(140,125))
    log_source=hard_alpha(Image.open(ROOT/"source/garden-root-log-v2.png"))
    # Remove 50 source pixels of uneven root tips, leaving a continuous visible contact edge.
    log_crop=[299,76,836,1278]
    for index,(name,center,foot_width) in enumerate(LONGS):
        width=foot_width+20
        im=Image.new("RGBA",(width,125))
        im.paste(log_source.crop(log_crop).resize((width-2,125),Image.Resampling.NEAREST),(1,0))
        im=palette_export(im)
        path=ROOT/"sprites"/(name+".png"); im.save(path)
        atlas.paste(im,(index*70,0))
        manifest["sprites"][name]={
            "file":str(path.relative_to(ROOT)),"size":[width,125],
            "source":"source/garden-root-log-v2.png","source_crop":log_crop,
            "export_method":"nearest resize of shared source crop; 1px horizontal padding",
            "atlas":"atlases/rain_scene_logs.png","region":[index*70,0,width,125],
            "pivot":[width/2,77.5],"opaque_bounds":list(im.getbbox()),"sha256":sha(path),
            "asset_set":"rain_scene","usage":"one continuous north-south root log; draw at model center, scale 1; no repeated stump stack",
            "footprint":{"space":"native sprite pixels; origin top-left",
                         "kind":"visible_coverage_of_existing_model_rectangle",
                         "rect":[10,30,foot_width,95],
                         "polygon":[[10,30],[9+foot_width,30],[9+foot_width,124],[10,124]],
                         "authority":"E02 map revision 1; rect uses half-open bounds; polygon covers its pixel centers; never create collision from art"},
            "placement_hint":{"map_revision":1,"model_center":list(center),
                              "model_id":"north-west-stump" if index==0 else "deep-stump",
                              "sorting":"model center; sprite extends 30px above footprint for raised body"},
        }
    atlas.save(ROOT/"atlases/rain_scene_logs.png")
    source_names=["rain-routes-layout-guide","rain-ground-routes","rain-canal-shallow","rain-canal-shallow-v2","garden-root-log-v1","garden-root-log-v2"]
    for name in source_names:
        path=ROOT/"source"/(name+".png"); im=Image.open(path)
        manifest["sources"][path.name]={"size":list(im.size),"mode":im.mode,"sha256":sha(path),"runtime":False}
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
    previews(manifest)
    print("Exported two flat scene layers and two root-log variants; existing art untouched.")


def previews(m):
    scene=Image.open(ROOT/"backgrounds/mushroom-garden.png").convert("RGBA").resize((960,540),Image.Resampling.NEAREST)
    scene.alpha_composite(Image.open(ROOT/m["backgrounds"]["rain_ground_routes"]["file"]))
    scene.alpha_composite(Image.open(ROOT/m["backgrounds"]["rain_canal_shallow"]["file"]),(340,335))
    for name,foot,_ in LONGS:
        r=m["sprites"][name]; p=r["pivot"]
        scene.alpha_composite(Image.open(ROOT/r["file"]),(round(foot[0]-p[0]),round(foot[1]-p[1])))
    scene.save(ROOT/"preview/rain-scene-native.png")
    # Actual existing actors show scale only, never baked into either runtime ground layer.
    actors=scene.copy()
    for name,foot in [("meemee_walk_se",(170,270)),("sporecaster_idle",(610,405)),("moonheart_guard",(805,225))]:
        r=m["sprites"][name]; p=r["pivot"]; im=Image.open(ROOT/r["file"])
        # Frozen E02 _sprite defaults to 2x for actors; logs explicitly use scale 1.
        im=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
        actors.alpha_composite(im,(round(foot[0]-p[0]*2),round(foot[1]-p[1]*2)))
    actors.save(ROOT/"preview/rain-scene-scale.png")
    layout=scene.copy(); d=ImageDraw.Draw(layout)
    for points in ROUTES.values(): d.line(points,fill="#d2a06d",width=1)
    d.rectangle((340,335,679,454),outline="#a9d6ce",width=1)
    d.text((340,458),"water [340,335,340,120] - flat/crossable",fill="#a9d6ce")
    for name,center,width in LONGS:
        x,y=center; d.rectangle((int(x-width/2),int(y-47.5),int(x+width/2)-1,int(y+47.5)-1),outline="#a9d6ce",width=1)
        d.line((x-3,y,x+3,y),fill="#fff3d0"); d.line((x,y-3,x,y+3),fill="#fff3d0")
    # Unchanged circle/short obstacles are reference outlines only in this QA view.
    for x,y,r in [(265,270,30),(585,150,35),(450,430,28)]:
        d.ellipse((x-r,y-r,x+r,y+r),outline="#c46588",width=1)
    d.rectangle((505,275,564,319),outline="#c46588",width=1)
    d.text((10,520),"QA alignment only: pink=existing obstacles; cyan=model bounds; tan=route reference; not runtime",fill="#f8e4b6")
    layout.save(ROOT/"preview/rain-scene-layout.png")
    contact=Image.new("RGBA",(340,170),"#3c514c"); draw=ImageDraw.Draw(contact)
    for i,(name,_,_) in enumerate(LONGS):
        r=m["sprites"][name]; im=Image.open(ROOT/r["file"])
        contact.alpha_composite(im,(20+i*170,5))
        draw.text((8+i*170,138),name,fill="#f8e4b6")
        draw.text((8+i*170,151),str(r["footprint"]["rect"]),fill="#a9d6ce")
    contact.save(ROOT/"preview/rain-scene-logs-native.png")
    contact.resize((1020,510),Image.Resampling.NEAREST).save(ROOT/"preview/rain-scene-logs-3x.png")


if __name__=="__main__":
    build_scene()
