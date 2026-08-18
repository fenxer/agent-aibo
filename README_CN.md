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
- 更新中……

## 系统要求

最低 macOS 26。

## 贡献

**本项目不接收 Pull Request。**

欢迎提 issue 反馈问题或想法，或 fork 后在自己的仓库里修改。

Fork 后建议先自行生成一份 `AGENTS.md`，按照自己喜欢的流程开发。

## 构建

```bash
# 核心逻辑测试
cd AiboKit && swift test

# 构建 app
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build

# 构建并启动
./Scripts/run.sh
```
