# 新聞部社群觀看數預測：多切點回測結果

- 產生時間：2026-10-15 14:40（`scripts/run_forecast_backtest.py`）
- 資料：`news_dept_social.fct_daily_traffic`，至 2026-10-10
- 切點：每 14 天一個、各 6 個；預測未來 28 天與 91 天的**總觀看數**
- 指標：總量平均絕對誤差（MAPE of total，越低越好）；區間 = 80% 預測區間（總量區間用每日上下界加總，偏保守）

## 未來 28 天

### 平均絕對誤差（各切點平均）

| series_id | arima | naive | timesfm | timesfm_ig_post0601 | timesfm_yt_engaged |
|---|---|---|---|---|---|
| connected|YouTube | 152% | 185% | 70% |  | 77% |
| news_dept|Facebook | 31% | 42% | 31% |  |  |
| news_dept|Instagram | 36% | 48% | 34% | 49% |  |
| news_dept|X | 42% | 21% | 11% |  |  |
| news_dept|YouTube | 46% | 39% | 32% |  | 38% |
| newsroom|Facebook | 31% | 42% | 31% |  |  |
| newsroom|Instagram | 41% | 39% | 39% | 49% |  |
| newsroom|X | 42% | 21% | 11% |  |  |
| newsroom|YouTube | 19% | 18% | 27% |  | 28% |
| talks|Instagram | 67% | 61% | 93% | 91% |  |
| talks|YouTube | 73% | 53% | 43% |  | 47% |

### 實際值落在預測區間內的比例（總量 / 每日）

| series_id | arima_total | timesfm_total | arima_daily | timesfm_daily |
|---|---|---|---|---|
| connected|YouTube | 33% | 50% | 28% | 55% |
| news_dept|Facebook | 100% | 100% | 82% | 77% |
| news_dept|Instagram | 100% | 100% | 82% | 84% |
| news_dept|X | 100% | 100% | 98% | 79% |
| news_dept|YouTube | 50% | 67% | 46% | 76% |
| newsroom|Facebook | 100% | 100% | 82% | 77% |
| newsroom|Instagram | 100% | 100% | 67% | 86% |
| newsroom|X | 100% | 100% | 98% | 79% |
| newsroom|YouTube | 83% | 100% | 68% | 80% |
| talks|Instagram | 17% | 0% | 35% | 62% |
| talks|YouTube | 33% | 67% | 36% | 72% |

### 各切點明細（新聞部合計）

| series_id | cutoff | arima | naive | timesfm | timesfm_ig_post0601 | timesfm_yt_engaged |
|---|---|---|---|---|---|---|
| news_dept|Facebook | 2026-07-04 | -32% | -2% | -61% |  |  |
| news_dept|Facebook | 2026-07-18 | +16% | +42% | -41% |  |  |
| news_dept|Facebook | 2026-08-01 | +12% | +81% | -21% |  |  |
| news_dept|Facebook | 2026-08-15 | +43% | +58% | +12% |  |  |
| news_dept|Facebook | 2026-08-29 | +68% | +52% | +51% |  |  |
| news_dept|Facebook | 2026-09-12 | +13% | +19% | +1% |  |  |
| news_dept|Instagram | 2026-07-04 | +53% | +88% | -16% |  |  |
| news_dept|Instagram | 2026-07-18 | +92% | +122% | +11% |  |  |
| news_dept|Instagram | 2026-08-01 | -8% | -17% | -50% | -74% |  |
| news_dept|Instagram | 2026-08-15 | -21% | -46% | -48% | -50% |  |
| news_dept|Instagram | 2026-08-29 | -19% | -17% | -44% | -44% |  |
| news_dept|Instagram | 2026-09-12 | -22% | -2% | -38% | -28% |  |
| news_dept|X | 2026-07-04 | +60% | +13% | +5% |  |  |
| news_dept|X | 2026-07-18 | +19% | -14% | -11% |  |  |
| news_dept|X | 2026-08-01 | +15% | -19% | -15% |  |  |
| news_dept|X | 2026-08-15 | -35% | +3% | -10% |  |  |
| news_dept|X | 2026-08-29 | +63% | +50% | +20% |  |  |
| news_dept|X | 2026-09-12 | +63% | +29% | +5% |  |  |
| news_dept|YouTube | 2026-07-04 | -9% | -19% | -11% |  | -13% |
| news_dept|YouTube | 2026-07-18 | -29% | -22% | -31% |  | -31% |
| news_dept|YouTube | 2026-08-01 | -7% | -24% | -16% |  | -18% |
| news_dept|YouTube | 2026-08-15 | -62% | -54% | -65% |  | -66% |
| news_dept|YouTube | 2026-08-29 | -59% | -58% | -65% |  | -71% |
| news_dept|YouTube | 2026-09-12 | +110% | +54% | +2% |  | +28% |

## 未來 91 天

### 平均絕對誤差（各切點平均）

| series_id | arima | naive | timesfm | timesfm_yt_engaged |
|---|---|---|---|---|
| connected|YouTube | 29% | 47% | 58% | 60% |
| news_dept|Facebook | 42% | 41% | 31% |  |
| news_dept|Instagram | 31% | 52% | 37% |  |
| news_dept|X | 68% | 57% | 14% |  |
| news_dept|YouTube | 25% | 25% | 37% | 37% |
| newsroom|Facebook | 42% | 41% | 31% |  |
| newsroom|Instagram | 55% | 56% | 44% |  |
| newsroom|X | 68% | 57% | 14% |  |
| newsroom|YouTube | 20% | 16% | 31% | 30% |
| talks|Instagram | 78% | 54% | 90% |  |
| talks|YouTube | 32% | 43% | 47% | 47% |

### 實際值落在預測區間內的比例（總量 / 每日）

| series_id | arima_total | timesfm_total | arima_daily | timesfm_daily |
|---|---|---|---|---|
| connected|YouTube | 67% | 50% | 41% | 62% |
| news_dept|Facebook | 100% | 100% | 71% | 77% |
| news_dept|Instagram | 100% | 100% | 78% | 81% |
| news_dept|X | 100% | 100% | 100% | 92% |
| news_dept|YouTube | 50% | 67% | 71% | 80% |
| newsroom|Facebook | 100% | 100% | 71% | 77% |
| newsroom|Instagram | 83% | 100% | 54% | 82% |
| newsroom|X | 100% | 100% | 100% | 92% |
| newsroom|YouTube | 100% | 100% | 68% | 80% |
| talks|Instagram | 17% | 17% | 47% | 46% |
| talks|YouTube | 50% | 50% | 62% | 77% |

### 各切點明細（新聞部合計）

| series_id | cutoff | arima | naive | timesfm | timesfm_yt_engaged |
|---|---|---|---|---|---|
| news_dept|Facebook | 2026-05-02 | -37% | -35% | -54% |  |
| news_dept|Facebook | 2026-05-16 | -29% | -26% | -52% |  |
| news_dept|Facebook | 2026-05-30 | -11% | -13% | -31% |  |
| news_dept|Facebook | 2026-06-13 | +14% | +6% | -26% |  |
| news_dept|Facebook | 2026-06-27 | +43% | +65% | -9% |  |
| news_dept|Facebook | 2026-07-11 | +118% | +102% | +11% |  |
| news_dept|Instagram | 2026-05-02 | -32% | -34% | -59% |  |
| news_dept|Instagram | 2026-05-16 | -36% | -49% | -58% |  |
| news_dept|Instagram | 2026-05-30 | -13% | +33% | -43% |  |
| news_dept|Instagram | 2026-06-13 | +25% | +71% | -33% |  |
| news_dept|Instagram | 2026-06-27 | +29% | +67% | -20% |  |
| news_dept|Instagram | 2026-07-11 | +49% | +61% | -7% |  |
| news_dept|X | 2026-05-02 | +46% | -17% | -22% |  |
| news_dept|X | 2026-05-16 | +41% | +152% | +12% |  |
| news_dept|X | 2026-05-30 | +70% | +125% | +6% |  |
| news_dept|X | 2026-06-13 | +75% | +17% | +27% |  |
| news_dept|X | 2026-06-27 | +88% | +24% | +17% |  |
| news_dept|X | 2026-07-11 | +88% | +7% | -1% |  |
| news_dept|YouTube | 2026-05-02 | +2% | +2% | -21% | -22% |
| news_dept|YouTube | 2026-05-16 | -4% | +7% | -24% | -24% |
| news_dept|YouTube | 2026-05-30 | -9% | -1% | -24% | -23% |
| news_dept|YouTube | 2026-06-13 | -41% | -39% | -55% | -53% |
| news_dept|YouTube | 2026-06-27 | -45% | -53% | -48% | -48% |
| news_dept|YouTube | 2026-07-11 | -47% | -50% | -53% | -53% |
