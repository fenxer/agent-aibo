# AGENTS_LEARNED.md

由 `continual-learning` 维护的学习记忆（用户偏好与稳定工作区事实）。
**只更新本文件**；不要往 [`AGENTS.md`](./AGENTS.md) 追加 `## Learned …` 小节。

## Learned User Preferences

- 菜单栏入口图标用 SF Symbol `bird.fill`
- 设置窗口用系统设置风格的侧边栏分类布局；不要在工具栏加关闭/折叠侧栏控件
- 状态气泡文案始终左对齐；气泡在宠物左/右侧时，布局锚点贴向宠物一侧（非居中锚点）
- 气泡文案或尺寸变化时，宠物在屏幕上的位置必须保持稳定
- 状态气泡 Liquid Glass 优先用更透的 `.clear`（相对 `.regular`）
- 本地开发/调试功能放在设置的「开发」页，并用 `#if DEBUG` 编译期隔离（例如任意消息气泡预览）
- 代码拆分不必按约 300 行硬切；单文件约 500–800 行可接受
- 希望能轻量记录 agent 相关 token/用量（含模型与时间戳）便于统计，不要求极细粒度

## Learned Workspace Facts

- 状态气泡为自定义 `PopoverBubbleShape` + SwiftUI `.glassEffect`；在透明浮动 `NSPanel` 上，glass 对桌面壁纸的明暗自适应不稳定，气泡文字颜色主要跟随 App/系统外观，不能指望随壁纸自动在黑/白间可靠切换
