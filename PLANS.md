# PLANS.md

aibo 的详细设计与执行规范。`AGENTS.md` 只列每次对话都要遵守的红线，具体怎么做看这里。

**目录**

- [1. 产品定义](#1-产品定义)
- [2. 环境与构建系统](#2-环境与构建系统)
- [3. 命令清单](#3-命令清单)
- [4. 目录结构与模块边界](#4-目录结构与模块边界)
- [5. 架构：事件如何流动](#5-架构事件如何流动)
- [6. UI 实现约定](#6-ui-实现约定)
- [7. 性能](#7-性能)
- [8. 代码风格](#8-代码风格)
- [9. 测试](#9-测试)
- [10. 开源准备](#10-开源准备)
- [11. 已知待办与陷阱](#11-已知待办与陷阱)

---

## 1. 产品定义

aibo 是一个 macOS 原生桌面宠物。它在桌面上显示一只常驻的宠物，并通过气泡实时播报两类信息：

1. **本机 AI Agent 的运行状态** —— Cursor、Codex 等工具在本机运行时的思考 / 工具调用 / 回复完成等状态。
2. **远程 Webhook 通知** —— Cloudflare 部署完成、GitHub Actions 结束等。这类通知会先经过一个可配置人设（persona）的大模型改写，再由宠物用"自己的口吻"说出来。

这两件事**走的是两套完全不同的机制**，不要试图用一套通道实现，原因见 §5.1。

---

## 2. 环境与构建系统

### 2.1 已验证的环境事实（2026-07）

- Swift 6.4（`swift-driver` 1.168.5），默认 target `arm64-apple-macosx27.0.0`
- SDK：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` → **macOS 27.0**
- 已实测可正常编译：`NSPanel(.borderless/.nonactivatingPanel)`、`NSHostingView`、`.glassEffect(_:in:)`、`Network.framework`
- `FoundationModels.framework` 存在于 SDK 中，端侧模型可用
- 未安装：`swift-format`、`swiftlint`、`gh`
- **Xcode 正在安装中。在它就绪之前 `xcodebuild` 不可用**，此期间只能用 `swiftc` 或在 `AiboKit/` 下用 SwiftPM 验证核心逻辑

### 2.2 Xcode 项目 + 本地 Swift Package

主构建方式是 `aibo.xcodeproj`。但**核心逻辑不放在 Xcode target 里**，而是放在仓库内的本地 Swift Package `AiboKit/`，由 Xcode 项目以本地依赖形式引用。

改动构建结构前请先理解这样划分的三个理由：

- **模块边界由编译器强制。** `AiboCore` 不声明对 AppKit 的依赖，所以一旦有人写了 `import SwiftUI`，编译直接失败，而不是靠自觉遵守约定。
- **核心逻辑的测试不依赖 Xcode。** 在 `AiboKit/` 下 `swift test` 就能跑完状态机和解析逻辑的全部测试，CI 也不需要完整 Xcode 环境。
- **缩小 `project.pbxproj` 的冲突面。** 这个文件在多人协作时几乎必然产生无法人工 review 的冲突。Xcode 项目里只保留 app 和 hook 两个 target，日常加删源文件都发生在 Package 侧，不触碰 `.pbxproj`。

`.app` 的组装、签名、Info.plist、资源打包全部交给 Xcode，不手工写 bundle 脚本。

> 如果 `.pbxproj` 冲突仍然频繁，可以考虑引入 XcodeGen（用文本化的 `project.yml` 生成项目，`.pbxproj` 不入库）。**这属于构建结构调整，实施前必须先征求用户同意。**

### 2.3 部署目标

macOS 26 (Tahoe) 是最低支持版本，用 SDK 27 编译。两处都要设，且必须保持一致：`AiboKit/Package.swift` 里 `platforms: [.macOS(.v26)]`，Xcode 项目里 `MACOSX_DEPLOYMENT_TARGET = 26.0`。

可以自由使用 macOS 26 引入的 API（Liquid Glass、`glassEffect` 等），**不要写任何 `if #available` 向下兼容分支**。

---

## 3. 命令清单

```bash
# 构建整个 app（debug）
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build

# 构建（release，发版用）
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Release build

# 跑全部测试
xcodebuild -project aibo.xcodeproj -scheme aibo test

# 只跑核心逻辑测试（秒级，日常改 AiboCore/AiboIngest 时用这个）
cd AiboKit && swift test

# 只做快速语法检查，不打包
cd AiboKit && swift build

# 构建并启动 app（开发主循环）
./Scripts/run.sh

# 把 hook 注册到 ~/.cursor/hooks.json 和 ~/.codex/hooks.json
./Scripts/install-hooks.sh
```

改动只涉及 `AiboKit/` 时，**优先用 `swift test` 而不是 `xcodebuild test`**——前者是秒级，后者要走完整的 app 打包流程。

两个已知的环境问题，遇到时不要误判成代码错误：

- SwiftPM 在受限沙箱下会因为 `~/Library/Caches/org.swift.swiftpm` 不可写而报 `Could not initialize build system: Unknown error parsing property list`。用 `--cache-path` / `--scratch-path` 指到仓库内目录，或请求提权后重试。
- GUI app 不能用 `swift run` 启动，它需要真正的 bundle 才能拿到正确的 activation policy 和 Info.plist。**始终通过 `./Scripts/run.sh` 或 Xcode 启动。**

---

## 4. 目录结构与模块边界

```
aibo/
├── AGENTS.md                   # 红线摘要
├── PLANS.md                    # 本文件
├── README.md
├── aibo.xcodeproj              # 只有两个 target：aibo（app）、aibo-hook（CLI）
├── AiboKit/                    # 本地 Swift Package，承载全部核心逻辑
│   ├── Package.swift
│   ├── Sources/
│   │   ├── AiboCore/           # 纯领域逻辑：事件模型、状态机、配置、人设。不 import AppKit/SwiftUI
│   │   ├── AiboIngest/         # 事件摄入：Unix socket 服务端、本地 HTTP 服务端、各 agent 适配器
│   │   └── AiboLLM/            # 模型 provider 抽象与实现
│   └── Tests/
│       ├── AiboCoreTests/
│       ├── AiboIngestTests/
│       └── Fixtures/           # 各 agent 的真实 hook payload 样本
├── App/                        # app target 源码：入口、NSPanel 窗口、SwiftUI 视图、菜单栏、设置
│   ├── Info.plist
│   └── aibo.entitlements
├── Hook/                       # aibo-hook target 源码，单文件即可
├── Resources/
│   └── kirby.png               # 占位素材，见 §11
└── Scripts/
    ├── run.sh
    └── install-hooks.sh
```

新增源文件时优先放进 `AiboKit/`，那里不需要改 `.pbxproj`。只有确实依赖 AppKit/SwiftUI 的代码才放 `App/`。

### 模块依赖方向

```
App (Xcode target) ──→ AiboIngest ──→ AiboCore
     └───────────────→ AiboLLM ─────────┘
aibo-hook (Xcode target) ──→ (无依赖，只用 Foundation)
```

**这个方向是单向的，不允许反向依赖。** 特别是：`AiboCore` 绝不能 `import AppKit` 或 `import SwiftUI`——它必须能在没有图形环境的测试进程里跑，这也是把它放在 Package 里的原因。

`aibo-hook` 会被打包进 app bundle 的 `Contents/Helpers/`，`install-hooks.sh` 注册的就是这个内嵌二进制的绝对路径。**它不链接 AiboKit**，理由见 §5.3。

---

## 5. 架构：事件如何流动

```
Cursor hooks ─┐
Codex hooks  ─┼─→ aibo-hook ──→ Unix Domain Socket ──┐
其他 agent   ─┘   (CLI, <10ms)                        │
                                                      ├─→ EventBus ─→ PetStateMachine ─→ SwiftUI 气泡
远程 Webhook ─────→ NWListener (HTTP, 默认 loopback) ─┘         │
                                                                 └─→ Persona + LLM ─→ 文案
```

### 5.1 本机 Agent 状态：用 hooks，不是 webhook

**这是本项目最容易搞错的一点，务必读完。**

Cursor 的 Webhook 是**云端 Cloud Agent** 的机制：由 Cursor 服务器 POST 到公网 URL，只有 `statusChange` 一个事件，且只在 `FINISHED` / `ERROR` 时触发。它拿不到"正在思考""正在调用工具"，而且 localhost 根本收不到。**用它来做本机状态显示是行不通的。**

本机 agent 的实时状态只能通过 **hooks** 拿到：

| 工具 | 配置文件 | 传输方式 | 关键事件 |
| --- | --- | --- | --- |
| Cursor | `~/.cursor/hooks.json`（user 级）或 `<项目>/.cursor/hooks.json` | spawn 进程，stdin 收 JSON，stdout 回 JSON | `beforeSubmitPrompt`、`preToolUse`、`postToolUse`、`postToolUseFailure`、`afterAgentThought`、`afterAgentResponse`、`stop`、`sessionStart`、`sessionEnd` |
| Codex | `~/.codex/hooks.json` 或 `config.toml` 的 `[hooks]` | 同上，事件名首字母大写 | `UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`SubagentStart`、`SubagentStop`、`Stop`、`SessionStart` |

实现时会用到的补充事实：

- Cursor 的 hook 输入 JSON 一定包含 `conversation_id`、`generation_id`、`model`、`hook_event_name`、`workspace_roots`、`transcript_path`。用 `conversation_id` 做会话 key，`workspace_roots` 做项目区分。
- Cursor 的 `matcher` 字段可以按工具名过滤（`Shell`、`Read`、`Write`、`Grep`、`Task`、`MCP:<name>`），**用它收窄触发范围，减少无谓的进程 spawn**。
- Cursor 默认 **fail-open**：hook 崩溃、超时、返回非法 JSON 都会放行。我们只做观察，因此**绝不要设 `failClosed: true`**。
- Codex 的顶层 `notify` 配置项只支持 `agent-turn-complete`，且官方已表示将被 hooks 取代。**不要用 `notify`，用 hooks。**
- Codex 的项目级 `.codex/config.toml` 会忽略 `notify` 等 machine-local 键，安装脚本必须写用户级配置。

### 5.2 状态机：为什么需要推断

**没有任何一家提供"开始思考"事件。** Cursor 的 `afterAgentThought` / `afterAgentResponse` 都是事后触发的。所以宠物状态必须靠推断。

**每家 agent 一张独立的映射表，不要合并成一张。** 同名事件在不同工具里语义可能相反，见下面的 `SubagentStop`。映射函数返回可选值，**未知或无关的事件返回 `nil` 表示"不改变状态"**，不要当作错误，也不要回落到某个默认状态。

Cursor：

| 事件 | 状态 |
| --- | --- |
| `sessionStart` | `.registered` → 延时回落 `.idle`（与 `.done` 同延时） |
| `beforeSubmitPrompt` | `.thinking` |
| `preToolUse` / `beforeShellExecution` | `.usingTool(name)` |
| `postToolUse` | `.thinking` |
| `afterAgentResponse` | `.responding` |
| `stop`（`status: completed`） | `.done` → 延时回落 `.idle` |
| `stop`（`aborted` / `error`） | `.interrupted` / `.failed` |
| `sessionEnd` | 立即移除该会话，不是 `.done` |

Codex：

| 事件 | 状态 |
| --- | --- |
| `SessionStart` | `.registered` → 延时回落 `.idle`（与 `.done` 同延时） |
| `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `SubagentStart` | `.thinking` / `.usingTool(name)` |
| `PermissionRequest` | **`.waiting`** |
| `Stop` / `SubagentStop` | `.done` |

#### `.waiting` 是最重要的状态

`.waiting` 表示 **agent 停下来在等用户回答**（Codex 的 `PermissionRequest`，Claude Code 的 `Notification`）。产品上它比 `.thinking` 重要得多：思考中用户不用管，等回答才需要立刻看一眼。宠物在 `.waiting` 时应当有明显区别于其他状态的表现。

**Cursor 目前没有对应事件**，所以 Cursor 会话拿不到 `.waiting`。这是工具能力差异，不是 bug。设置界面里要如实标注哪些 agent 支持这个状态，不要让用户以为是没配好。

#### 必须避开的陷阱

- **Claude Code 的 `SubagentStop` 必须忽略（返回 `nil`）。** 它在 `Task()` 子 agent 结束时触发，此时主会话还在跑。当成 `.done` 会造成 done → working 的状态闪烁。
- **但 Codex 的 `SubagentStop` 要映射成 `.done`。** 这正是"每家一张表"的原因。
- **`sessionEnd` 不等于 `.done`。** 前者是用户关掉了会话，该会话应当立即从列表移除；后者是这一轮跑完了，会话还在。

#### 看门狗

状态机必须有 **看门狗超时**：超过 N 秒（默认 120s，可配置）没有收到该会话的任何事件，强制回落 `.idle`。否则 agent 崩溃或用户强杀进程时，宠物会永远卡在"思考中"。

状态机实现在 `AiboCore`，必须是纯函数式的 `(State, Event) -> State`，并配有单元测试。**新增事件类型时必须同时补测试。**

### 5.3 aibo-hook：性能最敏感的部分

`preToolUse` 这类事件在一次 agent 会话里可能触发几十上百次，**每次都是一次完整的进程冷启动**。因此：

- `aibo-hook` 只 `import Foundation`，不碰 AppKit/SwiftUI/Network
- 唯一职责：读 stdin → 连 Unix socket → 原样写入（连不上就落盘排队）→ `exit(0)`
- **禁止**在 hook 里做：网络请求、JSON 深度解析、读写配置文件、调用 LLM
- 无论发生什么都必须**快速正常退出**，绝不能阻塞或拖慢用户的 agent
- 解析归一化在 app 侧的 `AiboIngest` 做，不在 hook 侧做

Unix Domain Socket 路径：`~/Library/Application Support/aibo/aibo.sock`，传 **NDJSON**（一行一个事件，`\n` 结尾）。选 UDS 而不是 HTTP 或文件监听，是因为它延迟最低、没有端口占用问题、且天然受文件权限保护。

#### 三个必须处理的 socket 细节

- **`SO_NOSIGPIPE`。** app 中途退出后，hook 往已关闭的 socket 写会收到 `SIGPIPE` 而被直接杀掉。连接建立后立刻 `setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, ...)`。这个错误发生在用户的 agent 会话里，体验很差。
- **循环写直到写完。** 一次 `write()` 可能只写入部分数据，必须按返回的字节数推进 offset continue 写，直到全部写完或返回 `<= 0`。
- **连不上时落盘排队，不要丢事件。** app 没运行时把这一行 JSON 写到 `~/Library/Application Support/aibo/queue/<timestamp>-<uuid>.json`，app 启动时按文件名顺序读取、投递、删除。**队列必须有上限**（建议按文件数和总大小双重限制，超出时丢弃最旧的），否则用户长期不开 app 会无限堆积。

#### 服务端 accept 循环的错误分类

accept 出错时按 errno 分三类处理，**默认必须是退避而不是立即重试**：

| errno | 处理 |
| --- | --- |
| `EINTR`、`ECONNABORTED` | 立即重试（正常的瞬时错误） |
| `EBADF`、`EINVAL`、`ENOTSOCK` | 停止循环（监听 socket 已失效，重试只会再失败） |
| 其他（默认） | 退避 ~50ms 再重试 |

默认分支如果写成立即重试，一个持续出现的未知错误会让循环把一个 CPU 核心打满。

### 5.4 远程 Webhook

用 `Network.framework` 的 `NWListener` 起一个极简 HTTP 服务端。**不要引入 Vapor / Swifter / Hummingbird**——我们只需要处理 POST + 读 body，几百行就够，引入 Web 框架会让常驻内存翻倍。

安全默认值，不要擅自放宽：

- 默认只绑 `127.0.0.1`。绑 `0.0.0.0` 必须由用户在设置里显式开启，并给出明确风险提示。
- 每个 webhook 端点有独立的共享密钥，校验 HMAC-SHA256 签名。Cursor 云端 webhook 的格式是 `X-Webhook-Signature: sha256=<hex>`，**必须用解析前的原始 body 计算**。
- 用 `X-Webhook-ID` 做幂等去重，因为发送方会重试。
- 尽快返回 2xx，LLM 改写等耗时工作必须异步做，不能阻塞 HTTP 响应。

**要如实告诉用户的边界**：绑在 loopback 上的服务收不到公网请求。GitHub / Cloudflare 的 webhook 要送达本机，用户必须自己搭 Cloudflare Tunnel、tailscale funnel 或类似的内网穿透。这个 app **不内置**穿透功能，README 里给出配置指引即可。

### 5.5 人设与模型

`AiboLLM` 定义一个 provider 协议，实现按以下优先级：

1. **Apple FoundationModels（默认）** —— 端侧、免费、离线、隐私，且没有额外的常驻内存开销。契合本项目的性能目标，应作为开箱即用的默认值。
2. **OpenAI 兼容 HTTP API** —— 用 `URLSession` 直接发请求，不要引入 SDK。用户填 base URL + model + key 即可对接 OpenAI、Ollama、OpenRouter 等。

其他规则：

- API key 存 **Keychain**，绝不写进 `UserDefaults` 或明文配置文件。
- persona 是一段用户可编辑的系统提示词，加上少量结构化偏好（说话长度、语气、emoji 用不用）。
- **只有远程 Webhook 通知才走 LLM 改写。** 本机 agent 状态是高频事件，必须走本地模板直出，绝不能每次状态变化都调模型。
- LLM 调用必须可失败：超时、报错、没配置时，一律回落到模板文案，宠物照常说话。

### 5.6 hook 的安装与卸载

我们要读写的是**用户自己的配置文件**（`~/.cursor/hooks.json`、`~/.codex/hooks.json`）。把用户的配置搞坏是这个 app 能造成的最严重的伤害，下面几条没有商量余地。

**纯变换与文件 IO 分离。** 安装、卸载、检测是否已安装，三者都实现成纯字典变换 `([String: Any], ...) -> [String: Any]`，由一层薄薄的 `*OnDisk` 包装负责读写。纯变换部分必须有完整单测。

**靠命令字符串识别自己的条目。** 判断一个 hook 条目是不是我们写的，用它的 `command` 是否指向 `aibo-hook`。由此得到两个性质：

- **安装幂等**：先过滤掉所有属于我们的旧条目，再追加新条目。重复安装不会产生重复项，升级换路径也能自动清理旧路径。
- **绝不动别人的 hook**：用户自己配的、其他工具配的条目原样保留。卸载时同理，只删自己的；某个事件下删空了就把这个事件键一起删掉，别留空数组。

**读不懂就拒绝写。** 配置文件存在但解析不出 JSON 对象时，**抛错并中止**，不要当成空配置继续。否则一次写入就会把用户原有的全部配置替换成只剩我们的 hook。文件不存在或为空才视为空配置。

**原子写入。** 用 `.atomic` 选项，避免写到一半崩溃留下一个截断的、彻底损坏的配置文件。

**各家的 JSON 形状不同，需要一层 style 抽象。** 至少这两种：

```jsonc
// Cursor：扁平
{ "version": 1, "hooks": { "preToolUse": [ { "type": "command", "command": "..." } ] } }

// Codex / Claude Code：嵌套一层
{ "hooks": { "PreToolUse": [ { "hooks": [ { "type": "command", "command": "..." } ] } ] } }
```

新增一家 agent 时，如果它的形状能归入已有 style 就复用，不能就加一个 style 分支，**不要在核心逻辑里散落 if-else**。

### 5.7 用 transcript 补足 hook 的信息盲区

hook payload 里的 `transcript_path` 指向该会话的完整 JSONL 记录。有些信息 hook 给不了，只能顺着这个路径去读：

- **当前实际在用的模型。** hook 只在 `sessionStart` 报一次 `model`，用户中途切换模型后 payload 就不准了。要显示准确的模型名，得从 transcript 里取最近一条 assistant 消息的模型标识。
- **会话标题**，用于区分多个并发会话属于哪个任务。
- **最近一条 assistant 文本**，可用于判断 agent 是不是在向用户提问。

这属于**可选增强，不是核心链路**。实现时必须守住两条性能底线：

- **增量读，不要重读整个文件。** 按路径记录已消费的字节 offset，每次只扫新增部分；只需要最近几条时从文件尾部反向读。
- **必须节流。** 读 transcript 是昂贵操作，而 hook 事件是高频的。用一个「按会话 key 限流，每 N 秒最多执行一次」的节流器把它压下来，不要每个事件都触发。节流器把当前时间作为参数传入而不是内部读时钟，这样可以被确定性地测试。

> §5.2 的陷阱、§5.3 的 socket 细节、§5.6 和 §5.7 的做法，部分参考了开源项目 [ntd4996/agentpet](https://github.com/ntd4996/agentpet) 的实践。**借鉴的是设计经验，不要直接复制它的代码。**

---

## 6. UI 实现约定

### 6.1 宠物窗口必须是 NSPanel

纯 SwiftUI 的 `Window` scene 做不到桌宠需要的行为。宠物窗口用 `NSPanel` 子类 + `NSHostingView` 承载 SwiftUI 内容，配置如下：

```swift
styleMask = [.borderless, .nonactivatingPanel]
isOpaque = false
backgroundColor = .clear
hasShadow = false
level = .floating
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
isReleasedWhenClosed = false
```

- `.nonactivatingPanel` 是关键：点击宠物不会把 aibo 切到前台，用户不会被打断。
- `NSApp.setActivationPolicy(.accessory)` + Info.plist 里 `LSUIElement = true`，不占 Dock 图标。
- 透明区域必须点击穿透，宠物本体和气泡可点击。用自定义 content view 的 `hitTest`（对宠物图做一次 alpha mask 缓存）实现，不要简单粗暴地全局 `ignoresMouseEvents`。**不要**再覆写 `NSWindow.hitTest`——macOS 27 的 Swift AppKit 叠层已不再暴露该方法。
- 多显示器：监听 `NSApplication.didChangeScreenParametersNotification`，屏幕变化时把宠物拉回可见区域。

### 6.2 其余 UI 用纯 SwiftUI

菜单栏用 `MenuBarExtra`，设置窗口用 `Settings` scene。用 macOS 原生控件（`Form`、`LabeledContent`、`Toggle`、`Picker`）。

用户没有给出具体设计时，**默认用系统原生外观**：系统材质、系统字体、系统间距、系统配色。不要自己发明视觉风格，不要硬编码颜色值——用 `Color.primary`、`.secondary`、语义化的系统颜色，这样自动适配深浅色模式。

气泡用 `.glassEffect(.regular, in:)`。多个玻璃元素必须包在 `GlassEffectContainer` 里，因为玻璃无法采样玻璃，分开写会导致渲染异常且性能更差。

---

## 7. 性能

低资源占用是这个 app 的核心卖点，但它靠的是**架构上不做错事**，不是靠盯着数字调优。下面几条是硬要求：

- **全事件驱动，零轮询。** 不要写任何 `Timer.scheduledTimer` 做状态检查。
- **空闲时不渲染。** `TimelineView`、`PhaseAnimator` 这类持续动画只在宠物处于活跃状态时启用，`.idle` 时必须停掉。一个 60fps 常驻动画足以让空闲 CPU 从 0% 涨到百分之几。
- **hook 进程里不做重活。** 见 §5.3。
- **高频事件路径上的昂贵工作要节流。** agent 密集活动时 hook 事件是持续高频的，任何跟着每个事件跑的重活（读 transcript、重算布局、写磁盘）都必须按会话 key 限流。见 §5.7。
- **任何重试循环都要有退避。** 没有退避的重试在持续错误下会把一个核心打满。见 §5.3。
- 宠物精灵图预解码一次后缓存，不要每帧从 PNG 解。
- 气泡消失后销毁其视图层级，不要留着隐藏视图。
- 不用 `NSVisualEffectView`，用 SwiftUI 的 `.glassEffect` / 材质，系统实现更省。

引入任何常驻后台工作（定时器、轮询、监听器）前，先向用户确认。

### 参考观测值

**这些不是验收标准，也还没有实测基线**，只是"偏离很多说明哪里做错了"的信号。等 app 真能跑起来后按实测值修正。

| 观测项 | 大致预期 |
| --- | --- |
| 空闲时 CPU | 应稳定在 0.0%。出现持续的非零读数，说明有东西在轮询，或者动画没在 `.idle` 时停掉 |
| 常驻内存 | 几十 MB 量级。SwiftUI 框架本身就有不小的底噪，**不要为了压这个数字牺牲代码清晰度** |
| `aibo-hook` 单次执行 | 个位数毫秒。明显更慢说明 hook 里做了不该做的事 |
| 事件到气泡更新 | 人感觉不到延迟即可 |

---

## 8. 代码风格

- Swift 6 严格并发。UI 相关类型标 `@MainActor`，跨 actor 传递的类型必须 `Sendable`。不要用 `@unchecked Sendable` 绕过编译器警告——那通常说明设计有问题。
- 优先 `struct` 和 `enum`，需要引用语义时才用 `class`（并标 `final`）。
- 事件、状态一律用 `enum` 带关联值建模，不要用 `String` + 魔法值。
- 异步用 `async/await` 和 `AsyncStream`，不要用 completion handler，不要用 `DispatchQueue` 手动管线程。
- 错误用具体的 `enum: Error`，不要 `NSError` 或字符串错误。
- 命名用完整单词（`conversationIdentifier` 而不是 `convID`）。
- **注释只写代码本身表达不了的约束和取舍**，比如"Cursor 默认 fail-open，所以这里不能抛错"。不要写"// 遍历数组"这种复述代码的注释。
- **按职责拆文件，不按行数。** 一个 SwiftUI 视图文件到五六百行、甚至更长都可能是正常的；但如果一个文件同时在管窗口生命周期、状态订阅和布局计算，两百行就该拆。判断标准是"它是不是在做不止一件事"，不是行数。
- 用户手工调整过的样式数值（间距、尺寸、动画时长）**不要擅自改回去**，除非它确实导致了功能问题。

---

## 9. 测试

- `AiboCore` 的状态机和事件归一化**必须有单元测试**，这是整个 app 逻辑正确性的核心。
- **hook 安装器的纯字典变换必须有测试**，至少覆盖：重复安装幂等、不误删用户已有的其他 hook、卸载后能干净还原、读到损坏 JSON 时抛错而不是覆写。这部分出错会破坏用户的配置文件，测试优先级等同核心逻辑。
- `AiboIngest` 的 HTTP 解析、HMAC 校验、幂等去重必须有测试。
- UI 不强制写自动化测试，改动后手动验证即可。
- 用 Swift Testing（`import Testing`、`@Test`），不用 XCTest。
- 每家 agent 的 hook payload 样本存在 `AiboKit/Tests/Fixtures/` 下，作为归一化逻辑的回归基准。新增 agent 支持时同步补 fixture。样本要从真实运行中抓取，不要手写臆造。

---

## 10. 开源准备

- 所有面向用户的字符串走本地化（`String(localized:)`），至少准备 `en` 和 `zh-Hans`。
- README 要包含：截图、系统要求、安装方式、hook 配置说明、webhook 配置说明（含内网穿透指引）、隐私声明。
- **隐私声明必须写清楚**：什么数据留在本机、什么数据会发给第三方 LLM、用户如何完全关掉网络出站。这是一个能读到用户全部 agent 会话内容的 app，隐私边界要说透。
- 提交信息用 Conventional Commits（`feat:`、`fix:`、`perf:`、`docs:`、`refactor:`）。
- 新增支持一个 agent 时，应当只需要写一个适配器 + 一份 fixture，不需要改动核心。如果发现要改核心，说明抽象漏了，先重构。
- 许可证待定，用户确认前不要自行添加 LICENSE 文件。

---

## 11. 已知待办与陷阱

- **`Resources/kirby.png` 是占位素材，Kirby 是任天堂的注册商标。开源发布前必须替换成原创或授权素材。** 不要在 README、截图、应用图标、仓库名里使用这个形象。代码里不要硬编码 `kirby` 这个名字，用 `defaultPet` 之类的中性命名，方便替换。
- Xcode 27 beta（`Xcode-beta.app`）已可用；命令行请先 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`，否则会落到 Command Line Tools。
- 未配置代码签名和公证。分发前需要 Developer ID 签名 + notarization，否则用户下载后会被 Gatekeeper 拦截。
- Cursor 的 user 级 hooks 在 Cloud Agent 环境里不生效（云端 VM 访问不到本地 home），这对桌宠场景无影响，但不要在文档里承诺支持 Cloud Agent。
- Cursor 文档没有给出 hook 的默认超时秒数，只写了 "platform default"。不要假设具体数值，保持 hook 足够快即可。
- 目前无法区分"agent 正在流式输出回复"和"agent 已输出完"，因为只有事后事件。不要向用户承诺打字机式的实时回复展示。
- **token 用量统计：想做，但设计待定。字段已实测（2026-07）。** hook payload 里**没有任何 token 信息**，只能顺着 `transcript_path` 读会话记录。三家能力差距很大：
  - **Codex**（`~/.codex/sessions/**/*.jsonl`）：`payload.info.total_token_usage.*` 是**会话累计值**，取最后一条即可，无需自行累加；`payload.info.last_token_usage.*` 是单轮值。字段含 `input_tokens`、`output_tokens`、`cached_input_tokens`、`reasoning_output_tokens`、`total_tokens`，另有 `payload.time_to_first_token_ms`。
  - **Claude Code**（`~/.claude/projects/**/*.jsonl`）：`message.usage.*`，含 `input_tokens`、`output_tokens`、`cache_creation_input_tokens`、`cache_read_input_tokens`。每条 assistant 消息一份，**需要自行累加**。
  - **Cursor**（`~/.cursor/projects/**/*.jsonl`）：**没有 token，也没有 model**。全部字段只有 `role`、`message.content[].{type,text,name,input}`、`status`、`type`。`~/.cursor/ai-tracking/ai-code-tracking.db` 是未文档化的内部 SQLite（看命名是追踪 AI 生成代码，不是计费），**不要依赖它**。

  待定：存储粒度（每会话一条 / 按天聚合）与存储格式（倾向 append-only JSONL，数据量小不必上 SQLite）。已确定的约束：**只在 `stop` 事件时读一次 usage**，不要跟着每个 hook 事件读（见 §5.7）；Codex 的 `cached_input_tokens` 与 Claude 的 `cache_read_input_tokens` 语义相同，需归一化；UI 必须如实标注 Cursor 不支持，否则用户会以为是统计漏了；**这会让 app 从"只读 hook 事件"扩大为"读取完整对话记录"，必须做成可关闭开关并相应改写 §10 的隐私声明**；先不做成本折算，价格表需要跟着模型持续维护，是长期负担。
- **双向审批通道：明确不做**（2026-07 决定）。指的是让 hook 阻塞等待 app 回传 allow/deny，从而在气泡上直接批准工具调用。不做的原因是 Codex 的 approval policy 加沙箱、Cursor 的 auto-run 已经让 agent 自行判断大部分批准，人工介入是低频路径，不值得为它改架构。技术接口是存在的（Cursor 的 `beforeShellExecution` / `beforeMCPExecution` 支持返回 `permission: allow/deny/ask`，Codex 有 `PermissionRequest` 事件），将来想做可行，但需要把 `aibo-hook` 从"写完立刻退出"改成"阻塞等待回复"，属于进程模型变更。**在用户明确提出前不要实现，也不要为它预留抽象或接口。**
