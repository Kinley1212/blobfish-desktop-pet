# 水滴魚 VI 概念素材

本目錄存放尚未接入運行時的原創 SVG 概念稿，供後續人工選款與實作。所有素材均使用 `viewBox="0 0 100 100"`，以大輪廓、少量層次和粗圓線條確保在約 24–40 px 顯示時仍可辨識。

## 鬧鐘

| 檔案 | 名稱 | 核心色 | 設計用途 |
| --- | --- | --- | --- |
| `alarm-clocks/alarm-clock-coral-default.svg` | 珊瑚抱抱鐘（新預設候選） | `#F06469`、`#FFF5E9`、`#5B3B43` | 最接近水滴魚的柔軟暖色；雙鈴、奶油錶面和左上高光在小尺寸最易辨識。 |
| `alarm-clocks/alarm-clock-seafoam.svg` | 海沫小鐘 | `#62B8AD`、`#E8FFF8`、`#355D59` | 清爽冷色，不會和粉色角色黏成一團；適合專注／快速計時。 |
| `alarm-clocks/alarm-clock-honey.svg` | 蜂蜜方鐘 | `#F5BD55`、`#FFF7DF`、`#694D34` | 圓角方形輪廓，暖黃但不是警示紅；適合小草團與溫和提醒。 |
| `alarm-clocks/alarm-clock-plum-night.svg` | 梅子夜鐘 | `#80658F`、`#F8F0FF`、`#4D3A59` | 深色外殼配淡紫錶面，夜間對比高，氣質較安靜。 |

建議掛點皆為下方中心；若沿用 accessory 座標，可先以 `anchor x=16, y=27` 試配，再由人工視覺 QA 微調。四款都刻意保留雙鈴或頂部按鈕、清楚錶面和短腳，避免縮小後只剩一般圓形。

## 消息提示

| 檔案 | 名稱 | 核心色 | 非傳統角標策略 |
| --- | --- | --- | --- |
| `message-indicators/message-mailbox.svg` | 舉旗小郵箱 | `#69AFC0`、`#FFE5A3`、`#355A66` | 未讀數字可直接放在黃色郵旗上，不另疊紅色圓點。 |
| `message-indicators/message-envelope.svg` | 軟角信封 | `#FFF0CF`、`#9A83B5`、`#594E69` | 未讀數字可置於信封正面的小紫封印中；封印是物件細節，不是外掛 badge。 |
| `message-indicators/message-flying-letter.svg` | 飛來信 | `#BDE9EA`、`#F4C96A`、`#3F6570` | 未讀數字直接印在信封正面，飛行線只表達新消息到達。 |
| `message-indicators/message-sea-mail.svg` | 漂流瓶信 | `#83CFC3`、`#FFF1CF`、`#4A6864` | 未讀數字放在瓶內信紙上；適合水滴魚，也以自然色和小草團共用。 |

消息提示均避開目前紅色膠囊式 `badge`。後續接入時建議用深色 9–11 pt 粗體數字覆蓋指定物件區域，超過 9 則顯示 `9+`；不要再加第二層圓點。

## 原創與使用邊界

- 圓潤輪廓、前後分層與柔和高光只是一般鬧鐘 emoji／玩具圖示的高階視覺特徵；沒有描摹、匯入或改寫 Apple 或第三方圖示路徑。
- 本目錄沒有修改 Swift、accessory manifest 或當前運行時素材；選款前不會被應用自動載入。
- 本輪只做 XML、畫布和靜態安全檢查，未啟動應用、未製作運行截圖，也未替代人工視覺 QA。
- 授權與來源聲明見 [LICENSE.md](LICENSE.md)。
