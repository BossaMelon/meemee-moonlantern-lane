# UI 接口与输入检查

`scenes/main.tscn` 的 Control 使用 `main.gd`。所有经济命令、经营阶段和持久状态由 `GameSession` 负责；UI 只读取 `view()`，每次玩家意图使用新的 request ID。按钮数量与可用条件随 view 重建。

- `get_action_control(action_id)` 只用于定位真实控件、读取点击坐标和观察焦点。验收应注入 `InputEvent`，不能直接发 `pressed` 信号或直接调用核心命令代替 UI 路径。
- 按钮至少 48×48 逻辑像素，使用 Control 焦点链。D-pad/方向键导航、手柄南侧面键确认、Escape/Start 暂停。触屏使用 Godot 公开的触控鼠标模拟。
- 暂停时禁用经营按钮；保存、恢复及查看页签仍可操作。特殊需求保持在当前订单，普通营业不推进。重建不立即释放正在发信号的对象；回调延迟到事件分发完成后执行。
- 营业时间以 UI 累积的 100ms 批次交给 `advance()`；不在逐帧整数舍入中丢时间。暂停、特殊需求或非营业阶段清除尚未提交的 UI 计时余量。
- 根 Control 按实际窗口尺寸重排，避免把整个 1280×720 界面缩小到窄屏。业务列表可滚动，焦点移动会确保目标可见。

## 图像挂接

`main.gd` 导出 `interior_art_path` 与 `lane_art_path` 两个 PNG 路径，由场景绑定 A01 实际交付的资源。`shop_canvas.gd` 使用 TextureRect 与 nearest 采样、等比完整显示；`show_lane(bool)` 切换内外景。A01 的像素文件与 manifest 归美术任务所有，P02 不覆盖。缺图时显示明确提示，不以旧代码矢量画代替资产。

## 可执行输入回归

```sh
Godot --headless --path . --max-fps 60 --script game/ui/checks/interaction.gd
Godot --path . --max-fps 60 --script game/ui/checks/interaction.gd -- mouse
Godot --path . --max-fps 60 --script game/ui/checks/interaction.gd -- touch pad
Godot --path . --max-fps 60 --script game/ui/checks/interaction.gd -- resume
```

脚本通过鼠标事件、模拟触屏事件或模拟 D-pad/A 输入驱动真实 Control；每种路径使用工作树 `output/p02/` 内独立临时存档，不修改玩家默认存档。`resume` 需要先完成鼠标路径；它在新引擎进程中经恢复按钮读取上一个进程保存的文件、检查日结防重，再经保存退出按钮关闭。

有显示的运行以 viewport 图像保存 PNG，报告注明实际显示驱动、引擎版本、断言和输入轨迹。断言失败退出非零；Computer Use 不参与这些检查。模拟输入不证明 iOS 真机或实体手柄可用。该脚本中的旧 catalog 路径仅供通用控件回归；产品验收始终以冻结后的料理/动作契约及实际候选为准。
