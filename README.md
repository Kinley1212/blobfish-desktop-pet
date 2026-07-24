<div align="center">

<img src="src/packs/characters/blobfish-wotou/art/character.svg" alt="水滴鱼" width="180">

# 水滴鱼 · Blobfish Desktop Pet

一只住在 macOS 桌面上的水滴鱼。会游泳、会碎碎念、会提醒你下班，还能自己捏形状、换表情、戴帽子。<br>
A blobfish that lives on your macOS desktop — it swims, mutters, reminds you to log off, and lets you reshape its face and dress it up.

**[中文](#中文) · [English](#english)**

![platform](https://img.shields.io/badge/platform-macOS-1f2328?style=flat-square)
![electron](https://img.shields.io/badge/Electron-43-47848F?style=flat-square)
![node](https://img.shields.io/badge/Node.js-%E2%89%A522.12-5FA04E?style=flat-square)
![version](https://img.shields.io/badge/version-1.1.2-c87d95?style=flat-square)

</div>

---

## 中文

### 这是什么

一个 Electron 写的 macOS 桌面宠物。透明置顶窗口，不占程序坞，平时在屏幕边缘来回游动，到点提醒你吃饭下班，跑 Codex / Claude Code 任务时会在头顶显示任务卡片。

### 功能

**互动**

- 点击会变形流泪（被揍），拖拽可以随便丢，甩出去有惯性和边界回弹
- 鼠标停在身上它就停下来；来回撫摸会脸红、说话，越摸反应越夸张
- 支持水平（沿底部）和垂直（沿边缘）两种游动方式

**捏鱼**

- 身体、鱼鳍可换轮廓预设，眼睛、嘴巴、鼻子可调大小和位置
- 所有调整存在配置里、渲染时叠加，**角色美术文件不会被改动**，随时一键还原
- 每只角色分别保存，互不影响

**表情与饰品（43 件）**

| 位置 | 数量 | 举例 |
| --- | --- | --- |
| 表情 | 18 | 晕、生气、困、撒娇、可怜、得意、心动、慌张…… |
| 头顶 | 9 | 草帽、毛线帽、贝雷帽、圣诞帽、小皇冠、竹蜻蜓…… |
| 眼镜 | 7 | 圆框眼镜、墨镜、爱心镜、星星镜、眼罩…… |
| 手边 | 9 | 咖啡杯、珍珠奶茶、冰淇淋、小雨伞、小鱼干…… |

饰品可调大小、宽高和位置，**每件各自记住自己的数值**，换来换去不会丢。说话时还会按场合临时借用表情——被揍会惊慌，任务做完会得意，快到饭点会饿——气泡消失后换回你选的那个。

**提醒与集成**

- 吃饭、下班、半小时提醒，可配置时间与开关；安静时段内不打扰
- 工作日早晨 / 休息日白天的每日首次问候
- Codex / Claude Code 任务状态桥接，任务完成可播放系统提示音
- 锁屏唤醒、低电量提醒、日历日程提醒（日历默认关闭）

**可扩展**

角色、语言、饰品都是独立资源包，加内容不用改代码。

### 安装运行

需要 [Node.js](https://nodejs.org) 22.12 或更新版本。

```bash
git clone https://github.com/Kinley1212/blobfish-desktop-pet.git
cd blobfish-desktop-pet
npm install
npm start
```

右键鱼本体、或点击菜单栏的 🐟 打开设置。

### 应用内更新

在“设置 → 连接与隐私 → 软件更新”中点“检查 GitHub 更新”。发现新版后，“下载并更新”会只下载适合当前 Mac 芯片的 GitHub Release 安装包，校验 GitHub 提供的 SHA-256 后自动安装、重开应用，并把旧版放进废纸篓以便恢复。

维护者发布时需要创建**正式** GitHub Release，标签使用 `v1.1.2` 这类格式，并上传两个同版本产物：

```text
水滴鱼Pro1.1.2-macOS-arm64.zip
水滴鱼Pro1.1.2-macOS-x64.zip
```

Draft 和 Pre-release 不会被应用内更新发现；缺少 GitHub SHA-256 摘要的安装包也不会自动安装。

### 打包成 App

```bash
npm run package:mac:arm64   # Apple Silicon
npm run package:mac:x64     # Intel
```

会编译对应架构的日历助手与任务发送器、生成 App、做 ad-hoc 本地签名、校验架构，产物写入 `release/`。`npm run package:mac` 会依次生成两种架构。

> 日历助手用到 macOS 14 的 EventKit 接口，需要在 macOS 14 或更新的系统上打包。
>
> ad-hoc 签名适合本机验收和开发者之间传递。面向普通用户分发仍需 Apple Developer ID 证书签名并完成 notarization。

### 加一件自己的饰品

新建一个文件夹就行，不用碰代码：

```
src/packs/accessories/my-hat/
├── manifest.json
└── art/accessory.svg
```

```json
{
  "id": "my-hat",
  "displayName": "我的帽子",
  "version": 1,
  "slot": "hat",
  "art": "art/accessory.svg",
  "anchor": { "x": 50, "y": 74 }
}
```

图画在 `viewBox="0 0 100 100"` 里，`anchor` 是这张图上要贴到角色挂点的那个点。重启后设置里就能选到。角色只要在自己的 manifest 里声明挂点位置，就能共用整套饰品。

### 项目结构

```
src/
├── main.js              主进程：窗口、移动、提醒、托盘、IPC
├── renderer.js          桌宠窗口：互动、动画、饰品渲染
├── settings.js/.html    设置界面
├── core/                纯逻辑模块（有测试覆盖）
└── packs/
    ├── characters/      形象包（水滴鱼、窝窝头版、小草团）
    ├── languages/       语言包
    └── accessories/     饰品与表情
docs/                    各子系统的设计文档
test/                    Node 内置测试
```

### 开发

```bash
npm test
```

详细文档：[形象包](docs/character-packs.md) · [语言包](docs/language-packs.md) · [设置](docs/settings.md) · [系统集成](docs/system-integrations.md) · [任务集成](docs/agent-integrations.md)

### 隐私

主 App 不声明摄像头、麦克风、蓝牙或任意网络加载权限。日历用途声明只存在于独立助手中，且日历功能默认关闭。任务集成默认不上传任何对话内容，任务标题需要手动开启。

### 作者

[Kinley Liao](https://github.com/Kinley1212) · [Corwin2828](https://github.com/Corwin2828)

---

## English

### What is this

A macOS desktop pet built with Electron. It lives in a transparent always-on-top window, stays out of the Dock, swims back and forth along the edge of your screen, reminds you when to eat and when to log off, and shows task cards above its head while Codex or Claude Code is working.

### Features

**Interaction**

- Click it and it squashes and cries; drag it anywhere; fling it and it carries momentum and bounces off the screen edges
- It stops swimming while your cursor rests on it, and blushes and talks when you stroke it back and forth — the longer you keep going, the more it gives in
- Swims either horizontally along the bottom or vertically along an edge

**Shape editor**

- Swap body and fin silhouettes between presets; resize and reposition the eyes, mouth and nose
- Every tweak lives in your config and is layered on at render time — **the character art files are never modified**, so one click puts everything back
- Saved separately per character

**Expressions and accessories (43 pieces)**

| Slot | Count | Examples |
| --- | --- | --- |
| Expression | 18 | dizzy, angry, sleepy, coy, pitiful, proud, smitten, panicked… |
| Head | 9 | straw hat, beanie, beret, santa hat, crown, bamboo copter… |
| Eyewear | 7 | round glasses, sunglasses, heart glasses, star glasses, eyepatch… |
| Hand | 9 | coffee, bubble tea, ice cream, umbrella, dried fish… |

Accessories can be resized and repositioned, and **each piece remembers its own fit** — swapping between two hats never loses either one's adjustment. Speech also borrows an expression to suit the moment: alarmed when punched, proud when a task finishes, hungry near lunchtime. Whatever you picked comes back when the bubble goes.

**Reminders and integrations**

- Lunch, end-of-day and half-hour reminders with configurable times; quiet hours keep it silent
- A first greeting of the day, separately configurable for workdays and days off
- Codex / Claude Code task-status bridge, with an optional system chime on completion
- Wake-from-lock, low-battery and calendar reminders (calendar is off by default)

**Extensible**

Characters, languages and accessories are all self-contained packs — adding content takes no code.

### Getting started

Requires [Node.js](https://nodejs.org) 22.12 or newer.

```bash
git clone https://github.com/Kinley1212/blobfish-desktop-pet.git
cd blobfish-desktop-pet
npm install
npm start
```

Right-click the fish, or click the 🐟 in the menu bar, to open settings.

### In-app updates

Open **Settings → Connections & Privacy → Software Update**, then choose **Check GitHub updates**. When a newer release is available, the app downloads only the matching Mac architecture, verifies GitHub's SHA-256 digest, installs it, reopens the app, and moves the previous copy to the Trash for recovery.

Maintainers must create a published GitHub Release tagged like `v1.1.2` and attach both matching files:

```text
水滴鱼Pro1.1.2-macOS-arm64.zip
水滴鱼Pro1.1.2-macOS-x64.zip
```

Drafts, pre-releases, and assets without a GitHub SHA-256 digest are intentionally not eligible for in-app installation.

### Packaging

```bash
npm run package:mac:arm64   # Apple Silicon
npm run package:mac:x64     # Intel
```

Each command builds the matching-architecture calendar helper and task sender, produces the app, ad-hoc signs it locally, verifies the architecture of the binaries and writes the bundle to `release/`. `npm run package:mac` builds both in turn.

> The calendar helper uses macOS 14 EventKit APIs, so packaging needs macOS 14 or newer.
>
> Ad-hoc signing is fine for local acceptance and passing builds between developers. Distributing to ordinary users still needs an Apple Developer ID certificate and notarization.

### Adding your own accessory

Just add a folder — no code changes:

```
src/packs/accessories/my-hat/
├── manifest.json
└── art/accessory.svg
```

```json
{
  "id": "my-hat",
  "displayName": "My Hat",
  "version": 1,
  "slot": "hat",
  "art": "art/accessory.svg",
  "anchor": { "x": 50, "y": 74 }
}
```

Draw inside `viewBox="0 0 100 100"`; `anchor` is the point on your drawing that lands on the character's slot. Restart and it appears in settings. Any character that declares slot anchors in its own manifest can wear the whole wardrobe.

### Project layout

```
src/
├── main.js              Main process: window, movement, reminders, tray, IPC
├── renderer.js          Pet window: interaction, animation, accessory rendering
├── settings.js/.html    Settings UI
├── core/                Pure logic modules (covered by tests)
└── packs/
    ├── characters/      Character packs (blobfish, bun-shaped, grass buddy)
    ├── languages/       Language packs
    └── accessories/     Accessories and expressions
docs/                    Per-subsystem design notes
test/                    Node built-in test runner
```

### Development

```bash
npm test
```

Docs: [character packs](docs/character-packs.md) · [language packs](docs/language-packs.md) · [settings](docs/settings.md) · [system integrations](docs/system-integrations.md) · [agent integrations](docs/agent-integrations.md)

### Privacy

The main app declares no camera, microphone, Bluetooth or arbitrary network-load entitlements. The calendar usage description exists only in the separate helper, and the calendar feature is off by default. The task integration uploads no conversation content, and task titles are opt-in.

### Authors

[Kinley Liao](https://github.com/Kinley1212) · [Corwin2828](https://github.com/Corwin2828)
