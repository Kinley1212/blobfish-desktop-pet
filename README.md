# 水滴鱼2.3

这是从现有 `水滴魚.app` 的 `app.asar` 恢复出的可维护源码项目。第一份基线保留原程序行为，后续功能按独立提交逐步加入。

## 开发运行

需要 Node.js 22.12 或更新版本。

```bash
npm install
npm start
```

## macOS 打包

```bash
npm run package:mac:arm64
npm run package:mac:x64
```

两个命令会分别编译同架构的 EventKit 日历助手和任务状态发送器、生成 App、做 ad-hoc
本地签名、检查主程序与两个原生助手的架构，并把交付包写入 `release/`。也可以运行
`npm run package:mac` 顺序生成两种架构。

ad-hoc 签名适合本机验收和开发者之间传递；面向普通用户分发时，仍需使用
Apple Developer ID 证书签名并完成 notarization。主 App 不声明摄像头、
麦克风、蓝牙或任意网络加载权限；日历用途声明只存在于独立助手中，且日历
功能默认关闭。

## 基线功能

- 透明置顶桌宠窗口
- 自动游动、转向和多显示器边界处理
- 点击反应、拖拽、甩动、惯性减速和碰撞回弹
- 原版随机闲聊与日程提醒
- 可替换的形象、动作与语言包
- 随机眨眼、稀有台词、冷却和防重复
- 可配置的吃饭、下班、半小时提醒与安静时段
- 工作日早晨和休息日白天的每日首次启动问候，可分别设置时段和开关
- 可配置鱼本体大小、速度和无任务时是否继续游动
- 右键鱼本体或点击菜单栏 🐟 打开设置、暂停和退出
- 可选登录后自动启动，平时不占用程序坞
- 设置页检测并一键连接 Codex / Claude Code（Claude 首次连接会显示 Terminal 过程）
- 设置按角色与动作、问候与作息、台词、连接与隐私重新分区，并在最小窗口保持可用
- 任务 Hook 使用随 App 打包的原生发送器，收件人的电脑不需要另装 Node.js

原始 App 仅作为行为和视觉基线，不纳入本项目版本控制。

## 扩展形象

角色图形和动作已经拆为独立形象包。目录结构、标准动作和回退规则见 [`docs/character-packs.md`](docs/character-packs.md)。

语言包的原版/扩展隔离规则见 [`docs/language-packs.md`](docs/language-packs.md)，设置存储与入口见 [`docs/settings.md`](docs/settings.md)。

锁屏唤醒、电量阈值和授权日历的实现与隐私边界见 [`docs/system-integrations.md`](docs/system-integrations.md)。

Codex / Claude Code 本地任务桥接、状态动作和零对话内容策略见 [`docs/agent-integrations.md`](docs/agent-integrations.md)。
