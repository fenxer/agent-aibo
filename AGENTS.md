# AGENTS.md

**aibo** 是一个 macOS 原生桌面宠物。宠物常驻桌面，用气泡播报本机 AI Agent（Cursor、Codex）的运行状态，以及远程 Webhook 通知（后者会经过人设 + 大模型改写）。

本文件只列每次对话都要遵守的红线。**详细设计与执行规范在 [`PLANS.md`](./PLANS.md)，动手前按 §路标 查阅对应章节。**

持续学习记忆（用户偏好 / 工作区事实）见 [`AGENTS_LEARNED.md`](./AGENTS_LEARNED.md)；由 `continual-learning` 维护，**不要**往本文件追加 `## Learned …` 小节。

---

## 红线（不可协商）

与这些冲突时**停下来问用户，不要自行取舍**。

- **仅 macOS，仅原生。** SwiftUI + AppKit。禁止 Electron、Tauri、Flutter、WebView 渲染 UI。不做跨平台抽象。
- **零第三方依赖。** `AiboKit/Package.swift` 的 `dependencies` 保持为空，Xcode 项目不加任何 SPM/CocoaPods 依赖。
- **极低资源占用是核心卖点。** 全事件驱动、**零轮询**、空闲时停掉一切动画、高频路径上的重活要节流。引入任何定时器或常驻后台工作前先问用户。
- **最低支持 macOS 26，用 SDK 27 编译。** 不写任何 `if #available` 向下兼容分支。
- **面向开源。** 按"会有陌生人来提 PR"的标准写代码、注释和错误信息。
- **不做范围蔓延。** 不主动创建 demo、示例、额外文档；不添加用户没要求的功能和配置项。
- **不擅自改回用户手工调过的样式数值**（间距、尺寸、动画时长），除非确实导致功能问题。
- **绝不破坏用户的配置文件。** 改写 `~/.cursor/hooks.json` 这类文件时：只增删属于 aibo 的条目、安装幂等、解析失败就中止而不是覆写、原子写入。→ PLANS §5.6

## 三个最容易搞错的前提

- **本机 agent 状态用 hooks，不是 webhook。** Cursor 的 Webhook 是云端 Cloud Agent 机制，localhost 收不到，且只有终态。走 `~/.cursor/hooks.json` 和 `~/.codex/hooks.json`。→ PLANS §5.1
- **宠物窗口必须是 `NSPanel` 子类，不是 SwiftUI `Window`。** 纯 SwiftUI 做不到透明 + 非激活 + 跨 Space。其余 UI（菜单栏、设置）才用纯 SwiftUI。→ PLANS §6.1
- **只有远程 Webhook 才调 LLM。** 本机 agent 状态是高频事件，必须模板直出。→ PLANS §5.5

## 常用命令

```bash
cd AiboKit && swift test    # 只改了核心逻辑时用这个，秒级
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build
./Scripts/run.sh            # 构建并启动 app
```

改完代码必须验证能编译。GUI app 不能用 `swift run` 启动。→ PLANS §3

## 行为准则

- 动手前先读相关源文件，不要凭文件名猜测编码。
- **查 Apple / Swift / SwiftUI / AppKit 文档时用 Context7**（skill：`context7`，或 MCP `user-context7`）。对 API 语义、参数、版本行为不确定时先查，不要靠过时训练记忆硬猜；查完仍不确定运行时行为时，再写最小片段用 `swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0` 实测。
- 新增源文件优先放 `AiboKit/`（不用改 `.pbxproj`）。只有确实依赖 AppKit/SwiftUI 的才放 `App/`。
- `AiboCore` 绝不能 `import AppKit` 或 `import SwiftUI`。

---

## 路标

| 你要做的事 | 读 PLANS.md 的 |
| --- | --- |
| 搭项目骨架、改构建配置 | §2 环境与构建系统、§4 目录结构 |
| 跑构建 / 测试，遇到构建报错 | §3 命令清单 |
| 接入 agent 状态、写 hook 相关代码 | §5.1 hooks、§5.2 状态机、§5.3 aibo-hook |
| 读写用户的 hooks.json（安装/卸载） | §5.6 —— **动手前必读**，写坏用户配置是本 app 能造成的最大伤害 |
| 想显示 hook 给不了的信息（模型名、标题） | §5.7 |
| 做远程 Webhook 接收 | §5.4 |
| 做人设、接大模型 | §5.5 |
| 写任何 UI | §6 UI 实现约定 |
| 改动 UI 或事件处理路径后自检 | §7 性能 |
| 写 Swift 代码前 | §8 代码风格 |
| 写测试 | §9 测试 |
| 准备开源、写 README | §10 开源准备 |
| 卡住了、遇到奇怪问题 | §11 已知待办与陷阱 |
