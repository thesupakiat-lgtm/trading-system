//+------------------------------------------------------------------+
//| XAU Order Flow Full System v1.0                                 |
//| MT5 tick-based footprint / order-flow proxy indicator            |
//|                                                                  |
//| IMPORTANT                                                        |
//| - On OTC symbols such as XAUUSD this is an ORDER-FLOW PROXY.     |
//| - It uses exchange BUY/SELL flags when a broker supplies them.   |
//| - Otherwise it classifies ticks with the tick rule.              |
//| - It does not place orders.                                      |
//+------------------------------------------------------------------+
#property copyright "OpenAI / User project"
#property version   "1.00"
#property description "Tick-based footprint, delta, CVD, profile, liquidity and structure dashboard"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "OrderFlowStatus"
#property indicator_type1   DRAW_NONE

#include <Canvas\Canvas.mqh>

#define OF_MAX_BARS             80
#define OF_MAX_LEVELS          320
#define OF_MAX_PROFILE_LEVELS  640
#define OF_EPSILON              1.0e-10

//--- data classification mode
enum ENUM_OF_CLASSIFICATION
  {
   OF_CLASSIFY_AUTO=0,          // exchange side flag when available, otherwise tick rule
   OF_CLASSIFY_EXCHANGE_FLAGS,  // use TICK_FLAG_BUY / TICK_FLAG_SELL only
   OF_CLASSIFY_TICK_RULE        // uptick/downtick proxy
  };

//--- dashboard corner
enum ENUM_OF_PANEL_CORNER
  {
   OF_PANEL_TOP_LEFT=0,
   OF_PANEL_TOP_RIGHT
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "01. Data Engine"
input ENUM_OF_CLASSIFICATION InpClassification       = OF_CLASSIFY_AUTO;
input int                    InpHistoryBars          = 30;       // bars rebuilt from tick history
input int                    InpMaxTickLookbackHours = 10;       // hard time cap for tick request
input int                    InpRefreshSeconds       = 2;        // rebuild frequency
input double                 InpPriceStepPoints      = 10.0;     // footprint bucket in chart points
input int                    InpMaxLevelsPerBar      = 180;      // auto-increase step above this count
input bool                   InpUseRealVolume        = true;     // use tick real volume when supplied

input group "02. Footprint / Imbalance"
input bool   InpShowFootprint          = true;
input int    InpFootprintBars          = 16;
input int    InpMinCellHeightPx        = 8;
input int    InpMinBarWidthPx          = 28;
input double InpImbalanceRatio         = 3.0;
input double InpMinImbalanceVolume     = 3.0;
input int    InpStackedLevels          = 3;
input bool   InpDiagonalImbalance      = true;
input bool   InpShowBarPOC             = true;

input group "03. Session Profile"
input bool   InpShowVolumeProfile      = true;
input int    InpSessionStartHour       = 0;        // broker/server time
input int    InpSessionStartMinute     = 0;
input double InpValueAreaPercent       = 70.0;
input int    InpProfilePanelWidth      = 220;
input bool   InpShowPOC_VAH_VAL_Lines  = true;
input bool   InpShowHVN_LVN            = true;

input group "04. Signal Logic"
input int    InpVolumeAverageLookback  = 12;
input double InpAbsorptionVolumeFactor = 1.50;
input double InpAbsorptionPressurePct  = 62.0;
input double InpAbsorptionCloseFrac    = 0.45;
input int    InpLiquidityLookback      = 12;
input double InpSweepTolerancePoints   = 2.0;
input int    InpPivotLength            = 3;
input int    InpDivergenceMaxAgeBars   = 12;
input int    InpConfluenceThreshold    = 3;

input group "05. Dashboard / Lower Panels"
input bool                 InpShowDashboard     = true;
input ENUM_OF_PANEL_CORNER InpDashboardCorner  = OF_PANEL_TOP_RIGHT;
input int                  InpDashboardWidth    = 270;
input bool                 InpShowCVDPanel      = true;
input bool                 InpShowDeltaPanel    = true;
input int                  InpLowerPanelHeight  = 145;
input bool                 InpShowSignalMarkers = true;
input int                  InpFontSize          = 10;

input group "06. Alerts"
input bool   InpEnableAlerts            = true;
input bool   InpPopupAlert              = true;
input bool   InpSoundAlert              = false;
input string InpSoundFile               = "alert.wav";
input bool   InpPushNotification        = false;
input bool   InpAlertOnClosedBarOnly     = true;

input group "07. Colors"
input color InpBuyColor          = clrLimeGreen;
input color InpSellColor         = clrTomato;
input color InpNeutralColor      = clrSilver;
input color InpPOCColor          = clrGold;
input color InpVAColor           = clrDeepSkyBlue;
input color InpPanelBackground   = C'10,16,24';
input color InpPanelBorder       = C'74,92,112';
input color InpTextColor         = clrWhiteSmoke;
input color InpBullSignalColor   = clrLime;
input color InpBearSignalColor   = clrRed;
input color InpWarningColor      = clrOrange;

//+------------------------------------------------------------------+
//| Indicator buffer                                                 |
//+------------------------------------------------------------------+
double g_status_buffer[];

//+------------------------------------------------------------------+
//| Main data                                                        |
//+------------------------------------------------------------------+
MqlRates g_rates[OF_MAX_BARS];
int      g_bar_count=0;

double g_buy[OF_MAX_BARS][OF_MAX_LEVELS];
double g_sell[OF_MAX_BARS][OF_MAX_LEVELS];
bool   g_buy_imb[OF_MAX_BARS][OF_MAX_LEVELS];
bool   g_sell_imb[OF_MAX_BARS][OF_MAX_LEVELS];
long   g_base_bucket[OF_MAX_BARS];
int    g_level_count[OF_MAX_BARS];

double g_total_volume[OF_MAX_BARS];
double g_delta[OF_MAX_BARS];
double g_cvd[OF_MAX_BARS];
double g_buy_pressure[OF_MAX_BARS];
int    g_bar_poc_level[OF_MAX_BARS];

bool g_buy_stacked[OF_MAX_BARS];
bool g_sell_stacked[OF_MAX_BARS];
bool g_buy_absorption[OF_MAX_BARS];
bool g_sell_absorption[OF_MAX_BARS];
bool g_buy_exhaustion[OF_MAX_BARS];
bool g_sell_exhaustion[OF_MAX_BARS];
bool g_sweep_low[OF_MAX_BARS];
bool g_sweep_high[OF_MAX_BARS];
bool g_bull_divergence[OF_MAX_BARS];
bool g_bear_divergence[OF_MAX_BARS];
bool g_bos_bull[OF_MAX_BARS];
bool g_bos_bear[OF_MAX_BARS];
bool g_choch_bull[OF_MAX_BARS];
bool g_choch_bear[OF_MAX_BARS];
int  g_structure_trend[OF_MAX_BARS];
int  g_bull_score[OF_MAX_BARS];
int  g_bear_score[OF_MAX_BARS];

//--- profile
double g_profile_volume[OF_MAX_PROFILE_LEVELS];
double g_profile_delta[OF_MAX_PROFILE_LEVELS];
long   g_profile_base_bucket=0;
int    g_profile_levels=0;
int    g_profile_poc_index=-1;
int    g_profile_val_index=-1;
int    g_profile_vah_index=-1;
double g_profile_poc_price=0.0;
double g_profile_val_price=0.0;
double g_profile_vah_price=0.0;
double g_profile_hvn_price=0.0;
double g_profile_lvn_price=0.0;
double g_session_delta=0.0;

//--- state
double   g_step=0.0;
double   g_tick_size=0.0;
datetime g_session_start=0;
int      g_direct_flag_ticks=0;
int      g_proxy_ticks=0;
int      g_processed_ticks=0;
string   g_data_status="INITIALIZING";
datetime g_last_alert_bar=0;
bool     g_busy=false;
bool     g_need_redraw=true;
bool     g_first_refresh=true;

//--- canvas
CCanvas g_canvas;
string  g_canvas_name="XAU_OF_FS_CANVAS";
int     g_canvas_width=0;
int     g_canvas_height=0;
bool    g_canvas_ready=false;

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
int ClampInt(const int value,const int min_value,const int max_value)
  {
   if(value<min_value) return min_value;
   if(value>max_value) return max_value;
   return value;
  }

double ClampDouble(const double value,const double min_value,const double max_value)
  {
   if(value<min_value) return min_value;
   if(value>max_value) return max_value;
   return value;
  }

uint ARGB(const color clr,const uchar alpha=255)
  {
   return ColorToARGB(clr,alpha);
  }

string FormatVolume(const double value)
  {
   double v=MathAbs(value);
   if(v>=1000000.0) return StringFormat("%.1fM",value/1000000.0);
   if(v>=10000.0)   return StringFormat("%.0fK",value/1000.0);
   if(v>=1000.0)    return StringFormat("%.1fK",value/1000.0);
   if(v>=100.0)     return StringFormat("%.0f",value);
   if(v>=10.0)      return StringFormat("%.0f",value);
   return StringFormat("%.1f",value);
  }

string BiasText(const int bull,const int bear)
  {
   if(bull>=InpConfluenceThreshold && bull>bear) return "BULLISH";
   if(bear>=InpConfluenceThreshold && bear>bull) return "BEARISH";
   return "WAIT / NEUTRAL";
  }

color BiasColor(const int bull,const int bear)
  {
   if(bull>=InpConfluenceThreshold && bull>bear) return InpBullSignalColor;
   if(bear>=InpConfluenceThreshold && bear>bull) return InpBearSignalColor;
   return InpWarningColor;
  }

string BoolText(const bool value,const string yes_text,const string no_text="-")
  {
   return value ? yes_text : no_text;
  }

bool SameSession(const datetime a,const datetime b)
  {
   MqlDateTime da,db;
   TimeToStruct(a,da);
   TimeToStruct(b,db);
   return (da.year==db.year && da.mon==db.mon && da.day==db.day);
  }

//+------------------------------------------------------------------+
//| Session start in broker/server time                              |
//+------------------------------------------------------------------+
datetime CurrentSessionStart(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now,dt);
   dt.hour=ClampInt(InpSessionStartHour,0,23);
   dt.min =ClampInt(InpSessionStartMinute,0,59);
   dt.sec =0;
   datetime start=StructToTime(dt);
   if(now<start) start-=86400;
   return start;
  }

//+------------------------------------------------------------------+
//| Reset arrays                                                     |
//+------------------------------------------------------------------+
void ResetData()
  {
   for(int b=0;b<OF_MAX_BARS;b++)
     {
      g_base_bucket[b]=0;
      g_level_count[b]=0;
      g_total_volume[b]=0.0;
      g_delta[b]=0.0;
      g_cvd[b]=0.0;
      g_buy_pressure[b]=50.0;
      g_bar_poc_level[b]=-1;
      g_buy_stacked[b]=false;
      g_sell_stacked[b]=false;
      g_buy_absorption[b]=false;
      g_sell_absorption[b]=false;
      g_buy_exhaustion[b]=false;
      g_sell_exhaustion[b]=false;
      g_sweep_low[b]=false;
      g_sweep_high[b]=false;
      g_bull_divergence[b]=false;
      g_bear_divergence[b]=false;
      g_bos_bull[b]=false;
      g_bos_bear[b]=false;
      g_choch_bull[b]=false;
      g_choch_bear[b]=false;
      g_structure_trend[b]=0;
      g_bull_score[b]=0;
      g_bear_score[b]=0;
      for(int l=0;l<OF_MAX_LEVELS;l++)
        {
         g_buy[b][l]=0.0;
         g_sell[b][l]=0.0;
         g_buy_imb[b][l]=false;
         g_sell_imb[b][l]=false;
        }
     }

   for(int p=0;p<OF_MAX_PROFILE_LEVELS;p++)
     {
      g_profile_volume[p]=0.0;
      g_profile_delta[p]=0.0;
     }

   g_profile_levels=0;
   g_profile_poc_index=-1;
   g_profile_val_index=-1;
   g_profile_vah_index=-1;
   g_profile_poc_price=0.0;
   g_profile_val_price=0.0;
   g_profile_vah_price=0.0;
   g_profile_hvn_price=0.0;
   g_profile_lvn_price=0.0;
   g_session_delta=0.0;
   g_direct_flag_ticks=0;
   g_proxy_ticks=0;
   g_processed_ticks=0;
  }

//+------------------------------------------------------------------+
//| Canvas management                                                |
//+------------------------------------------------------------------+
bool EnsureCanvas()
  {
   int width =(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(width<320 || height<240) return false;

   if(g_canvas_ready && width==g_canvas_width && height==g_canvas_height)
      return true;

   if(g_canvas_ready)
     {
      g_canvas.Destroy();
      ObjectDelete(0,g_canvas_name);
      g_canvas_ready=false;
     }

   if(!g_canvas.CreateBitmapLabel(0,0,g_canvas_name,0,0,width,height,COLOR_FORMAT_ARGB_NORMALIZE))
     {
      Print("XAU OF: canvas creation failed. Error ",GetLastError());
      return false;
     }

   ObjectSetInteger(0,g_canvas_name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_YDISTANCE,0);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_BACK,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,g_canvas_name,OBJPROP_ZORDER,0);

   g_canvas_width=width;
   g_canvas_height=height;
   g_canvas_ready=true;
   return true;
  }

void DrawText(const int x,const int y,const string text,const color clr,const int align=0)
  {
   uint anchor=TA_LEFT|TA_TOP;
   if(align==1) anchor=TA_CENTER|TA_TOP;
   if(align==2) anchor=TA_RIGHT|TA_TOP;
   g_canvas.TextOut(x,y,text,ARGB(clr),anchor);
  }

void DrawHLine(const int y,const int x1,const int x2,const color clr,const uchar alpha=190,const int dash=0)
  {
   if(y<0 || y>=g_canvas_height) return;
   if(dash<=0)
     {
      g_canvas.Line(x1,y,x2,y,ARGB(clr,alpha));
      return;
     }
   for(int x=x1;x<x2;x+=dash*2)
      g_canvas.Line(x,y,MathMin(x+dash,x2),y,ARGB(clr,alpha));
  }

void DrawPanel(const int x1,const int y1,const int x2,const int y2,const uchar alpha=220)
  {
   g_canvas.FillRectangle(x1,y1,x2,y2,ARGB(InpPanelBackground,alpha));
   g_canvas.Rectangle(x1,y1,x2,y2,ARGB(InpPanelBorder,240));
  }

//+------------------------------------------------------------------+
//| Determine effective footprint step                               |
//+------------------------------------------------------------------+
double CalculateEffectiveStep()
  {
   g_tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_tick_size<=0.0) g_tick_size=_Point;

   double requested=MathMax(g_tick_size,InpPriceStepPoints*_Point);
   double max_bar_range=0.0;
   double global_low =DBL_MAX;
   double global_high=-DBL_MAX;

   for(int b=0;b<g_bar_count;b++)
     {
      double range=g_rates[b].high-g_rates[b].low;
      if(range>max_bar_range) max_bar_range=range;
      if(g_rates[b].low<global_low) global_low=g_rates[b].low;
      if(g_rates[b].high>global_high) global_high=g_rates[b].high;
     }

   int max_levels=ClampInt(InpMaxLevelsPerBar,20,OF_MAX_LEVELS-2);
   double by_bar=max_bar_range/MathMax(1,max_levels-2);
   double by_profile=(global_high-global_low)/MathMax(1,OF_MAX_PROFILE_LEVELS-4);
   double raw=MathMax(requested,MathMax(by_bar,by_profile));
   double steps=MathCeil(raw/g_tick_size-OF_EPSILON);
   if(steps<1.0) steps=1.0;
   return NormalizeDouble(steps*g_tick_size,_Digits);
  }

//+------------------------------------------------------------------+
//| Tick price and weight                                            |
//+------------------------------------------------------------------+
double TickReferencePrice(const MqlTick &tick)
  {
   // Use Last only for an actual trade/Last update. MqlTick keeps previous
   // field values on quote-only updates, so blindly using Last can freeze
   // the tick-rule classifier on OTC feeds.
   bool last_changed=((tick.flags&TICK_FLAG_LAST)==TICK_FLAG_LAST);
   bool direct_side =((tick.flags&TICK_FLAG_BUY)==TICK_FLAG_BUY ||
                      (tick.flags&TICK_FLAG_SELL)==TICK_FLAG_SELL);
   if(tick.last>0.0 && (last_changed || direct_side)) return tick.last;
   // MT5 OTC chart bars are normally built from Bid, so Bid keeps the
   // footprint buckets aligned with the visible candle high/low.
   if(tick.bid>0.0) return tick.bid;
   if(tick.ask>0.0) return tick.ask;
   return tick.last;
  }

double TickWeight(const MqlTick &tick,const bool is_direct_trade)
  {
   if(!InpUseRealVolume) return 1.0;
   if(is_direct_trade)
     {
      if(tick.volume_real>0.0) return tick.volume_real;
      if(tick.volume>0) return (double)tick.volume;
     }
   return 1.0;
  }

//+------------------------------------------------------------------+
//| Load bars and tick history                                       |
//+------------------------------------------------------------------+
bool LoadAndAggregate()
  {
   ResetData();
   int requested_bars=ClampInt(InpHistoryBars,8,OF_MAX_BARS);

   MqlRates temp[];
   ResetLastError();
   int copied=CopyRates(_Symbol,_Period,0,requested_bars,temp);
   if(copied<8)
     {
      g_data_status=StringFormat("WAITING FOR BAR HISTORY (%d)",copied);
      return false;
     }

   // CopyRates places the oldest copied element at physical index zero.
   datetime now=TimeCurrent();
   datetime min_time=now-ClampInt(InpMaxTickLookbackHours,1,72)*3600;
   int first=0;
   while(first<copied-8 && temp[first].time<min_time)
      first++;

   g_bar_count=MathMin(copied-first,OF_MAX_BARS);
   for(int i=0;i<g_bar_count;i++)
      g_rates[i]=temp[first+i];

   g_session_start=CurrentSessionStart(now);
   g_step=CalculateEffectiveStep();
   if(g_step<=0.0)
     {
      g_data_status="INVALID PRICE STEP";
      return false;
     }

   // initialize bar bucket ranges
   for(int b=0;b<g_bar_count;b++)
     {
      long low_bucket =(long)MathFloor(g_rates[b].low/g_step+OF_EPSILON);
      long high_bucket=(long)MathFloor(g_rates[b].high/g_step+OF_EPSILON);
      if(high_bucket<low_bucket)
        {
         long swap=low_bucket;
         low_bucket=high_bucket;
         high_bucket=swap;
        }
      g_base_bucket[b]=low_bucket;
      long level_span=high_bucket-low_bucket+1;
      if(level_span>OF_MAX_LEVELS) level_span=OF_MAX_LEVELS;
      g_level_count[b]=(int)level_span;
     }

   datetime tick_from_time=g_rates[0].time;
   if(tick_from_time<min_time) tick_from_time=min_time;
   ulong from_msc=(ulong)tick_from_time*1000;
   ulong to_msc=(ulong)TimeCurrent()*1000+999;
   MqlTick ticks[];
   ResetLastError();
   int tick_count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,from_msc,to_msc);
   if(tick_count<=0)
     {
      g_data_status=StringFormat("WAITING FOR TICK HISTORY (%d / err %d)",tick_count,GetLastError());
      return false;
     }

   int direct_candidates=0;
   for(int scan=0;scan<tick_count;scan++)
     {
      bool buy_side =((ticks[scan].flags&TICK_FLAG_BUY)==TICK_FLAG_BUY);
      bool sell_side=((ticks[scan].flags&TICK_FLAG_SELL)==TICK_FLAG_SELL);
      if(buy_side || sell_side) direct_candidates++;
     }
   // In AUTO mode, use exchange-side trades exclusively when the feed
   // supplies a meaningful number of BUY/SELL flags. This avoids mixing
   // quote updates with true trade prints.
   bool auto_uses_direct=(InpClassification==OF_CLASSIFY_AUTO &&
                          direct_candidates>=10 &&
                          direct_candidates>=(int)MathMax(10.0,tick_count*0.001));

   int bar_index=0;
   double previous_price=0.0;
   int last_side=0;

   for(int t=0;t<tick_count;t++)
     {
      long tick_sec=(long)(ticks[t].time_msc/1000);
      while(bar_index<g_bar_count-1 && tick_sec>=(long)g_rates[bar_index+1].time)
         bar_index++;
      if(bar_index<0 || bar_index>=g_bar_count) continue;
      if(tick_sec<(long)g_rates[bar_index].time) continue;

      double price=TickReferencePrice(ticks[t]);
      if(price<=0.0) continue;

      bool buy_flag =((ticks[t].flags&TICK_FLAG_BUY)==TICK_FLAG_BUY);
      bool sell_flag=((ticks[t].flags&TICK_FLAG_SELL)==TICK_FLAG_SELL);
      bool has_direct=(buy_flag || sell_flag);
      int side=0;

      if(InpClassification==OF_CLASSIFY_EXCHANGE_FLAGS || auto_uses_direct)
        {
         if(!has_direct) continue;
         side=buy_flag ? 1 : -1;
         g_direct_flag_ticks++;
        }
      else
        {
         double epsilon=MathMax(g_tick_size,_Point)*0.10;
         if(previous_price>0.0)
           {
            if(price>previous_price+epsilon) side=1;
            else if(price<previous_price-epsilon) side=-1;
            else side=last_side;
           }
         if(side==0)
            side=(price>=g_rates[bar_index].open ? 1 : -1);
         g_proxy_ticks++;
        }

      previous_price=price;
      last_side=side;

      long bucket=(long)MathFloor(price/g_step+OF_EPSILON);
      int level=(int)(bucket-g_base_bucket[bar_index]);
      if(level<0 || level>=g_level_count[bar_index] || level>=OF_MAX_LEVELS)
         continue;

      double weight=TickWeight(ticks[t],has_direct);
      if(side>0) g_buy[bar_index][level]+=weight;
      else       g_sell[bar_index][level]+=weight;
      g_processed_ticks++;
     }

   if(g_processed_ticks<=0)
     {
      g_data_status="NO USABLE TICKS IN SELECTED MODE";
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Footprint statistics                                             |
//+------------------------------------------------------------------+
void CalculateFootprintStatistics()
  {
   double running_cvd=0.0;

   for(int b=0;b<g_bar_count;b++)
     {
      double max_level_volume=-1.0;
      int max_level=-1;
      double buy_total=0.0;
      double sell_total=0.0;

      for(int l=0;l<g_level_count[b];l++)
        {
         double bv=g_buy[b][l];
         double sv=g_sell[b][l];
         double tv=bv+sv;
         buy_total+=bv;
         sell_total+=sv;
         if(tv>max_level_volume)
           {
            max_level_volume=tv;
            max_level=l;
           }
        }

      g_total_volume[b]=buy_total+sell_total;
      g_delta[b]=buy_total-sell_total;
      g_buy_pressure[b]=(g_total_volume[b]>0.0 ? 100.0*buy_total/g_total_volume[b] : 50.0);
      g_bar_poc_level[b]=max_level;

      if(g_rates[b].time>=g_session_start)
         running_cvd+=g_delta[b];
      else
         running_cvd=0.0;
      g_cvd[b]=running_cvd;

      int consecutive_buy=0;
      int consecutive_sell=0;
      int max_consecutive_buy=0;
      int max_consecutive_sell=0;

      for(int l=0;l<g_level_count[b];l++)
        {
         double buy_base=0.0;
         double sell_base=0.0;

         if(InpDiagonalImbalance)
           {
            if(l>0) buy_base=g_sell[b][l-1];
            if(l+1<g_level_count[b]) sell_base=g_buy[b][l+1];
           }
         else
           {
            buy_base=g_sell[b][l];
            sell_base=g_buy[b][l];
           }

         double min_volume=MathMax(0.0,InpMinImbalanceVolume);
         double ratio=MathMax(1.1,InpImbalanceRatio);

         if(g_buy[b][l]>=min_volume && g_buy[b][l]>=buy_base*ratio &&
            (buy_base>0.0 || g_buy[b][l]>=min_volume*ratio))
            g_buy_imb[b][l]=true;

         if(g_sell[b][l]>=min_volume && g_sell[b][l]>=sell_base*ratio &&
            (sell_base>0.0 || g_sell[b][l]>=min_volume*ratio))
            g_sell_imb[b][l]=true;

         if(g_buy_imb[b][l]) consecutive_buy++; else consecutive_buy=0;
         if(g_sell_imb[b][l]) consecutive_sell++; else consecutive_sell=0;
         if(consecutive_buy>max_consecutive_buy) max_consecutive_buy=consecutive_buy;
         if(consecutive_sell>max_consecutive_sell) max_consecutive_sell=consecutive_sell;
        }

      int stack_required=ClampInt(InpStackedLevels,2,10);
      g_buy_stacked[b]=(max_consecutive_buy>=stack_required);
      g_sell_stacked[b]=(max_consecutive_sell>=stack_required);
     }
  }

//+------------------------------------------------------------------+
//| Absorption and exhaustion proxies                                |
//+------------------------------------------------------------------+
void CalculateAbsorptionAndExhaustion()
  {
   int lookback=ClampInt(InpVolumeAverageLookback,3,30);
   double pressure=ClampDouble(InpAbsorptionPressurePct,51.0,95.0);
   double close_frac=ClampDouble(InpAbsorptionCloseFrac,0.20,0.80);

   for(int b=0;b<g_bar_count;b++)
     {
      int start=MathMax(0,b-lookback);
      double sum=0.0;
      int count=0;
      for(int j=start;j<b;j++)
        {
         if(g_total_volume[j]>0.0)
           {
            sum+=g_total_volume[j];
            count++;
           }
        }
      double avg=(count>0 ? sum/count : g_total_volume[b]);
      double range=g_rates[b].high-g_rates[b].low;
      if(range<=0.0 || g_total_volume[b]<=0.0) continue;

      double close_location=(g_rates[b].close-g_rates[b].low)/range;
      bool high_volume=(avg>0.0 && g_total_volume[b]>=avg*MathMax(1.0,InpAbsorptionVolumeFactor));
      double sell_pressure=100.0-g_buy_pressure[b];

      // Buy absorption: aggressive selling, elevated activity, close rejects the low.
      g_buy_absorption[b]=(high_volume && sell_pressure>=pressure && close_location>=close_frac);
      // Sell absorption: aggressive buying, elevated activity, close rejects the high.
      g_sell_absorption[b]=(high_volume && g_buy_pressure[b]>=pressure && close_location<=1.0-close_frac);

      // Exhaustion proxy: very light terminal volume at the extreme plus rejection.
      int edge=MathMin(2,g_level_count[b]);
      double bottom=0.0,top=0.0;
      for(int k=0;k<edge;k++)
        {
         bottom+=g_buy[b][k]+g_sell[b][k];
         int upper=g_level_count[b]-1-k;
         if(upper>=0) top+=g_buy[b][upper]+g_sell[b][upper];
        }
      double avg_level=g_total_volume[b]/MathMax(1,g_level_count[b]);
      g_buy_exhaustion[b]=(bottom<avg_level*0.65*edge && close_location>0.55);
      g_sell_exhaustion[b]=(top<avg_level*0.65*edge && close_location<0.45);
     }
  }

//+------------------------------------------------------------------+
//| Liquidity sweeps                                                 |
//+------------------------------------------------------------------+
void CalculateLiquiditySweeps()
  {
   int lookback=ClampInt(InpLiquidityLookback,3,40);
   double tolerance=InpSweepTolerancePoints*_Point;

   for(int b=lookback;b<g_bar_count;b++)
     {
      double previous_high=-DBL_MAX;
      double previous_low=DBL_MAX;
      for(int j=b-lookback;j<b;j++)
        {
         if(g_rates[j].high>previous_high) previous_high=g_rates[j].high;
         if(g_rates[j].low<previous_low) previous_low=g_rates[j].low;
        }
      g_sweep_high[b]=(g_rates[b].high>previous_high+tolerance && g_rates[b].close<previous_high);
      g_sweep_low[b]=(g_rates[b].low<previous_low-tolerance && g_rates[b].close>previous_low);
     }
  }

//+------------------------------------------------------------------+
//| Market structure and CVD divergence                              |
//+------------------------------------------------------------------+
bool IsPivotHigh(const int center,const int length)
  {
   if(center-length<0 || center+length>=g_bar_count) return false;
   double value=g_rates[center].high;
   for(int i=center-length;i<=center+length;i++)
     {
      if(i==center) continue;
      if(g_rates[i].high>=value) return false;
     }
   return true;
  }

bool IsPivotLow(const int center,const int length)
  {
   if(center-length<0 || center+length>=g_bar_count) return false;
   double value=g_rates[center].low;
   for(int i=center-length;i<=center+length;i++)
     {
      if(i==center) continue;
      if(g_rates[i].low<=value) return false;
     }
   return true;
  }

void CalculateStructureAndDivergence()
  {
   int p=ClampInt(InpPivotLength,2,8);
   double last_swing_high=0.0;
   double last_swing_low=0.0;
   int last_swing_high_index=-1;
   int last_swing_low_index=-1;
   double previous_pivot_high=0.0;
   double previous_pivot_high_cvd=0.0;
   int previous_pivot_high_index=-1;
   double previous_pivot_low=0.0;
   double previous_pivot_low_cvd=0.0;
   int previous_pivot_low_index=-1;
   int trend=0;

   for(int b=0;b<g_bar_count;b++)
     {
      int confirmed_center=b-p;
      if(confirmed_center>=p)
        {
         if(IsPivotHigh(confirmed_center,p))
           {
            if(previous_pivot_high_index>=0 &&
               g_rates[confirmed_center].high>previous_pivot_high &&
               g_cvd[confirmed_center]<previous_pivot_high_cvd)
               g_bear_divergence[confirmed_center]=true;

            previous_pivot_high=g_rates[confirmed_center].high;
            previous_pivot_high_cvd=g_cvd[confirmed_center];
            previous_pivot_high_index=confirmed_center;
            last_swing_high=previous_pivot_high;
            last_swing_high_index=confirmed_center;
           }

         if(IsPivotLow(confirmed_center,p))
           {
            if(previous_pivot_low_index>=0 &&
               g_rates[confirmed_center].low<previous_pivot_low &&
               g_cvd[confirmed_center]>previous_pivot_low_cvd)
               g_bull_divergence[confirmed_center]=true;

            previous_pivot_low=g_rates[confirmed_center].low;
            previous_pivot_low_cvd=g_cvd[confirmed_center];
            previous_pivot_low_index=confirmed_center;
            last_swing_low=previous_pivot_low;
            last_swing_low_index=confirmed_center;
           }
        }

      double previous_close=(b>0 ? g_rates[b-1].close : g_rates[b].open);
      if(last_swing_high_index>=0 && b>last_swing_high_index &&
         g_rates[b].close>last_swing_high && previous_close<=last_swing_high)
        {
         if(trend<0) g_choch_bull[b]=true;
         else        g_bos_bull[b]=true;
         trend=1;
        }
      if(last_swing_low_index>=0 && b>last_swing_low_index &&
         g_rates[b].close<last_swing_low && previous_close>=last_swing_low)
        {
         if(trend>0) g_choch_bear[b]=true;
         else        g_bos_bear[b]=true;
         trend=-1;
        }
      g_structure_trend[b]=trend;
     }
  }

//+------------------------------------------------------------------+
//| Profile and value area                                           |
//+------------------------------------------------------------------+
void CalculateProfile()
  {
   long min_bucket=LONG_MAX;
   long max_bucket=LONG_MIN;

   for(int b=0;b<g_bar_count;b++)
     {
      if(g_rates[b].time<g_session_start) continue;
      if(g_level_count[b]<=0) continue;
      long lo=g_base_bucket[b];
      long hi=g_base_bucket[b]+g_level_count[b]-1;
      if(lo<min_bucket) min_bucket=lo;
      if(hi>max_bucket) max_bucket=hi;
     }

   if(min_bucket==LONG_MAX || max_bucket==LONG_MIN || max_bucket<min_bucket)
      return;

   g_profile_base_bucket=min_bucket;
   long profile_span=max_bucket-min_bucket+1;
   if(profile_span>OF_MAX_PROFILE_LEVELS) profile_span=OF_MAX_PROFILE_LEVELS;
   g_profile_levels=(int)profile_span;

   double total=0.0;
   g_session_delta=0.0;
   for(int b=0;b<g_bar_count;b++)
     {
      if(g_rates[b].time<g_session_start) continue;
      g_session_delta+=g_delta[b];
      for(int l=0;l<g_level_count[b];l++)
        {
         long bucket=g_base_bucket[b]+l;
         int p=(int)(bucket-g_profile_base_bucket);
         if(p<0 || p>=g_profile_levels) continue;
         double bv=g_buy[b][l];
         double sv=g_sell[b][l];
         g_profile_volume[p]+=bv+sv;
         g_profile_delta[p]+=bv-sv;
         total+=bv+sv;
        }
     }

   double max_volume=-1.0;
   for(int p=0;p<g_profile_levels;p++)
     {
      if(g_profile_volume[p]>max_volume)
        {
         max_volume=g_profile_volume[p];
         g_profile_poc_index=p;
        }
     }
   if(g_profile_poc_index<0 || total<=0.0) return;

   double target=total*ClampDouble(InpValueAreaPercent,50.0,95.0)/100.0;
   int low=g_profile_poc_index;
   int high=g_profile_poc_index;
   double accumulated=g_profile_volume[g_profile_poc_index];

   while(accumulated<target && (low>0 || high<g_profile_levels-1))
     {
      double next_low =(low>0 ? g_profile_volume[low-1] : -1.0);
      double next_high=(high<g_profile_levels-1 ? g_profile_volume[high+1] : -1.0);
      if(next_high>next_low)
        {
         high++;
         accumulated+=MathMax(0.0,next_high);
        }
      else if(next_low>next_high)
        {
         low--;
         accumulated+=MathMax(0.0,next_low);
        }
      else
        {
         if(low>0)
           {
            low--;
            accumulated+=MathMax(0.0,next_low);
           }
         if(accumulated<target && high<g_profile_levels-1)
           {
            high++;
            accumulated+=MathMax(0.0,next_high);
           }
        }
     }

   g_profile_val_index=low;
   g_profile_vah_index=high;
   g_profile_poc_price=NormalizeDouble((g_profile_base_bucket+g_profile_poc_index)*g_step,_Digits);
   g_profile_val_price=NormalizeDouble((g_profile_base_bucket+g_profile_val_index)*g_step,_Digits);
   g_profile_vah_price=NormalizeDouble((g_profile_base_bucket+g_profile_vah_index+1)*g_step,_Digits);

   // Secondary high-volume node and a local low-volume node. POC is already
   // the primary HVN, so the secondary HVN excludes the POC bucket.
   int hvn=-1;
   double hvn_volume=-1.0;
   int lvn=-1;
   double lvn_volume=DBL_MAX;
   for(int n=1;n<g_profile_levels-1;n++)
     {
      double current=g_profile_volume[n];
      if(n!=g_profile_poc_index && current>g_profile_volume[n-1] &&
         current>=g_profile_volume[n+1] && current>hvn_volume)
        {
         hvn=n;
         hvn_volume=current;
        }
      if(current>0.0 && g_profile_volume[n-1]>0.0 && g_profile_volume[n+1]>0.0 &&
         current<g_profile_volume[n-1] && current<=g_profile_volume[n+1] &&
         current<lvn_volume)
        {
         lvn=n;
         lvn_volume=current;
        }
     }
   if(hvn>=0) g_profile_hvn_price=NormalizeDouble((g_profile_base_bucket+hvn)*g_step,_Digits);
   if(lvn>=0) g_profile_lvn_price=NormalizeDouble((g_profile_base_bucket+lvn)*g_step,_Digits);
  }

//+------------------------------------------------------------------+
//| Confluence scoring                                               |
//+------------------------------------------------------------------+
bool RecentBullDivergence(const int bar)
  {
   int age=ClampInt(InpDivergenceMaxAgeBars,1,30);
   int start=MathMax(0,bar-age);
   for(int i=start;i<=bar;i++) if(g_bull_divergence[i]) return true;
   return false;
  }

bool RecentBearDivergence(const int bar)
  {
   int age=ClampInt(InpDivergenceMaxAgeBars,1,30);
   int start=MathMax(0,bar-age);
   for(int i=start;i<=bar;i++) if(g_bear_divergence[i]) return true;
   return false;
  }

void CalculateScores()
  {
   for(int b=0;b<g_bar_count;b++)
     {
      int bull=0,bear=0;
      if(g_sweep_low[b]) bull++;
      if(g_sweep_high[b]) bear++;
      if(g_buy_absorption[b]) bull++;
      if(g_sell_absorption[b]) bear++;
      if(g_buy_exhaustion[b] && g_sweep_low[b]) bull++;
      if(g_sell_exhaustion[b] && g_sweep_high[b]) bear++;
      if(g_buy_stacked[b]) bull++;
      if(g_sell_stacked[b]) bear++;
      if(RecentBullDivergence(b)) bull++;
      if(RecentBearDivergence(b)) bear++;
      if(g_choch_bull[b] || g_bos_bull[b]) bull++;
      if(g_choch_bear[b] || g_bos_bear[b]) bear++;
      if(g_structure_trend[b]>0) bull++;
      if(g_structure_trend[b]<0) bear++;
      if(g_delta[b]>0.0 && b>0 && g_cvd[b]>=g_cvd[b-1]) bull++;
      if(g_delta[b]<0.0 && b>0 && g_cvd[b]<=g_cvd[b-1]) bear++;
      g_bull_score[b]=bull;
      g_bear_score[b]=bear;
     }
  }

//+------------------------------------------------------------------+
//| Build all calculations                                           |
//+------------------------------------------------------------------+
bool RebuildData()
  {
   if(!LoadAndAggregate()) return false;
   CalculateFootprintStatistics();
   CalculateAbsorptionAndExhaustion();
   CalculateLiquiditySweeps();
   CalculateStructureAndDivergence();
   CalculateProfile();
   CalculateScores();

   string mode="TICK RULE PROXY";
   if(g_direct_flag_ticks>0 && g_proxy_ticks==0) mode="EXCHANGE SIDE FLAGS";

   g_data_status=StringFormat("OK | %s | ticks %d | step %s",
                              mode,g_processed_ticks,DoubleToString(g_step,_Digits));
   return true;
  }

//+------------------------------------------------------------------+
//| Price-to-pixel helper                                            |
//+------------------------------------------------------------------+
bool PriceToY(const double price,int &y)
  {
   int x=0;
   datetime t=(g_bar_count>0 ? g_rates[g_bar_count-1].time : TimeCurrent());
   return ChartTimePriceToXY(0,0,t,price,x,y);
  }

bool TimePriceToXY(const datetime time,const double price,int &x,int &y)
  {
   return ChartTimePriceToXY(0,0,time,price,x,y);
  }

//+------------------------------------------------------------------+
//| Draw profile and reference levels                                |
//+------------------------------------------------------------------+
void DrawProfile()
  {
   if(!InpShowVolumeProfile || g_profile_levels<=0 || g_profile_poc_index<0) return;

   int panel_width=ClampInt(InpProfilePanelWidth,140,MathMax(140,g_canvas_width/3));
   int x2=g_canvas_width-4;
   int x1=MathMax(4,x2-panel_width);
   DrawPanel(x1,4,x2,g_canvas_height-4,205);

   g_canvas.FontSet("Arial",InpFontSize+1,FW_BOLD);
   DrawText(x1+8,9,"SESSION PROFILE + DELTA",InpTextColor);
   g_canvas.FontSet("Consolas",MathMax(8,InpFontSize-1));

   double max_volume=0.0;
   for(int p=0;p<g_profile_levels;p++)
      if(g_profile_volume[p]>max_volume) max_volume=g_profile_volume[p];
   if(max_volume<=0.0) return;

   int header=34;
   int usable_width=panel_width-74;
   int text_x=x2-68;

   for(int p=0;p<g_profile_levels;p++)
     {
      if(g_profile_volume[p]<=0.0) continue;
      double price=(g_profile_base_bucket+p)*g_step;
      int y_mid=0,y_top=0,y_bottom=0;
      if(!PriceToY(price,y_mid)) continue;
      PriceToY(price+g_step*0.5,y_top);
      PriceToY(price-g_step*0.5,y_bottom);
      int top=MathMin(y_top,y_bottom);
      int bottom=MathMax(y_top,y_bottom);
      if(bottom<4 || top>g_canvas_height-4) continue;
      top=MathMax(top,header);
      bottom=MathMin(bottom,g_canvas_height-5);
      if(bottom<=top) continue;

      int width=(int)MathRound(usable_width*g_profile_volume[p]/max_volume);
      color bar_color=(g_profile_delta[p]>=0.0 ? InpBuyColor : InpSellColor);
      uchar alpha=(p==g_profile_poc_index ? 225 : 150);
      g_canvas.FillRectangle(x1+4,top,x1+4+width,bottom,ARGB(bar_color,alpha));

      if(p==g_profile_poc_index)
         g_canvas.Rectangle(x1+3,top,x2-3,bottom,ARGB(InpPOCColor,255));

      if(bottom-top>=9)
        {
         DrawText(text_x,top,StringFormat("%s",FormatVolume(g_profile_delta[p])),
                  g_profile_delta[p]>=0.0 ? InpBuyColor : InpSellColor);
        }
     }

   // labels and reference lines
   if(InpShowPOC_VAH_VAL_Lines)
     {
      int y=0;
      if(PriceToY(g_profile_poc_price,y))
        {
         DrawHLine(y,0,x1,InpPOCColor,210,7);
         g_canvas.FillRectangle(3,y-10,112,y+9,ARGB(InpPOCColor,220));
         DrawText(7,y-8,"POC "+DoubleToString(g_profile_poc_price,_Digits),clrBlack);
        }
      if(PriceToY(g_profile_vah_price,y))
        {
         DrawHLine(y,0,x1,InpVAColor,170,6);
         DrawText(5,y-14,"VAH "+DoubleToString(g_profile_vah_price,_Digits),InpVAColor);
        }
      if(PriceToY(g_profile_val_price,y))
        {
         DrawHLine(y,0,x1,InpVAColor,170,6);
         DrawText(5,y+2,"VAL "+DoubleToString(g_profile_val_price,_Digits),InpVAColor);
        }
      if(InpShowHVN_LVN && g_profile_hvn_price>0.0 && PriceToY(g_profile_hvn_price,y))
        {
         DrawHLine(y,0,x1,InpPOCColor,110,4);
         DrawText(x1+6,y-11,"HVN",InpPOCColor);
        }
      if(InpShowHVN_LVN && g_profile_lvn_price>0.0 && PriceToY(g_profile_lvn_price,y))
        {
         DrawHLine(y,0,x1,InpNeutralColor,95,3);
         DrawText(x1+6,y-11,"LVN",InpNeutralColor);
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw footprint cells                                             |
//+------------------------------------------------------------------+
void DrawFootprint()
  {
   if(!InpShowFootprint || g_bar_count<=0) return;
   int footprint_bars=ClampInt(InpFootprintBars,3,MathMin(OF_MAX_BARS,g_bar_count));
   int first=MathMax(0,g_bar_count-footprint_bars);
   int profile_width=(InpShowVolumeProfile ? ClampInt(InpProfilePanelWidth,140,MathMax(140,g_canvas_width/3)) : 0);
   int right_limit=g_canvas_width-profile_width-6;

   g_canvas.FontSet("Consolas",MathMax(7,InpFontSize-2));

   for(int b=first;b<g_bar_count;b++)
     {
      int x=0,y=0;
      if(!TimePriceToXY(g_rates[b].time,g_rates[b].close,x,y)) continue;
      if(x<-100 || x>right_limit+100) continue;

      int x_next=x+40;
      if(b+1<g_bar_count)
        {
         int temp_y=0;
         TimePriceToXY(g_rates[b+1].time,g_rates[b+1].close,x_next,temp_y);
        }
      else
        {
         datetime next_time=g_rates[b].time+(datetime)PeriodSeconds(_Period);
         int temp_y=0;
         TimePriceToXY(next_time,g_rates[b].close,x_next,temp_y);
        }

      int spacing=MathAbs(x_next-x);
      if(spacing<InpMinBarWidthPx) continue;
      int cell_width=ClampInt((int)(spacing*0.88),InpMinBarWidthPx,92);
      int left=x-cell_width/2;
      int mid=x;
      int right=x+cell_width/2;
      if(right<0 || left>right_limit) continue;

      double max_side=0.0;
      for(int l=0;l<g_level_count[b];l++)
        {
         if(g_buy[b][l]>max_side) max_side=g_buy[b][l];
         if(g_sell[b][l]>max_side) max_side=g_sell[b][l];
        }
      if(max_side<=0.0) continue;

      for(int l=0;l<g_level_count[b];l++)
        {
         double price=(g_base_bucket[b]+l)*g_step;
         int y_top=0,y_bottom=0;
         if(!PriceToY(price+g_step*0.5,y_top)) continue;
         if(!PriceToY(price-g_step*0.5,y_bottom)) continue;
         int top=MathMin(y_top,y_bottom);
         int bottom=MathMax(y_top,y_bottom);
         if(bottom<0 || top>g_canvas_height) continue;
         top=MathMax(0,top);
         bottom=MathMin(g_canvas_height-1,bottom);
         int h=bottom-top;
         if(h<2) continue;

         double bv=g_buy[b][l];
         double sv=g_sell[b][l];
         uchar buy_alpha =(uchar)ClampInt(45+(int)(175*bv/max_side),45,220);
         uchar sell_alpha=(uchar)ClampInt(45+(int)(175*sv/max_side),45,220);

         g_canvas.FillRectangle(left,top,mid,bottom,ARGB(InpSellColor,sell_alpha));
         g_canvas.FillRectangle(mid,top,right,bottom,ARGB(InpBuyColor,buy_alpha));
         g_canvas.Rectangle(left,top,right,bottom,ARGB(C'85,92,105',140));

         if(g_sell_imb[b][l])
            g_canvas.Rectangle(left,top,mid,bottom,ARGB(InpBearSignalColor,255));
         if(g_buy_imb[b][l])
            g_canvas.Rectangle(mid,top,right,bottom,ARGB(InpBullSignalColor,255));
         if(InpShowBarPOC && l==g_bar_poc_level[b])
            g_canvas.Rectangle(left-1,top-1,right+1,bottom+1,ARGB(InpPOCColor,255));

         if(h>=InpMinCellHeightPx)
           {
            int text_y=top+MathMax(0,(h-(InpFontSize+1))/2);
            DrawText(mid-2,text_y,FormatVolume(sv),InpTextColor,2);
            DrawText(mid+2,text_y,FormatVolume(bv),InpTextColor,0);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw CVD and Delta mini panels                                   |
//+------------------------------------------------------------------+
void DrawLowerPanels()
  {
   if((!InpShowCVDPanel && !InpShowDeltaPanel) || g_bar_count<3) return;

   int profile_width=(InpShowVolumeProfile ? ClampInt(InpProfilePanelWidth,140,MathMax(140,g_canvas_width/3)) : 0);
   int x1=5;
   int x2=g_canvas_width-profile_width-8;
   if(x2-x1<300) return;

   int total_height=ClampInt(InpLowerPanelHeight,90,240);
   int y2=g_canvas_height-5;
   int y1=MathMax(40,y2-total_height);
   int gap=3;
   int cvd_height=InpShowCVDPanel ? (InpShowDeltaPanel ? (total_height*2)/3 : total_height) : 0;
   int delta_height=InpShowDeltaPanel ? total_height-cvd_height-gap : 0;

   int first=MathMax(0,g_bar_count-40);
   int last=g_bar_count-1;

   if(InpShowCVDPanel)
     {
      int cy1=y1;
      int cy2=y1+cvd_height;
      DrawPanel(x1,cy1,x2,cy2,205);
      g_canvas.FontSet("Arial",MathMax(8,InpFontSize-1),FW_BOLD);
      DrawText(x1+7,cy1+5,"CVD (SESSION)",InpTextColor);

      double min_cvd=DBL_MAX,max_cvd=-DBL_MAX;
      for(int b=first;b<=last;b++)
        {
         if(g_cvd[b]<min_cvd) min_cvd=g_cvd[b];
         if(g_cvd[b]>max_cvd) max_cvd=g_cvd[b];
        }
      if(MathAbs(max_cvd-min_cvd)<OF_EPSILON)
        {
         max_cvd+=1.0;
         min_cvd-=1.0;
        }
      int px_prev=0,py_prev=0;
      bool have_prev=false;
      for(int b=first;b<=last;b++)
        {
         int x=0,dummy=0;
         if(!TimePriceToXY(g_rates[b].time,g_rates[b].close,x,dummy)) continue;
         int y=cy2-8-(int)((cy2-cy1-26)*(g_cvd[b]-min_cvd)/(max_cvd-min_cvd));
         if(have_prev)
            g_canvas.Line(px_prev,py_prev,x,y,ARGB(g_cvd[b]>=g_cvd[MathMax(first,b-1)] ? InpBuyColor : InpSellColor,240));
         px_prev=x;
         py_prev=y;
         have_prev=true;
        }
      DrawText(x2-8,cy1+5,FormatVolume(g_cvd[last]),g_cvd[last]>=0.0 ? InpBuyColor : InpSellColor,2);
     }

   if(InpShowDeltaPanel)
     {
      int dy1=y1+cvd_height+gap;
      int dy2=y2;
      DrawPanel(x1,dy1,x2,dy2,205);
      g_canvas.FontSet("Arial",MathMax(8,InpFontSize-1),FW_BOLD);
      DrawText(x1+7,dy1+4,"BAR DELTA",InpTextColor);
      int zero=(dy1+dy2)/2;
      DrawHLine(zero,x1+2,x2-2,InpNeutralColor,100);

      double max_abs=0.0;
      for(int b=first;b<=last;b++) if(MathAbs(g_delta[b])>max_abs) max_abs=MathAbs(g_delta[b]);
      if(max_abs<=0.0) max_abs=1.0;
      for(int b=first;b<=last;b++)
        {
         int x=0,dummy=0;
         if(!TimePriceToXY(g_rates[b].time,g_rates[b].close,x,dummy)) continue;
         int bar_w=3;
         int h=(int)((delta_height/2-10)*MathAbs(g_delta[b])/max_abs);
         if(g_delta[b]>=0.0)
            g_canvas.FillRectangle(x-bar_w,zero-h,x+bar_w,zero,ARGB(InpBuyColor,210));
         else
            g_canvas.FillRectangle(x-bar_w,zero,x+bar_w,zero+h,ARGB(InpSellColor,210));
        }
      DrawText(x2-8,dy1+4,FormatVolume(g_delta[last]),g_delta[last]>=0.0 ? InpBuyColor : InpSellColor,2);
     }
  }

//+------------------------------------------------------------------+
//| Draw signal markers                                              |
//+------------------------------------------------------------------+
void DrawMarkers()
  {
   if(!InpShowSignalMarkers || g_bar_count<2) return;
   int first=MathMax(0,g_bar_count-20);
   int profile_width=(InpShowVolumeProfile ? ClampInt(InpProfilePanelWidth,140,MathMax(140,g_canvas_width/3)) : 0);
   int right_limit=g_canvas_width-profile_width-5;
   g_canvas.FontSet("Arial",MathMax(8,InpFontSize-1),FW_BOLD);

   for(int b=first;b<g_bar_count;b++)
     {
      int x=0,y=0;
      if(!TimePriceToXY(g_rates[b].time,g_rates[b].low,x,y)) continue;
      if(x<0 || x>right_limit) continue;
      int y_low=y+4;
      int y_high=0,temp_x=0;
      TimePriceToXY(g_rates[b].time,g_rates[b].high,temp_x,y_high);

      if(g_sweep_low[b]) DrawText(x,y_low,"SWEEP L",InpBullSignalColor,1);
      if(g_buy_absorption[b]) DrawText(x,y_low+13,"BUY ABS",InpBullSignalColor,1);
      else if(g_buy_exhaustion[b]) DrawText(x,y_low+13,"BUY EXH",InpBullSignalColor,1);
      if(g_bull_divergence[b]) DrawText(x,y_low+26,"BULL DIV",clrViolet,1);
      if(g_choch_bull[b]) DrawText(x,y_low+39,"CHOCH +",InpBullSignalColor,1);
      else if(g_bos_bull[b]) DrawText(x,y_low+39,"BOS +",InpBullSignalColor,1);

      if(g_sweep_high[b]) DrawText(x,y_high-14,"SWEEP H",InpBearSignalColor,1);
      if(g_sell_absorption[b]) DrawText(x,y_high-27,"SELL ABS",InpBearSignalColor,1);
      else if(g_sell_exhaustion[b]) DrawText(x,y_high-27,"SELL EXH",InpBearSignalColor,1);
      if(g_bear_divergence[b]) DrawText(x,y_high-40,"BEAR DIV",clrViolet,1);
      if(g_choch_bear[b]) DrawText(x,y_high-53,"CHOCH -",InpBearSignalColor,1);
      else if(g_bos_bear[b]) DrawText(x,y_high-53,"BOS -",InpBearSignalColor,1);
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DashboardRow(const int x,const int y,const string label,const string value,const color value_color)
  {
   DrawText(x,y,label,InpNeutralColor);
   DrawText(x+InpDashboardWidth-20,y,value,value_color,2);
  }

void DrawDashboard()
  {
   if(!InpShowDashboard || g_bar_count<2) return;

   int profile_width=(InpShowVolumeProfile ? ClampInt(InpProfilePanelWidth,140,MathMax(140,g_canvas_width/3)) : 0);
   int width=ClampInt(InpDashboardWidth,220,340);
   int x=8;
   if(InpDashboardCorner==OF_PANEL_TOP_RIGHT)
      x=MathMax(8,g_canvas_width-profile_width-width-12);
   int y=8;
   int height=352;
   DrawPanel(x,y,x+width,y+height,232);

   int signal_bar=(InpAlertOnClosedBarOnly && g_bar_count>=2 ? g_bar_count-2 : g_bar_count-1);
   int live_bar=g_bar_count-1;
   string bias=BiasText(g_bull_score[signal_bar],g_bear_score[signal_bar]);
   color bias_color=BiasColor(g_bull_score[signal_bar],g_bear_score[signal_bar]);

   g_canvas.FontSet("Arial",InpFontSize+2,FW_BOLD);
   DrawText(x+10,y+8,"XAU ORDER FLOW FULL SYSTEM",InpPOCColor);
   g_canvas.FontSet("Arial",InpFontSize,FW_NORMAL);
   DrawText(x+10,y+29,_Symbol+"  "+EnumToString(_Period),InpTextColor);
   DrawText(x+width-10,y+29,DoubleToString(g_rates[live_bar].close,_Digits),InpTextColor,2);
   DrawHLine(y+48,x+8,x+width-8,InpPanelBorder,200);

   int row=y+57;
   DashboardRow(x+10,row,"Bar Delta",FormatVolume(g_delta[live_bar]),g_delta[live_bar]>=0.0 ? InpBuyColor : InpSellColor); row+=19;
   DashboardRow(x+10,row,"Session Delta",FormatVolume(g_session_delta),g_session_delta>=0.0 ? InpBuyColor : InpSellColor); row+=19;
   DashboardRow(x+10,row,"CVD",FormatVolume(g_cvd[live_bar]),g_cvd[live_bar]>=0.0 ? InpBuyColor : InpSellColor); row+=19;
   DashboardRow(x+10,row,"Buy Pressure",StringFormat("%.1f%%",g_buy_pressure[live_bar]),g_buy_pressure[live_bar]>=50.0 ? InpBuyColor : InpSellColor); row+=19;
   DashboardRow(x+10,row,"POC",g_profile_poc_index>=0 ? DoubleToString(g_profile_poc_price,_Digits) : "-",InpPOCColor); row+=19;
   DashboardRow(x+10,row,"VAH / VAL",g_profile_poc_index>=0 ? DoubleToString(g_profile_vah_price,_Digits)+" / "+DoubleToString(g_profile_val_price,_Digits) : "-",InpVAColor); row+=19;
   DashboardRow(x+10,row,"HVN / LVN",(g_profile_hvn_price>0.0 || g_profile_lvn_price>0.0) ? DoubleToString(g_profile_hvn_price,_Digits)+" / "+DoubleToString(g_profile_lvn_price,_Digits) : "-",InpPOCColor); row+=23;

   DrawHLine(row-5,x+8,x+width-8,InpPanelBorder,180);
   DashboardRow(x+10,row,"Liquidity",g_sweep_low[signal_bar] ? "LOW SWEEP" : (g_sweep_high[signal_bar] ? "HIGH SWEEP" : "-"),
                g_sweep_low[signal_bar] ? InpBuyColor : (g_sweep_high[signal_bar] ? InpSellColor : InpNeutralColor)); row+=19;
   string absorption_text="-";
   color absorption_color=InpNeutralColor;
   if(g_buy_absorption[signal_bar]) { absorption_text="BUY ABS"; absorption_color=InpBuyColor; }
   else if(g_sell_absorption[signal_bar]) { absorption_text="SELL ABS"; absorption_color=InpSellColor; }
   else if(g_buy_exhaustion[signal_bar]) { absorption_text="BUY EXH"; absorption_color=InpBuyColor; }
   else if(g_sell_exhaustion[signal_bar]) { absorption_text="SELL EXH"; absorption_color=InpSellColor; }
   DashboardRow(x+10,row,"Abs / Exhaust",absorption_text,absorption_color); row+=19;
   DashboardRow(x+10,row,"Stacked Imbalance",g_buy_stacked[signal_bar] ? "BUY" : (g_sell_stacked[signal_bar] ? "SELL" : "-"),
                g_buy_stacked[signal_bar] ? InpBuyColor : (g_sell_stacked[signal_bar] ? InpSellColor : InpNeutralColor)); row+=19;
   DashboardRow(x+10,row,"Divergence",RecentBullDivergence(signal_bar) ? "BULLISH" : (RecentBearDivergence(signal_bar) ? "BEARISH" : "-"),
                RecentBullDivergence(signal_bar) ? InpBuyColor : (RecentBearDivergence(signal_bar) ? InpSellColor : InpNeutralColor)); row+=19;
   string structure="RANGE";
   color structure_color=InpNeutralColor;
   if(g_choch_bull[signal_bar]) { structure="CHOCH +"; structure_color=InpBuyColor; }
   else if(g_choch_bear[signal_bar]) { structure="CHOCH -"; structure_color=InpSellColor; }
   else if(g_bos_bull[signal_bar]) { structure="BOS +"; structure_color=InpBuyColor; }
   else if(g_bos_bear[signal_bar]) { structure="BOS -"; structure_color=InpSellColor; }
   else if(g_structure_trend[signal_bar]>0) { structure="UP"; structure_color=InpBuyColor; }
   else if(g_structure_trend[signal_bar]<0) { structure="DOWN"; structure_color=InpSellColor; }
   DashboardRow(x+10,row,"Structure",structure,structure_color); row+=23;

   DrawHLine(row-5,x+8,x+width-8,InpPanelBorder,180);
   DashboardRow(x+10,row,"Bull / Bear score",StringFormat("%d / %d",g_bull_score[signal_bar],g_bear_score[signal_bar]),bias_color); row+=22;
   g_canvas.FontSet("Arial",InpFontSize+3,FW_BOLD);
   DrawText(x+width/2,row,bias,bias_color,1);
   g_canvas.FontSet("Arial",MathMax(8,InpFontSize-2),FW_NORMAL);
   DrawText(x+10,y+height-34,"Data: "+g_data_status,InpNeutralColor);
   DrawText(x+10,y+height-18,"OTC XAUUSD = order-flow proxy",InpWarningColor);
  }

//+------------------------------------------------------------------+
//| Status / warning overlay                                         |
//+------------------------------------------------------------------+
void DrawStatusMessage()
  {
   if(StringFind(g_data_status,"OK")>=0) return;
   int x=12,y=12,w=MathMin(600,g_canvas_width-24),h=68;
   DrawPanel(x,y,x+w,y+h,235);
   g_canvas.FontSet("Arial",InpFontSize+2,FW_BOLD);
   DrawText(x+12,y+10,"XAU ORDER FLOW: DATA NOT READY",InpWarningColor);
   g_canvas.FontSet("Arial",InpFontSize,FW_NORMAL);
   DrawText(x+12,y+36,g_data_status,InpTextColor);
  }

//+------------------------------------------------------------------+
//| Render                                                           |
//+------------------------------------------------------------------+
void Render()
  {
   if(!EnsureCanvas()) return;
   g_canvas.Erase(0x00000000);
   g_canvas.FontSet("Arial",InpFontSize,FW_NORMAL);

   if(StringFind(g_data_status,"OK")>=0)
     {
      DrawFootprint();
      DrawMarkers();
      DrawLowerPanels();
      DrawProfile();
      DrawDashboard();
     }
   else
      DrawStatusMessage();

   g_canvas.Update();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Alert logic                                                      |
//+------------------------------------------------------------------+
void CheckAlerts()
  {
   if(!InpEnableAlerts || g_bar_count<2) return;
   int b=(InpAlertOnClosedBarOnly ? g_bar_count-2 : g_bar_count-1);
   if(b<0) return;
   datetime bar_time=g_rates[b].time;
   if(g_first_refresh)
     {
      g_last_alert_bar=bar_time;
      return;
     }
   if(bar_time==g_last_alert_bar) return;

   string bias=BiasText(g_bull_score[b],g_bear_score[b]);
   if(bias=="WAIT / NEUTRAL") return;

   string message=StringFormat("%s %s Order Flow %s | Bull %d Bear %d | Delta %s",
                               _Symbol,EnumToString(_Period),bias,
                               g_bull_score[b],g_bear_score[b],FormatVolume(g_delta[b]));
   if(InpPopupAlert) Alert(message);
   if(InpSoundAlert) PlaySound(InpSoundFile);
   if(InpPushNotification) SendNotification(message);
   g_last_alert_bar=bar_time;
  }

//+------------------------------------------------------------------+
//| Main refresh                                                     |
//+------------------------------------------------------------------+
void RefreshSystem()
  {
   if(g_busy) return;
   g_busy=true;
   bool ok=RebuildData();
   Render();
   if(ok)
     {
      CheckAlerts();
      g_first_refresh=false;
     }
   g_busy=false;
  }

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,g_status_buffer,INDICATOR_DATA);
   ArraySetAsSeries(g_status_buffer,true);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU Order Flow Full System v1.0");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   EventSetTimer(ClampInt(InpRefreshSeconds,1,60));
   g_data_status="INITIALIZING TICK HISTORY";
   RefreshSystem();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_canvas_ready)
     {
      g_canvas.Destroy();
      ObjectDelete(0,g_canvas_name);
      g_canvas_ready=false;
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshSystem();
  }

//+------------------------------------------------------------------+
//| Chart event                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
     {
      g_need_redraw=true;
      Render();
      g_need_redraw=false;
     }
  }

//+------------------------------------------------------------------+
//| Indicator calculation event                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total>0)
     {
      int latest=MathMax(0,g_bar_count-1);
      g_status_buffer[0]=(double)(g_bar_count>0 ? g_bull_score[latest]-g_bear_score[latest] : 0);
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
