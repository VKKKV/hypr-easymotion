# 按 PLAN 实现 hypr-easymotion

## Goal

根据 `PLAN.md` 开发 hypr-easymotion：用 Hyprland Lua 配置层生成窗口跳转 label 数据，用 Zig 独立 Wayland layer-shell client 渲染 overlay 并捕获键盘输入，重现 hyprland-easymotion 的核心窗口快速跳转体验，同时避免依赖 C++ Hyprland 插件 API。

## What I Already Know

- 项目目标是纯 Lua + Zig 实现 Hyprland easymotion 窗口快速跳转。
- 运行环境基线：Arch Linux、Hyprland 0.55.0、Lua 5.5/LuaJIT 2.1、Zig 0.16.0、Wayland 1.25.0、wayland-protocols 1.48、cairo 1.18.4、pango 1.57.1、xkbcommon 1.13.1。
- 计划架构：Lua 侧调用 `hyprctl clients -j`，过滤可见窗口，分配 motionkeys，写 JSON，启动 `easymotion-render`。
- Zig 侧作为 Wayland layer-shell overlay client，读取 JSON，渲染 label，使用 exclusive keyboard 捕获按键，命中后执行 `hyprctl dispatch focuswindow address:{}` 并退出。
- 当前仓库除 `PLAN.md` 和 Trellis 初始化文件外，没有现成 Lua/Zig 实现代码。

## Requirements

- 建立项目文件结构：Lua 模块、Zig build 配置、Zig 源码目录和协议生成/引用位置。
- Lua 侧提供 `init.lua`、`config.lua`、`labels.lua`、`json.lua`。
- Lua 侧 `activate()` 能读取 Hyprland 窗口列表、过滤窗口、按 `motionkeys` 分配 label、写入临时 JSON、启动 `easymotion-render`。
- JSON 接口采用 `PLAN.md` 中定义的 `action`、`labels`、`style` 结构。
- Zig 侧提供 `easymotion-render` 二进制入口，能读取 JSON 配置。
- Zig 侧创建全屏透明 layer-shell overlay surface，namespace 为 `easymotion`，并请求 exclusive keyboard。
- Zig 侧使用 cairo/pango 渲染 label 背景、边框和文字。
- Zig 侧处理键盘输入：Escape 退出；匹配 label key 时执行配置的 action 并退出。
- 支持默认 Gruvbox 主题参数。
- 对窗口数量超过 `motionkeys` 的情况进行可预期截断。
- 支持完整 style 参数传递：文字大小、文字颜色、背景颜色、字体、内边距、圆角、边框大小、边框颜色。
- 支持 `only_special`：当当前显示 special workspace 且配置开启时，只给 special workspace 窗口挂 label。
- 支持 fullscreen 处理：MVP 默认跳过 fullscreen 窗口，避免 overlay/focus 行为不确定。
- 支持多个 monitor：label 坐标按 Hyprland 输出的全局坐标渲染到覆盖所有 monitor 的 overlay 上。

## Acceptance Criteria

- [ ] `zig build` 能构建 `easymotion-render`。
- [ ] Lua 模块能被 Hyprland Lua 配置 `require("easymotion")` 加载，并暴露 `activate()`。
- [ ] Lua 侧能生成符合约定结构的 JSON 文件。
- [ ] Zig 侧能解析 Lua 生成的 JSON 并渲染多个 label。
- [ ] 按 Escape 能退出 overlay。
- [ ] 按匹配 motion key 能执行 `hyprctl dispatch focuswindow address:<address>` 或配置的 action 模板。
- [ ] `only_special` 开启且当前 special workspace active 时，只生成 special workspace 窗口 label。
- [ ] fullscreen 窗口按 MVP 策略跳过，不生成 label。
- [ ] 多 monitor 下 label 使用 Hyprland 全局窗口坐标定位。
- [ ] 所有 PLAN style 字段都能从 Lua 配置传递到 Zig 渲染层。
- [ ] 代码包含基本错误处理，失败时输出清晰错误并退出非零状态。
- [ ] 项目文档说明构建、安装和 Hyprland 配置接入方式。

## Definition Of Done

- `zig build` 通过。
- 可运行的 Lua + Zig 端到端最小实现完成。
- README 或等效文档说明依赖、构建、安装、配置和使用方式。
- Trellis check 阶段完成；如发现项目规范需要补充，更新 `.trellis/spec/`。

## Technical Approach

- 按 PLAN 的增量路线实现完整 MVP：先搭建 Zig Wayland overlay，再接 JSON，再接键盘匹配/action，再补 Lua 生成 JSON，最后补齐 style、special workspace、fullscreen 和多 monitor 行为。
- Lua 侧保持轻量、无第三方依赖，使用小型 JSON encoder。
- Zig 侧优先选择直接 C ABI 调用 Wayland/Cairo/Pango/xkbcommon，避免引入额外包管理复杂度。
- 协议文件优先从系统路径或仓库内协议 XML 生成/引用，保证构建可重复。

## Decision (ADR-lite)

**Context**: This is a greenfield implementation with no existing code, so the first milestone needs a simple architecture that can be validated end to end without speculative complexity.

**Decision**: Use a single full-screen layer-shell surface as the default overlay model, render all labels in global compositor coordinates, skip fullscreen windows in MVP, and ship `only_special`, full style propagation, and motionkey truncation in the first complete implementation.

**Consequences**: The first implementation stays straightforward to build and verify. If monitor-specific surfaces are later needed, they can be added without changing the Lua JSON contract.

## Out Of Scope

- C++ Hyprland 插件 API 集成。
- Lua submap 方案。
- 复杂动画、模糊规则和 Hyprland layer_rule 自动配置。
- 原插件全部高级行为完全对齐。

## Technical Notes

- 主要参考：`PLAN.md`。
- 本地参考源码：`/home/kita/code/hyprland-easymotion/`。
- Hyprland 中文参考：`/home/kita/code/knowledge/references/hyprland/hyprland-config-reference.md`。
- 需要读取 `.trellis/spec/backend/index.md` 及相关 backend 规范，因为本任务主要是 CLI/系统集成/构建实现。
