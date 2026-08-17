# aibo

![](doc/hero.png)

English ｜ [简体中文](README_CN.md)

> あいぼう，エージェント走らせるぜ！

Native macOS desktop companion.

Stays perched on your desktop, broadcasting two types of info via speech bubbles:

1. **Local AI Agent Status**: Real-time thinking, tool calls, and completion events from Cursor, Codex, etc. via hooks.
2. **Remote Webhook Notifications**: Deployment status, CI results, etc. (requires your own tunnel).

## Features

- Native app without heavy helper processes hogging system resources.
  - ~~Enjoy authentic SwiftUI stutters~~
- Supports static single images.
- Supports PetDex V1/V2 assets.
- Handy little extras.

## Requirements

macOS 26 or later.

## Contributing

**This project does not accept Pull Requests.**

Feel free to open an [Issue](../../issues) for feedback or ideas, or fork and hack on it in your own repository.

When forking, consider generating an `AGENTS.md` first and develop with your preferred workflow.

## Build

```bash
# Core logic tests
cd AiboKit && swift test

# Build app
xcodebuild -project aibo.xcodeproj -scheme aibo -configuration Debug build

# Build and launch
./Scripts/run.sh
```
