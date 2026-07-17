# 形象包与动作约定

每个形象放在 `src/packs/characters/<id>/`，目录名和 `manifest.json` 的 `id` 必须一致。ID 只允许小写字母、数字和连字符。

```text
<id>/
  manifest.json
  art/
    character.svg
  animations/
    base.css
    idle.css
    blink.css
    roam.css
    working.css
    waiting.css
    success.css
    failed.css
    hit.css
    bump.css
    dragging.css
```

## 最低要求

- SVG 必须是完整角色，不得包含脚本、外部链接或 `foreignObject`。
- `manifest.json` 必须声明所有标准动作；未制作的工作、等待、成功和失败动作可以在 `fallbacks` 中回退。
- CSS 只能负责视觉表现，不得包含 JavaScript。
- `.eye` 是眨眼动作的标准眼睛选择器；没有眼睛的角色可以保留空的 `blink.css`。
- 角色朝向通过 `#pet` 上的 `--dir` CSS 变量控制，值为 `1` 或 `-1`。

## 标准动作

| 动作 | 语义 |
|---|---|
| `idle` | 没有任务时的静止呼吸 |
| `blink` | 随机眨眼 |
| `roam` | 有任务时在桌面移动 |
| `working` | 有任务但不移动时的处理动作 |
| `waiting` | 等待用户确认 |
| `success` | 单个或全部任务完成 |
| `failed` | 任务失败 |
| `hit` | 被点击 |
| `bump` | 碰撞屏幕边缘 |
| `dragging` | 被用户拖动 |

运行 `npm test` 会检查内置形象包的目录边界、清单结构、动作完整性和资源大小。
