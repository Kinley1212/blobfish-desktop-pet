# 水滴鱼原生 AppKit 试验版

这是与 Electron 正式版并行的技术原型，不会替换 `main` 上已经发布的应用。目标是先验证三件事：原生透明桌宠窗口、低开销动画，以及不经过终端读取现有 Codex / Claude Code 任务状态。

## 当前实现

- AppKit 透明、无程序坞图标、跨桌面的浮动 `NSPanel`
- Core Graphics / `NSBezierPath` 直接绘制的水滴鱼和眨眼
- 有任务时才启动 30 FPS 水平移动；等待确认、完成或空闲时停止移动
- 任务气泡显示运行、等待、完成、失败和多个任务数量
- 只读现有 `~/Library/Application Support/BlobfishDesktopPet/agent-task-leases`
- 菜单栏提供暂停/继续、找回角色和退出
- lease 文件名、数量、体积、权限、所有者、时间、字段和符号链接均有边界校验

## 运行

需要一套版本互相匹配的 Xcode 或 Command Line Tools：

```bash
cd native-appkit
swift test
swift run BlobfishNative
```

当前开发机器的 Command Line Tools 存在系统级版本不匹配：Swift 编译器为 6.3.3，而 SDK 由 6.3.2 生成，因此 `swift build` 在读取 SDK 时失败，尚未进入本项目源码的类型检查。安装匹配版本的 Xcode / Command Line Tools 后，需要重新执行上面的 `swift test` 和 `swift run` 才能把原型视为构建验证通过。

## 目前没有做

- 设置界面、语言包、闹钟、日历、自动更新
- Electron 版完整的角色包、捏鱼、饰品与对话系统
- `.app` 打包、签名和性能基准

这些功能暂时不移植，避免在验证原生窗口与任务链路之前复制整套产品。下一阶段应先在可用工具链上测量空闲/任务状态的 RSS 与 CPU，再决定是否继续迁移。
