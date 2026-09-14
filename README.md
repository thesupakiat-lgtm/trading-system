# XAUUSD ML Diagnostic System V1

A research/backtest system for XAUUSD that focuses on **walk-forward validation and failure diagnosis**, not only win rate.

## What V1 does

- Reads OHLCV CSV (`timestamp, open, high, low, close, volume`)
- Builds causal technical/geometry features
- Includes COS30/COS45/COS60 swing-distance features
- Includes swing position, BOS/FVG approximations, ATR, RSI, trend, time-of-day features
- Uses a regime layer (Gaussian Mixture fallback in V1)
- Trains LightGBM, XGBoost, or sklearn HistGradientBoosting
- Uses a triple-barrier style target: TP-before-SL inside a future horizon
- Performs expanding walk-forward testing
- Measures accuracy, ROC-AUC, Brier score, log loss, trade win rate, expectancy in R
- Classifies losing trades into:
  - DIRECTION_ERROR
  - TIMING_OR_STOP_ERROR
  - EXIT_OR_TP_ERROR
  - OVERCONFIDENCE
  - REGIME_OR_NO_EDGE
- Produces an interactive HTML diagnostic report

## Important limitations

This is a **research V1, not a live trading bot**. The current `poc_proxy` is a volume-weighted price proxy, not a true binned Volume Profile POC. BOS/FVG logic is intentionally simple. These should be replaced with your exact trading definitions before judging edge.

The current classifier tests long/BUY setups. A symmetric SELL model is the next step.

## Install

```bash
python -m venv .venv
.venv\\Scripts\\activate
pip install -r requirements.txt
```

## Demo

```bash
python generate_demo_data.py
python main.py --csv data/demo_xauusd_m15.csv --model lightgbm --threshold 0.60
```

Open:

`output/diagnostic_report.html`

## Use MT5 exported data

Export XAUUSD history to CSV and normalize the column names to:

```text
timestamp,open,high,low,close,volume
```

Then run:

```bash
python main.py --csv data/XAUUSD_M15.csv --model lightgbm --horizon 16 --tp-atr 1.5 --sl-atr 1.0 --threshold 0.65
```

## Interpretation

A model change should not be accepted only because the in-sample result improves. Use the walk-forward folds as the first protection against leakage/overfitting. Later versions should add a final untouched holdout period and purged/embargoed CV for overlapping labels.

## Planned V2

1. Exact Swing High/Low definitions
2. True Volume Profile + POC
3. Supply/Demand zones
4. Order Blocks
5. Exact FVG definition
6. BOS/CHOCH state machine
7. Multi-timeframe H4/H1/M15/M5 feature alignment
8. HMM regime model
9. SHAP per losing trade
10. BUY and SELL models
11. News-event flags (CPI/NFP/FOMC)
12. MT5 live/paper-trading bridge
13. Trade replay chart for every signal
14. Automated hypothesis tests for suggested filters
