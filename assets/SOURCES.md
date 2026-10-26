# 原型素材来源

- 运行时像素图像来自 A01 的 `assets/pixel/**`。当前接入基线为 `41770a1`；原始生成图、确定性像素导出、色板、硬透明及来源见该目录的 `SOURCES.md` 与 `manifest.json`。P02 只读取资产，不覆盖美术文件。
- 旧 prototype/rain 组件使用 `restaurant-shell`、`restaurant-lane` 与 `restaurant-layout.json`。P11 世界按 Core 实际几何消费独立家具与角色脚底 pivot，不用完整背景冒充可走区；640×360 视口 nearest 整数放大并保留黑边。地面复用原地砖，降低重复图案的面积和对比。
- 店主、客人、海格和菜品均加载实际 PNG。出餐、搅拌、暖焰、星火轨迹与彗尾由成功制作/成交触发；只有视觉，不决定顾客匹配、伤害或奖励。
- UI 按钮使用 A01 像素九宫格，文字实时排版，焦点框另由 Control 输入系统维护。
- 随包字体为下述官方 Noto Sans SC，公共字体入口是 `game/ui/portable_font.gd` 的 `get_font() -> Font`；只使用包内 FontFile，不复制或分发系统字体。各 UI 入口的实际绑定、导出与目标设备结果分别验收，Mac 截图不代替 Windows/iOS 或安全区验证。
- 当前无来源不明的音乐、音效或电影截图；未购买素材或开通服务。

P11 世界呈现复用已验收 A01 的四向 `meemee_walk_*_cycle`（各四帧、125ms/帧、循环500ms）。每帧使用清单脚底 pivot，动画相位只随 Core 实际位移推进；停步、碰撞与暂停保持相位。P11 不改像素图或资产清单；门铃提示使用 Core 锚点上的程序绘制标记，未冒用不存在的门铃贴图。

携带物复用 `floating_plates` 形成手边盘组；同种图标只汇总显示，仍绑定所有真实 UID。料理状态放在台面附近的安静底色中，不增加图像资产。建筑与家具尺度的原 ba4 图像仍是负例，待专用墙/低台体 kit 后再验收，不以这些呈现修订宣称视觉已通过。

## 随包文字字体

- 原文件：`assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf`，官方中国区域静态 Regular 400；Noto Sans SC 2.004，内部版本 `Version 2.004;hotconv 1.0.118;makeotfexe 2.5.65603`。保留官方原始字节，不自行裁剪、改名或合成字重。
- [固定官方文件](https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf)，8331336 字节；Git blob SHA-1 `fc0fda9394367c16c1af7555a2ae4d5e2e6a6f02`（含 Git blob header，不是裸文件 SHA-1）；文件 SHA-256 `faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9`。
- [同 commit 的 OFL 1.1 原许可证](https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/LICENSE) 原样保存在 `assets/fonts/noto-sans-sc/OFL.txt`；字体内原版权 `© 2014-2021 Adobe (http://www.adobe.com/).` 另存 `NOTICE.txt`，随字体一起分发。
- 精确版本、原始文件/许可/版权 hash 和资源路径见 `assets/fonts/font-manifest.json`。通过 Godot 正常动态字体导入为 FontFile；导入配置和共享入口均禁用系统回退，显式 fallbacks 为空。保留现有字号、颜色、间距与灰度抗锯齿，不改变像素素材。
