# 水滴魚 VI 原創素材

本目錄存放已接入 accessory pack 的原創 SVG 設計源檔。所有素材使用 `viewBox="0 0 100 100"`，以大面積柔和填色、前後色塊與低對比高光建立層次；可見圖形不使用描邊。

## 鬧鐘

| 檔案 | 名稱 | 輪廓與概念 | 小尺寸辨識點 |
| --- | --- | --- | --- |
| `alarm-clocks/alarm-clock-coral-default.svg` | 珊瑚抱抱鐘 | 不規則珊瑚枝包住珍珠錶面 | 粉色珊瑚臂、圓形珍珠面 |
| `alarm-clocks/alarm-clock-seafoam.svg` | 海泡貝殼鐘 | 放射形扇貝外殼與漂浮氣泡 | 扇形底座、青綠珍珠面 |
| `alarm-clocks/alarm-clock-honey.svg` | 蜂蜜方糖鐘 | 圓角方糖機身與蜂蜜滴冠 | 暖黃方形輪廓、蜜滴頂部 |
| `alarm-clocks/alarm-clock-plum-night.svg` | 月光水母鐘 | 月色水母圓傘與三條觸手 | 紫色傘體、新月錶面、觸手 |

四款均用填色膠囊形指針保留「鐘面」辨識度，輪廓、重心與裝飾語彙互不相同。運行時素材保留 `alarm-clock-shaker` class 供現有響鈴動畫使用。

## 消息提示

| 檔案 | 名稱 | 形象差異 | 既有未讀數字承載區 |
| --- | --- | --- | --- |
| `message-indicators/message-mailbox.svg` | 海葵舉旗郵箱 | 海葵般柔軟的圓頂郵箱 | 淡黃色郵旗 |
| `message-indicators/message-envelope.svg` | 月貝封信 | 展開的月色貝殼包住信件 | 深紫色貝殼封印 |
| `message-indicators/message-flying-letter.svg` | 魟魚飛信 | 魟魚載著中央小信封游來 | 奶油色中央信封 |
| `message-indicators/message-sea-mail.svg` | 海瓶漂流信 | 半透明海玻璃瓶與瓶中信 | 奶油色瓶中信紙 |

未讀數字直接落在物件自身的旗、封印或信紙上，不額外疊加傳統紅色角標。四款均保留既有 100×100 數字區，無需修改運行時定位幾何。

## 原創與使用邊界

- 所有路徑均由本項目從零設計，沒有描摹、匯入或改寫 Apple、emoji 或第三方圖示路徑。
- SVG 僅包含靜態幾何、分層填色與透明度；沒有外部引用、script、filter 或文字節點。
- 本輪只執行 XML、靜態安全、資產載入與程式測試；沒有進行渲染、截圖或人工視覺 QA。
- 授權與來源聲明見 [LICENSE.md](LICENSE.md)。
