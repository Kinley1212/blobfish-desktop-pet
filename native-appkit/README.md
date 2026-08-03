# 水滴鱼 2.0 原生 AppKit 版

2.0.0 把 Electron 1.4.5 的功能迁移到 Swift、AppKit 与 SwiftUI，同时继续读取同一份用户数据：

`~/Library/Application Support/BlobfishDesktopPet`

## 已实现

- 透明、无程序坞图标、跨桌面的原生 `NSPanel`；支持水平/垂直游动、低开销上下浮动、拖高后保持新高度及按角色可见边界碰撞
- 读取现有角色 SVG、语言包、捏鱼/捏草参数与 89 个饰品；原生眨眼和任务反馈动画
- 品牌化 SwiftUI 设置页，捏鱼/捏草与饰品调整提供常驻实时预览，并支持中英文界面、作息、隐私、声音、性能和开机启动
- Codex / Claude Code 安全 lease 读取、启动恢复、多任务摩天轮、状态突变立即跳转
- 无终端的一键状态插件连接；Codex 仍需在 `/hooks` 中完成一次信任确认
- 与 Electron 共用闹钟、计时器和响铃偏好；闹钟附件震动、计时牌、暂停/继续/延长
- 首次问候、工作日提醒、锁屏唤醒、电量阈值（含 3% / 2%）和 EventKit 日历
- 原生 CPU / RAM 面板，以及连续三分钟超出自选阈值后的安全退出
- 独立原生更新渠道；应用内下载、SHA-256、应用身份、临时签名校验与原子替换

## 构建与验证

```bash
cd native-appkit
make build       # Debug
make test        # 内置真实自检
make app         # Release .app + 同源资源 + ad-hoc 签名
make archive     # 架构对应的 zip
```

`Makefile` 会优先选用本机可用的 macOS 15.4 SDK，并把缓存放在 `.build/`。GitHub Actions 会重复构建、自检、Release 打包，并上传分支预览产物。

## 发布约定

原生版不读取 Electron 的 `blobfish-latest.json`，只读取 `blobfish-native-latest.json`。2.0.0 Release 只发布 Swift / AppKit 原生安装包：

- `channel: "native-appkit"`
- `BlobfishNative-<version>-macOS-arm64.zip`
- 文件大小和 `sha256:<64 hex>`

目前只支持 Apple Silicon Mac，这样可以从根本上避免原生版误装 Electron 包或错误架构。
