# COS MTF Smart Money Confluence v2.0 — Static Check

- File: `COS_MTF_Smart_Money_Confluence_v2.pine`
- SHA-256: `8cd849df34ab6f7ed35eefb1cae29f0aa1337e545f2d846a069e1abd2cd7e820`
- Lines: 835
- Result: **15 PASS / 0 FAIL**

| Check | Status | Detail |
|---|---:|---|
| Pine version annotation | PASS | //@version=6 |
| Indicator declaration | PASS | indicator() found in global scope |
| Balanced delimiters and strings | PASS | No unmatched (), [], {}, or strings |
| Indentation shape | PASS | Four-space local blocks; no tabs |
| Global-scope plot/fill/barcolor/alertcondition | PASS | All compiler-sensitive visual/event calls are global |
| MTF request count | PASS | 5 request.security() calls; below the common 40 unique-request tier |
| Direct na comparison | PASS | Uses na(x), avoiding invalid direct na comparisons |
| Indicator-only safety | PASS | No broker-emulator orders are placed |
| Drawing declaration caps | PASS | Each drawing cap is 400 (below Pine maximum 500) |
| Historical offset guard | PASS | Dynamic profile history is guarded below max_bars_back |
| Future projection guard | PASS | Zone projection input is capped at 300 bars |
| Table bounds | PASS | 4 columns x 19 rows; populated indices stay within 0..3 and 0..18 |
| Zone-array synchronization structure | PASS | Six zone families each contain box/top/bottom/created/active arrays and an update call |
| Signal gating | PASS | Entry-zone, location, grade, cooldown, valid-risk and confirmed-bar guards present |
| Alert events | PASS | BUY/SELL alertcondition plus dynamic BUY/SELL alert messages |

## Limitation

Static validation only. The authoritative compile/runtime check remains TradingView Pine Editor because no official standalone Pine compiler is available in this environment.

A successful static check reduces common syntax/architecture errors, but it is not equivalent to clicking **Add to chart** in TradingView.