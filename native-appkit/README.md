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
make build
make test
make run
```

`Makefile` 会在当前开发机器上选择可用的 macOS 15.4 SDK，并把模块缓存限制在项目的 `.build/` 内；其他机器会使用 `xcrun` 返回的默认 SDK。GitHub Actions 会重复执行构建和自检。`--self-test` 不依赖缺失的 XCTest 模块，但会执行真实文件系统安全检查。

## 目前没有做

- 设置界面、语言包、闹钟、日历、自动更新
- Electron 版完整的角色包、捏鱼、饰品与对话系统
- `.app` 打包、签名和性能基准

这些功能暂时不移植，避免在验证原生窗口与任务链路之前复制整套产品。下一阶段应先在可用工具链上测量空闲/任务状态的 RSS 与 CPU，再决定是否继续迁移。
