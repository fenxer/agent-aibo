# aibo

macOS 原生桌面宠物。宠物常驻桌面，用气泡播报两类信息：

1. **本机 AI Agent 状态** — Cursor、Codex 等在本机运行时的思考 / 工具调用 / 完成等（经 hooks，模板直出）。
2. **远程 Webhook 通知** — 如部署完成、CI 结束等；

## 要求

- 仅 macOS，SwiftUI + AppKit，无第三方依赖
- 最低 macOS 26

## 构建

```bash
# 核心逻辑测试
cd AiboKit && swift test

# 构建 app
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build

# 构建并启动
./Scripts/run.sh
```

## 贡献

**本项目不接收 Pull Request。**

欢迎提 [Issue](../../issues) 反馈问题或想法，或 fork 后在自己的仓库里修改。

Fork 后动手前，建议先自行生成一份 `AGENTS.md`，再按你自己的流程开发。