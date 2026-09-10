# 2.7.5 语言维护交接

## 已落实的约定

- UI 支持 `zh-CN` / `en`；台词支持水滴鱼 `zh-TW` / `en`、小草团 `zh-CN` / `en`。界面语言与台词语言是独立偏好，不自动互相覆盖。
- Settings 使用草稿即时预览 UI，点“应用”后保存并刷新运行中的菜单、传话、历史、快捷闹钟、角色互动聊天。只改界面语言不重置正在进行的角色互动聊天。
- 更换角色使用 `SpeechLanguagePolicy.preferredPack`，优先保留兼容包，其次相同语言；中文可在角色支持的简繁体之间匹配。不存在的包回到当前角色默认包，不跨角色借用聊天内容。
- 每个自动台词包都必须有同 ID 的独立互动聊天包；四个内置互动包均有 31 节点、9 个开场、3 类小游戏，小草团仅用三种草团表情。
- 原版 original 台词按项目历史约定原样保留；繁体 additions 与独立聊天统一为繁体。小游戏和后备台词使用实际台词语言，用户输入的消息不翻译。
- 静态菜单先刷新双语标题，再刷新未读数/计时状态。菜单使用缓存未读数，避免从非隔离方法直接访问 MainActor Messenger。
- 原生资源显示名使用 NativeLocalization；Windows/Electron 使用 ui-i18n，新增名称需同步回归检查。
- 有效台词包或角色改变时清空自动台词队列，不清好友消息气泡。旧存档中不兼容的包 ID 在加载时按角色匹配并同步内存配置，下次保存持久化。

## 验证与发布

- 原生：`cd native-appkit && make test`，包含角色切换/保存重开/窗口语言同步/完整目录显示名自检。
- 数据及 UI 合约：`node --test test/localization-pack-completeness.test.js test/language-switch-contract.test.js test/native-menu-localization.test.js`。
- 不把事件集合相同等同于所有运行场景已接入；新增事件需补触发路径测试。
- 不做未经批准的视觉检查。英文长文案布局仍须人工或获批后现场验收。
- 本次不混入工作树中未提交的 Windows 构建、安装器及发布流水线工作。GitHub 正式安装包继续使用 macOS 原生双架构、ad-hoc 签名，不含 Developer ID / Apple 公证。
- 发布前本地结果：100/100 原生自检、48/48 语言/资源/菜单相关 Node 测试通过；`git diff --check` 通过。无视觉验收。
