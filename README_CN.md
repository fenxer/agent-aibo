# Aibo

<img src="doc/hero.png" width="640">

[English](README.md) ｜ 简体中文

> あいぼう，エージェント走らせるぜ！

轻量的 macOS 桌面伙伴。来源于日语 Aibou（相棒）。

常驻桌面，可用气泡播报两类信息：

1. **本机 AI Agent 状态**：通过 hooks 输出 Cursor、Codex 等在本机运行时的思考 / 工具调用 / 完成信息等；
2. **远程 Webhook 通知**：如部署完成、CI 结束等（需要自己部署远程 tunnel）；

## 特色

- 原生应用，没有 XX helper 占用额外系统资源；
  - ~~体验原汁原味的 SwiftUI 卡顿~~
- 支持 [PetDex](https://petdex.dev/) V1/V2 格式资源；
- 支持本地上传单张静态图片，或以 `.zip` 形式上传 V1/V2 格式资源；
- 额外的小功能；
  - Webhook 接收记录；
  - 检测到系统播放音乐时，会飘出音符；
  - 像素风格的 sprite 图片展示优化；
  - 切割 sprite 图片以优化常驻资源；

## 更新计划  

[点此查看](https://github.com/users/fenxer/projects/1/views/2)

## Skills

- [hatch-aibo](Skills/hatch-aibo): 改造了原有的 'hatch-pet' skills 用于生成质量更可控的 sprite 图；
- [aibo-webhook](Skills/aibo-webhook): 将 webhook 消息发送到 aibo 的说明；

## 目录结构

```
App/        桌面 UI（窗口、气泡、设置）
AiboKit/    核心逻辑与测试（事件、hooks、webhook）
Hook/       aibo-hook 命令行
Skills/     给 Agent 用的 skills
Scripts/    构建与启动
```

## 系统要求

最低 macOS 26。

## 安装

从 [Releases](https://github.com/fenxer/agent-aibo/releases/latest) 下载 `Aibo-*.dmg`，打开后把 `aibo.app` 拖进 **应用程序**。不要长期放在「下载」里运行——应用内更新要求 app 在 `/Applications`。

## 贡献

**本项目不接收 Pull Request。**

欢迎提 issue 反馈问题或想法，或 fork 后在自己的仓库里修改。

Fork 后建议先自行生成一份 `AGENTS.md`，按照自己喜欢的流程开发。比如：

- 「帮我适配 Claude Code 的 hook 消息」
- 「帮我适配到 macOS 15 以下系统」
- 「帮我适配到 Linux 系统」

## 构建

```bash
# 核心逻辑测试
cd AiboKit && swift test

# 构建 app
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build

# 构建并启动
./Scripts/run.sh
```
