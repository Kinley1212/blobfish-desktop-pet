# 水滴魚桌寵

这是从现有 `水滴魚.app` 的 `app.asar` 恢复出的可维护源码项目。第一份基线保留原程序行为，后续功能按独立提交逐步加入。

## 开发运行

```bash
npm install
npm start
```

## 基线功能

- 透明置顶桌宠窗口
- 自动游动、转向和多显示器边界处理
- 点击反应、拖拽、甩动、惯性减速和碰撞回弹
- 原版随机闲聊与日程提醒
- 可替换的形象、动作与语言包
- 随机眨眼、稀有台词、冷却和防重复
- 可配置的吃饭、下班、半小时提醒与安静时段
- macOS 菜单栏设置、暂停和退出入口

原始 App 仅作为行为和视觉基线，不纳入本项目版本控制。

## 扩展形象

角色图形和动作已经拆为独立形象包。目录结构、标准动作和回退规则见 [`docs/character-packs.md`](docs/character-packs.md)。

语言包的原版/扩展隔离规则见 [`docs/language-packs.md`](docs/language-packs.md)，设置存储与入口见 [`docs/settings.md`](docs/settings.md)。

锁屏唤醒、电量阈值和授权日历的实现与隐私边界见 [`docs/system-integrations.md`](docs/system-integrations.md)。

Codex / Claude Code 本地任务桥接、状态动作和零对话内容策略见 [`docs/agent-integrations.md`](docs/agent-integrations.md)。
