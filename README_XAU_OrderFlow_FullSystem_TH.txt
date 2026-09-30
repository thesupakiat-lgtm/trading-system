XAU ORDER FLOW FULL SYSTEM v1.0 (MT5)
=====================================

ไฟล์หลัก
--------
XAU_OrderFlow_FullSystem_v1_0.mq5

วัตถุประสงค์
-------------
Indicator สำหรับ MetaTrader 5 ที่สร้าง Footprint / Cluster จากข้อมูล Tick ของสัญลักษณ์บนกราฟ
พร้อม Delta, CVD, Session Volume Profile, POC, VAH, VAL, HVN, LVN, Imbalance,
Stacked Imbalance, Absorption/Exhaustion Proxy, Liquidity Sweep, BOS/CHOCH,
Price-CVD Divergence, Dashboard, Confluence Bias และ Alert

ข้อจำกัดสำคัญ
-------------
1. เมื่อใช้กับ XAUUSD ของโบรกเกอร์ MT5 ระบบนี้เป็น ORDER-FLOW PROXY
   ไม่ใช่ True COMEX GC Order Flow เพราะ XAUUSD เป็นตลาด OTC และโบรกเกอร์แต่ละรายส่งข้อมูลไม่เหมือนกัน
2. AUTO mode จะใช้ TICK_FLAG_BUY/TICK_FLAG_SELL ถ้า feed ส่งข้อมูลด้านคำสั่งซื้อขายมาเพียงพอ
   ถ้าไม่มี ระบบจะใช้ Tick Rule: ราคาขยับขึ้นจัดเป็น Buy, ราคาขยับลงจัดเป็น Sell
3. คุณภาพ Footprint ขึ้นอยู่กับ Tick History ของโบรกเกอร์
4. Indicator นี้ไม่เปิด Order และไม่ใช่ EA
5. ควรทดสอบบนบัญชี Demo ก่อนใช้ประกอบการตัดสินใจจริง

วิธีติดตั้ง
----------
1. เปิด MT5
2. ไปที่ File > Open Data Folder
3. เปิดโฟลเดอร์ MQL5 > Indicators
4. วางไฟล์ XAU_OrderFlow_FullSystem_v1_0.mq5 ลงในโฟลเดอร์ Indicators
5. เปิด MetaEditor จาก MT5 หรือกด F4
6. เปิดไฟล์ Indicator แล้วกด F7 เพื่อ Compile
7. กลับ MT5 แล้วคลิกขวาที่ Navigator > Indicators > Refresh
8. ลาก Indicator ไปวางบนกราฟ XAUUSD

ค่าตั้งต้นแนะนำสำหรับ XAUUSD M5
------------------------------
Classification            = AUTO
History Bars              = 30
Max Tick Lookback Hours   = 10
Refresh Seconds           = 2
Price Step Points         = 10
Max Levels Per Bar        = 180
Footprint Bars            = 16
Imbalance Ratio           = 3.0
Stacked Levels            = 3
Session Start Hour        = ตั้งตามเวลา Server ของโบรกเกอร์
Value Area Percent        = 70
Confluence Threshold      = 3

ความหมาย Price Step Points
--------------------------
ค่าจะคูณกับ _Point ของสัญลักษณ์
ตัวอย่าง:
- ถ้า XAUUSD แสดง 2 ตำแหน่งทศนิยม และ _Point = 0.01
  Price Step Points = 10 หมายถึง 0.10 ดอลลาร์ต่อ 1 Footprint bucket
- ถ้าตัวเลขแน่นเกินไป ให้เพิ่มเป็น 20, 25 หรือ 50
- ถ้าตัวเลขห่างเกินไป ให้ลดเป็น 5

โมดูลหลัก
---------
1. Footprint / Cluster
   แสดง Sell Volume ทางซ้ายและ Buy Volume ทางขวาของแต่ละระดับราคา

2. Delta / CVD
   Delta = Buy Volume - Sell Volume
   CVD = Delta สะสมตั้งแต่ Session Start

3. Imbalance / Stacked Imbalance
   ตรวจความไม่สมดุลของ Buy/Sell ตาม Ratio ที่ตั้งไว้

4. Session Volume Profile
   แสดง Volume และ Delta ตามระดับราคา พร้อม POC, VAH, VAL, HVN และ LVN

5. Absorption Proxy
   ตรวจกรณี Volume/แรงซื้อขายสูง แต่ราคาปิดปฏิเสธด้านนั้น

6. Exhaustion Proxy
   ตรวจ Activity ที่ปลาย High/Low ลดลงและราคาปฏิเสธ

7. Liquidity Sweep
   ตรวจการทะลุ Previous High/Low แล้วปิดกลับเข้ากรอบ

8. Market Structure
   ตรวจ Swing, BOS และ CHOCH

9. CVD Divergence
   Bullish: ราคาทำ Lower Low แต่ CVD ทำ Higher Low
   Bearish: ราคาทำ Higher High แต่ CVD ทำ Lower High

10. Confluence Bias
    รวมหลายเงื่อนไขเป็น BULLISH, BEARISH หรือ WAIT / NEUTRAL

คำแนะนำการอ่าน Setup
--------------------
Long Setup ที่มีคุณภาพมากขึ้นควรเห็นหลายองค์ประกอบร่วมกัน เช่น:
Liquidity Sweep Low + Buy Absorption + Bullish CVD Divergence + Buy Imbalance + CHOCH Up

Short Setup ที่มีคุณภาพมากขึ้นควรเห็น:
Liquidity Sweep High + Sell Absorption + Bearish CVD Divergence + Sell Imbalance + CHOCH Down

อย่าใช้ Delta เพียงตัวเดียวเป็นเหตุผล Buy/Sell
Delta ลบมากแต่ราคาลงต่อไม่ได้ อาจเป็น Buy Absorption
Delta บวกมากแต่ราคาขึ้นต่อไม่ได้ อาจเป็น Sell Absorption

แก้ปัญหาเบื้องต้น
-----------------
1. ขึ้น WAITING FOR TICK HISTORY
   - รอให้ MT5 ดาวน์โหลด Tick History
   - ตรวจ Internet และการเชื่อมต่อ Broker
   - เปิดกราฟทิ้งไว้สักครู่
   - ลด History Bars หรือ Max Tick Lookback Hours

2. ไม่เห็นตัวเลข Footprint
   - Zoom กราฟเข้า
   - เพิ่ม Price Step Points
   - ลด Footprint Bars
   - ตรวจว่า Show Footprint = true

3. Indicator หน่วง
   - History Bars = 15 ถึง 20
   - Footprint Bars = 8 ถึง 12
   - Refresh Seconds = 3 ถึง 5
   - เพิ่ม Price Step Points
   - ปิด CVD Panel หรือ Delta Panel ที่ไม่ใช้

4. Profile ไม่ครบทั้งวัน
   - Max Tick Lookback Hours ต้องครอบคลุมเวลาตั้งแต่ Session Start
   - Tick History ที่โบรกเกอร์เก็บต้องมีเพียงพอ

5. ต้องการ True Order Flow
   - ต้องรับข้อมูล GC Futures จาก Exchange/Data Provider ภายนอก
   - MT5 XAUUSD Tick Rule ไม่สามารถแทน COMEX Bid x Ask ได้ทั้งหมด

หมายเหตุการ Compile
-------------------
Source ถูกออกแบบตาม MQL5 Standard Library และ Canvas API
แต่ควร Compile ด้วย MetaEditor ของ MT5 ที่ติดตั้งอยู่ในเครื่องผู้ใช้ เพราะ Build และ Feed ของโบรกเกอร์อาจต่างกัน
หาก MetaEditor แจ้ง Error ให้เก็บข้อความ Error พร้อมเลขบรรทัดเพื่อแก้ไขตรงจุด
