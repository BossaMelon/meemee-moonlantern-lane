# World 建筑与低柜组件接口

本包是 A01 的七件可组合素材；生产 UI 尚未消费。读取入口仍为既有 `manifest.json` 的 `sprites`，没有改变 reader schema。专用 atlas 为 `atlases/world_building_kit.png`，源图与裁切来源见 `world-building-provenance.json`。旧 PNG、atlas、角色、动画和 provenance 文件均保留。

| ID | PNG 画布 | 有效内容 | 用途 |
|---|---:|---:|---|
| `world_wall_h` | 100×92 | 96×88 | 地面96×24，墙高64 |
| `world_wall_v` | 28×164 | 24×160 | 地面24×96，墙高64 |
| `world_wall_corner` | 28×92 | 24×88 | 地面24×24，墙高64；转角/端头 |
| `world_wood_top` | 36×20 | 32×16 | 安静的重复台面 |
| `world_wood_front` | 36×28 | 32×24 | 固定24px低柜前板 |
| `world_wood_end` | 12×28 | 8×24 | 前板左右收口 |
| `world_wood_foot` | 12×28 | 8×24 | 同高度的落地支脚 |

所有纹理都有2px透明边；重复拼接时取 `content_region`，不要把透明边算入地面尺寸。墙记录另含 `construction.cap_region/face_region/ground_rect`，坐标均相对于单张 PNG；`region` 才是整张 PNG 在 atlas 内的区域。最小单位1px，最近邻采样，硬 alpha，十色导出子集属于既有32色板。

## 坐标与拼装

遵循现有 Core：x向右、y向下，矩形x/y为中心，人物坐标为脚点。不旋转或压缩地面坐标成菱形。以下只规定绘图，不增加或调整 collider、锚点、交互半径。

低柜/台桌：取已有矩形中心 `(cx,cy)`、宽深 `(w,d)`，令 `left=cx-w/2, top=cy-d/2`。

1. 在 `(left,top-24)` 铺台面，目标大小为 `w×d`。32×16重复，边缘剩余部分裁切；不要缩放整个家具。
2. 在 `(left,top+d-24)` 横向铺前板，大小 `w×24`，高度永远24。
3. 左右收口分别放在前板的 `x=left` 和 `left+w-8`，地脚与 `top+d` 对齐。支脚可用于相同高度的柜体框架，不用于延长旧悬挂草药架。
4. 成品覆盖 `w×(d+24)`，在原 footprint 内没有透明缺口。角色使用原48×64画布与脚点，不跟随家具缩放。

这套比例用于 pantry96×112、prep128×80、stove112×80、pass144×64、table96×64，QA还覆盖recipe40×32与ledger60×48。大台面由小块重复形成；工作物件在台面上独立放置。现有大型 `stove/prep_table/herb_shelf` 整张图并非此低柜的台面装饰，不再按碰撞宽度整体放大。

recipe-body 的中心仍为 `(430,430)`，操作锚点仍为 `(430,466)`。用同样规则做40×32支承面，QA把已有64×48书图以0.5倍最近邻显示成32×24并放在支承面上；不挪核心锚点，不生成重复书资产。其他锅、食材与菜品是原素材的同尺度摆放示意，不代表真实经营状态。

墙：对已有墙矩形同样取 `left,top,w,d`。顶面绘于 `(left,top-64)`，目标 `w×d`；前端立面绘于 `(left,top+d-64)`，目标 `w×64`。使用相应 cap/face 区域重复裁切，始终保留64px高立面。不要将整张墙图伸缩，也不要旋转H墙去代替V墙。连续共线段先作为一个可见墙段组装，重叠拐角仅归一个组件，按地面南沿排序；`build_world_building.py` 的 `wall()` 和接缝图给出参考。

## 真实门口与遮挡

fixture revision1 的店铺东墙分为 `shop-e-n` 和 `shop-e-s`，真实开口为 y520..640、宽120；保持这段开放，不添假墙或窄门框。墙面向上延伸64像素，因此南端顶面在屏幕上会向开口投影；不得据投影修改物理开口。应由 UI 沿用实际脚点处理遮挡。

巷道西墙是连续实体墙，`lane-home` 的真实交互锚点是 `(80,256)`，不是可步行穿墙的缺口。QA把旧48×64门叶贴到西墙、PNG左上角为 `(0,194)`，人物保持在 `(80,256)`：它是墙上可接近的传送门入口，不凭空画另一条可走通道。这里只给出视觉附着示例；生产提示、命中和可操作锚点仍取 Core。未新增门框资产。

## 可复现检查图

运行 `python3 assets/pixel/build_world_building.py`（需要 Pillow）仅追加/重建本包，生成 Git 忽略的 `assets/pixel/evidence/world-building-kit/`：

- `contact-native.png` / `contact-3x.png`：七模块及画布尺寸。
- `scale-native.png` / `scale-2x.png` / `scale-footprints.png`：真实宽深、24px柜身与原生角色；洋红框为地面 footprint，蓝线为台面拼接边。
- `walls-join-native.png` / `walls-join-3x.png`：H、V、corner拼接。
- `walls-shop-*` / `walls-lane-*`：原fixture门口与门叶附着。
- `shop-layout-native.png` / `shop-spawn-640x360.png`：原店铺坐标组合和出生镜头的静态裁切。平色底仅为检查背景，不是新的地板素材。

这些是 Pillow 素材组装检查，不能作为 Godot 全屏、真实输入、碰撞运行或趣味验收。生产接入后的遮挡、门提示与同机全屏比例由 P11/V02 验证；本包不启动前台游戏，不改 UI/Core/契约。

定向验证：`python3 assets/pixel/verify_world_building.py` 检查台面边缘重复、实际fixture尺寸、固定高度、所有地面覆盖，以及相对639ea819全部旧像素文件和记录的保留。再以七个ID调用既有 `verify.py` 检查编码、atlas与来源。旧全包未变化部分无需为本包重跑玩法测试。
