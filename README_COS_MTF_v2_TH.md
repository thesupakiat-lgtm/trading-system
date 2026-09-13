# COS MTF Smart Money Confluence v2.0

Indicator สำหรับ TradingView Pine Script v6 ที่รวมแนวคิด Multi-Timeframe Bias, confirmed swing, COS Fibonacci, swing volume profile/POC, BOS/CHOCH, liquidity sweep, Supply/Demand, FVG, Order Block, setup grade และแผน Entry/SL/TP ไว้ในสคริปต์เดียว

> ใช้เพื่อการวิเคราะห์และทดสอบระบบเท่านั้น ไม่ใช่คำแนะนำการลงทุน และสคริปต์นี้ไม่ส่งคำสั่งซื้อขายจริง

## ไฟล์หลัก

- `COS_MTF_Smart_Money_Confluence_v2.pine` — โค้ด Indicator
- `COS_MTF_Smart_Money_v2_preview.png` — ภาพ Concept Preview
- `COS_MTF_v2_static_check.md` — รายงานตรวจโครงสร้างโค้ด

## Logic หลัก

1. คำนวณ Bias ของ TF1–TF5 จาก market structure และ EMA
2. รวมคะแนน TF ที่เปิดใช้เป็น MTF Consensus
3. หา confirmed pivot และสร้างขา Bullish/Bearish swing ที่ยืนยันแล้ว
4. ตี COS30, COS45 และ COS60 ตามทิศทางของ Anchor Bias
5. ใช้พื้นที่ระหว่าง COS30–COS45 เป็น Entry Zone
6. คำนวณ Swing Volume Profile และ POC จากแท่งภายในขา impulse ที่เลือก
7. ตรวจ BOS/CHOCH และ liquidity sweep จาก confirmed pivot
8. สร้างและติดตาม Supply/Demand, FVG และ Order Block
9. เปลี่ยน Zone เป็น Mitigated หรือซ่อนตามค่าที่ตั้งไว้
10. สัญญาณต้องแตะ COS Entry Zone และผ่าน Location Confluence ตามจำนวนขั้นต่ำ
11. คำนวณคะแนนรวมและจัด Grade A/B/C
12. สร้าง Entry, Stop Loss และ Take Profit ตาม Reward/Risk ที่กำหนด

## Location Confluence

กลุ่ม Location ได้แก่:

- POC อยู่ภายใน/ใกล้ COS Entry Zone และแท่งราคาสัมผัส POC
- Demand/Supply ซ้อนกับ COS Entry Zone และแท่งราคาสัมผัสพื้นที่ซ้อนกัน
- Bullish/Bearish FVG ซ้อนกับ COS Entry Zone
- Bullish/Bearish Order Block ซ้อนกับ COS Entry Zone

ค่าเริ่มต้นเปิด `Require at least one POC/zone match` เพื่อป้องกันไม่ให้ BOS, sweep หรือ candle pattern เพียงอย่างเดียวสร้างสัญญาณ

## Extra Confirmation

- BOS/CHOCH ล่าสุดต้องตรงกับทิศทางเข้า
- Liquidity sweep ภายในจำนวนแท่งที่กำหนด
- Rejection candle, Engulfing หรือ Either

เฉพาะ Confirmation ที่เปิดใช้งานเท่านั้นที่จะถูกนับในตัวหารของคะแนน

## Grade

- Grade A: คะแนนเป็นเปอร์เซ็นต์ตั้งแต่ค่า A threshold ขึ้นไป
- Grade B: คะแนนตั้งแต่ B threshold ถึงก่อน A threshold
- Grade C: ผ่าน minimum confirmations แต่ต่ำกว่า B threshold
- Minimum signal grade เลือก A, B หรือ C ได้

ค่าเริ่มต้น:

- Grade A = 80%
- Grade B = 60%
- Minimum signal grade = B
- Minimum total confirmations = 3
- Minimum location confirmations = 1

## Zone Mitigation

เลือกเกณฑ์ได้ 3 แบบ:

- `Touch` — ราคาแตะขอบแรกของ Zone
- `50%` — ราคาแตะ midpoint ของ Zone
- `Full fill` — ราคาวิ่งถึงขอบไกลของ Zone

เมื่อ Mitigated:

- `Hide mitigated zones = false` — Zone หยุดขยาย เปลี่ยนเป็นสีเทา และไม่ใช้เป็น confluence อีก
- `Hide mitigated zones = true` — ลบ Zone ออกจากกราฟ

Invalidation เลือก `Close` หรือ `Wick` ได้

## Volume Profile

- `HLC3 allocation` — ใส่ volume ของแต่ละแท่งไว้ที่ bin ของราคา HLC3 เร็วกว่าและเป็นค่าเริ่มต้น
- `Range distributed` — กระจาย volume ไปตาม bins ที่แท่งราคาครอบคลุม ใช้ difference-array เพื่อลดภาระ loop

POC คำนวณจากช่วงขา impulse ที่ยืนยันแล้ว ไม่รวม retracement หลัง Swing endpoint

สำหรับ Forex ข้อมูล volume ของหลายโบรกเกอร์เป็น tick volume ไม่ใช่ centralized exchange volume จึงควรใช้ POC เป็น confluence ไม่ใช่หลักฐาน order flow ที่แน่นอน

## Stop Loss

- `Swing` — หลัง Swing Low/High พร้อม ATR buffer
- `Entry Zone` — หลังขอบ COS Entry Zone พร้อม ATR buffer
- `ATR` — ระยะ ATR จากราคาสัญญาณ

Take Profit คำนวณจาก:

`Reward = Risk × Reward/Risk`

ค่าเริ่มต้น `Reward/Risk = 0.58` จึงแสดงเป็น `RR 1:0.58`

## ลด Repaint

ค่าตั้งต้นใช้:

- confirmed pivots
- last closed HTF candle
- `barmerge.lookahead_off`
- signals only on confirmed chart bar

Pivot จะปรากฏย้อนหลังที่ตำแหน่ง Swing หลังรอครบ `Swing pivot length` แท่ง ซึ่งเป็นการยืนยันแบบล่าช้า ไม่ใช่การรู้ Swing ล่วงหน้า ส่วน Fib anchor และ POC สามารถเปลี่ยนเมื่อมี Swing ใหม่ยืนยันหรือทิศทาง Bias เปลี่ยน

## วิธีติดตั้ง

1. เปิด TradingView
2. เข้า Pine Editor
3. สร้าง Blank Indicator
4. ลบโค้ดเดิมทั้งหมด
5. วางโค้ดจากไฟล์ `.pine`
6. กด Save
7. กด Add to chart
8. เปิด Settings และปรับ TF, Swing length, Zone, Grade และ RR ให้เหมาะกับคู่เงิน/TF

## ค่าทดสอบเริ่มต้นสำหรับ XAUUSD

ค่าต่อไปนี้เป็นเพียงจุดเริ่มต้นสำหรับ forward test:

- Chart TF: M15 หรือ H1
- TF1/TF2/TF3: M15 / H1 / H4
- Swing pivot length: 5–8
- Profile rows: 24–40
- FVG minimum: 0.10–0.25 ATR
- Displacement: 1.0–1.5 ATR
- Minimum total confirmations: 3–4
- Minimum signal grade: B
- Confirmed chart bar: On
- Last closed HTF: On

## Error Check

ไฟล์ผ่าน static checks 15 รายการ เช่น delimiter, indentation, global plot scope, request count, direct `na` comparison, history guard, table bounds, parallel zone arrays และ signal gating

Static check ไม่ใช่ Pine compiler ของ TradingView การยืนยันขั้นสุดท้ายต้องวางโค้ดใน Pine Editor และกด Add to chart เพราะ TradingView ไม่มี standalone compiler อย่างเป็นทางการให้ใช้ในสภาพแวดล้อมนี้
