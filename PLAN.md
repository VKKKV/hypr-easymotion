# hypr-easymotion — PLAN

Hyprland easymotion 窗口快速跳转，纯 Lua + Zig 实现。

## 目标

重现 [hyprland-easymotion](https://github.com/zakk4223/hyprland-easymotion) 的核心体验，但不依赖 C++ Hyprland 插件 API。配置全部在 Hyprland 的 Lua 层，渲染和输入捕获用 Zig 写的独立 Wayland client。

## 版本基线 (2026-05-12)

| 组件 | 版本 | 备注 |
|---|---|---|
| OS | Arch Linux | 桌面环境 |
| Hyprland | 0.55.0 | Lua config, hyprlang 已废弃 |
| Lua | 5.5.0 / LuaJIT 2.1 | Hyprland 内嵌 Lua 5.5 |
| Zig | 0.16.0 | Arch 官方包 |
| wayland | 1.25.0 | libwayland-client (Arch: wayland) |
| wayland-protocols | 1.48 | 含 wlr-layer-shell-unstable-v1 |
| cairo | 1.18.4 | 2D 矢量图形 (Arch: cairo) |
| pango | 1.57.1 | 文字排版 + 字体渲染 (Arch: pango) |
| xkbcommon | 1.13.1 | 键盘 keymap / keysym 解析 (Arch: libxkbcommon) |

## 架构

```
SUPER+R 按下
  │
  ▼
easymotion/init.lua (Hyprland 内)
  │
  ├─ hl.get_windows() → 解析窗口列表
  ├─ 过滤可见窗口，按 motionkeys 分配 label
  ├─ 写入 /tmp/easymotion-{PID}.json
  ├─ hl.exec_cmd("easymotion-render /tmp/easymotion-{PID}.json")
  └─ return (Zig 进程接管全部控制)
       │
       ▼
easymotion-render (Zig binary, Wayland layer-shell client)
  │
  ├─ 读取 JSON → label 坐标、文本、样式参数
  ├─ 创建 wlr-layer-shell overlay surface (全屏, exclusive keyboard)
  ├─ PangoCairo 渲染每个 label (圆角矩形 + 文字)
  ├─ poll keyboard events (xkbcommon keysym)
  │   ├─ 命中 motion key → system() 执行 action → exit 0
  │   └─ Escape → exit 1
  └─exit (layer surface 销毁, 键盘控制归还 Hyprland)
```

不需要 Lua submap。Zig 进程的 `keyboard_interactivity = exclusive` 天然阻止 Hyprland 接收键盘事件，退出后自动释放。

## 文件结构

```
~/.config/hypr/easymotion/
├── init.lua               ← 入口: return table, 含 activate() 函数
├── config.lua              ← 主题 / motionkeys / action 配置
├── labels.lua              ← hyprctl → 窗口过滤 → label 分配
├── json.lua                ← 轻量 JSON encoder (只需 encode, ~30行)
├── build.zig               ← zig build
└── src/
    ├── main.zig            ← entry: arg parse, Wayland connect, event loop
    ├── Layer.zig            ← wlr-layer-shell surface + exclusive keyboard
    ├── Labels.zig           ← JSON parse + PangoCairo 渲染
    └── protocol/            ← wayland.xml + wlr-layer-shell.xml
        ├── wayland.zig          (build.zig 中通过 wayland-scanner 生成)
        └── wlr-layer-shell.zig
```

编译产物 `easymotion-render` 为单二进制，安装在 `~/.local/bin/` 或 `~/.config/hypr/lib/`。

## Lua ↔ Zig 接口 (JSON)

Lua 写入临时 JSON 文件，路径作为 CLI 参数传给 Zig：

```jsonc
{
  "action": "hyprctl eval 'hl.dispatch(hl.dsp.focus({window = \"address:{}\"}))'",
  "labels": [
    {
      "key": "a",           // 按这个键选中
      "text": "A",          // 显示的 label 文字
      "address": "0x55...", // Hyprland 窗口地址, 替换 action 中的 {}
      "x": 640, "y": 360,   // 窗口中心坐标 (Lua 侧计算)
      "w": 1280, "h": 720   // 窗口宽高 (Zig 侧用于居中定位 label)
    }
  ],
  "style": {
    "textsize": 128,
    "textcolor": [0.98, 0.85, 0.18, 1.0],   // RGBA float
    "bgcolor":   [0.23, 0.22, 0.20, 0.80],
    "textfont": "JetBrains Mono",
    "textpadding": 8,
    "rounding": 6,
    "bordersize": 2,
    "bordercolor": [0.40, 0.36, 0.33, 1.0]
  }
}
```

- label 的 `x, y` = 窗口左上角像素坐标（来自 `hyprctl clients -j` 的 `at`）
- label 的 `w, h` = 窗口像素尺寸（来自 `size`）
- Zig 侧根据 `w, h` 计算 label 矩形在窗口中心的精确像素位置
- 颜色用 RGBA float 数组，避免字符串解析歧义

## 默认配置 (Gruvbox 主题)

```lua
-- ~/.config/hypr/easymotion/config.lua
return {
  motionkeys = "arstneio",
  action = "hyprctl eval 'hl.dispatch(hl.dsp.focus({window = \"address:{}\"}))'",
  only_special = true,

  textsize   = 128,
  textcolor  = {0.98, 0.85, 0.18, 1.0},   -- Gruvbox Yellow #fabd2f
  bgcolor    = {0.23, 0.22, 0.20, 0.80},   -- Gruvbox Dark Gray #3c3836 CC
  textfont   = "JetBrains Mono",
  textpadding = 8,
  rounding   = 6,
  bordersize = 2,
  bordercolor = {0.40, 0.36, 0.33, 1.0},   -- Gruvbox Medium Gray #665c54
}
```

`keybindings.lua` 接入:

```lua
local easymotion = require("easymotion")
hl.bind("SUPER + R", function()
  local ok, err = easymotion.activate()
  if not ok then
    print("easymotion: " .. tostring(err))
  end
end)
```

Lua 层必须在 `activate()` 里先写 JSON 再 spawn，这样 JSON 写入和进程启动是原子的。不要把按键直接绑定到 `easymotion-render /tmp/...`，否则 renderer 可能读取不存在或过期的配置文件。

## Zig 层关键技术点

### 1. Wayland 连接 + registry
标准流程，~50 行。bind `wl_compositor` v6、`zwlr_layer_shell_v1` v5、`wl_seat` v9、`wl_shm`。

参考:
- https://wayland-book.com/ (Wayland 协议入门)
- https://wayland.app/protocols/ (协议浏览器, 每个 request/event 的签名)
- `/usr/share/wayland/wayland.xml` (本地协议定义)
- https://gitlab.freedesktop.org/wlroots/wlr-protocols/-/blob/master/unstable/wlr-layer-shell-unstable-v1.xml

### 2. Layer surface 创建
```
wlr_layer_surface_v1:
  namespace = "easymotion"
  layer = ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY
  anchor = 全屏 (top|bottom|left|right 全部 set)
  exclusive_zone = -1  (不排挤其他 surface)
  keyboard_interactivity = 1  (exclusive: 阻断所有 Hyprland 快捷键)

wl_surface commit → 得到 configure 事件 → ack → 渲染
```

参考:
- https://wayland.app/protocols/wlr-layer-shell-unstable-v1

Hyprland 的 `layer_rule` 可以匹配 `namespace = "easymotion"`，控制 blur/ignore_alpha/动画。

### 3. PangoCairo 渲染
每个 label:
1. `cairo_rectangle` + `cairo_fill` 画圆角背景
2. `cairo_set_line_width` + `cairo_stroke` 画边框
3. `pango_layout_set_text` + `pango_cairo_show_layout` 渲染文字
4. `wl_surface_damage_buffer` + `wl_surface_commit`

只渲染一次（label 不移动不变化，按完键就退出），不需要帧循环。

参考:
- https://docs.gtk.org/Pango/ (Pango API)
- https://www.cairographics.org/manual/ (Cairo API)

### 4. 键盘事件
1. `wl_keyboard_listener.keymap` → `xkb_keymap_new_from_string`
2. `wl_keyboard_listener.key` → `xkb_state_key_get_one_sym` → keysym
3. keysym 转字符: `xkb_keysym_to_utf8` 得到 UTF-8 字符串
4. 与 labels 的 `key` 字段字符串匹配
5. 匹配命中 → `std.process.Child.exec("hyprctl", ...)` 或 `std.os.system()`
6. Escape → cleanup + exit

参考:
- https://xkbcommon.org/doc/current/ (xkbcommon API)

### 5. SHM buffer (像素数据载体)
最简单方案: `wl_shm_pool` + mmap。Cairo 可以直接画到 SHM buffer 上。
或者用 `cairo_image_surface_create_for_data` 指向 mmap 的 SHM 内存。

## Hyprland 集成注意点

- **`HYPRLAND_INSTANCE_SIGNATURE`**: 多实例场景下标识 Hyprland socket。JSON 文件名建议包含此签名，确保多 session 不冲突。
- **`hl.get_windows()`**: 当前实现直接使用 Hyprland Lua API 读取窗口 userdata，再转换成 `{address, mapped, hidden, fullscreen, at, size, workspace}` 结构供 label 过滤使用。
- **fullscreen 窗口处理**: `hyprctl clients -j` 的输出包含 `fullscreen` 字段 (0/1/2)。原插件支持 `fullscreen_action = toggle/maximize/none`。V1 可先不支持（fullscreen 窗口不挂 label 或加 `fullscreen_action = "none"` 跳过）。
- **special workspace**: `hyprctl clients -j` 包含 `workspace.id`。通过 `hyprctl activeworkspace -j` 判断当前是否有 special workspace active。如果 `only_special = true` 且当前显示 special workspace，只给 special workspace 的窗口挂 label。
- **Zig 进程生命周期**: `hl.exec_cmd()` 是 fire-and-forget，不需要 `&`。Zig 进程退出后 layer surface 自动销毁，键盘控制自动归还。不需要进程间通信协议。
- **临时文件清理**: Lua 在 `activate()` 写入 JSON，Zig 启动后先 rename/delete JSON 再读取（或直接读取后 unlink），Lua 侧无需清理。

## 开发增量计划

### Phase 1: 最小可验证
- `easymotion-render` 能创建全屏透明 surface + 在固定位置画一个 label + 按任意键退出
- Lua 侧: 只 spawn Zig binary，不做 JSON

### Phase 2: JSON 通道
- Zig 读取 JSON，渲染多个 label
- Lua 侧: `hyprctl clients -j` → 构造 labels JSON → 写文件 → spawn

### Phase 3: 键盘匹配 + action
- Zig keyboard handler 匹配 motion key → 执行 action → exit
- Lua 侧: config 可配置 action / motionkeys

### Phase 4: 主题 + 边缘情况
- 完整 style 参数传递
- only_special / fullscreen 处理
- 多个 monitor 支持
- 窗口数量超过 motion keys 时的截断

## 相关仓库

- [zakk4223/hyprland-easymotion](https://github.com/zakk4223/hyprland-easymotion) — 原 C++ 插件，本项目参考对象
- [hyprwm/Hyprland](https://github.com/hyprwm/Hyprland) — Hyprland 0.55.0+, Lua config
- [Hyprland Wiki - Configuring](https://wiki.hypr.land/Configuring/Start/) — 官方配置文档
- 本地参考: `/home/kita/code/knowledge/references/hyprland/hyprland-config-reference.md` — 从 wiki 全量抓取的中文参考
- [ziglang/zig](https://github.com/ziglang/zig) — Zig 0.16.0
- 本地参考: `/home/kita/code/hyprland-easymotion/` — 原插件源码

## License

GPLv3-or-later.
