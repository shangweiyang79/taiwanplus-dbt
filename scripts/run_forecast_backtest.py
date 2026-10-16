"""新聞部社群觀看數預測的多切點回測（給新聞雙週報用，不接 Data Chatbox）。

比較三種方法預測「未來 28 天 / 91 天總觀看數」的準確度：
    timesfm   AI.FORECAST（TimesFM 2.5，免訓練）
    arima     ARIMA_PLUS（每個切點訓練一次；HOLIDAY_REGION=TW、清突波、調整水準位移）
    naive     前 28 天日平均 × 天數（對照組）
外加兩個處理斷點的變化版（只用 TimesFM）：
    timesfm_yt_engaged  YouTube 改預測 engaged_views，再乘切點前 28 天的 views / engaged 比例（因應 2026-08-27 定義改變）
    timesfm_ig_post0601 Instagram 只用 2026-06-01 換算法之後的資料

序列：新聞部合計 × 平台（news_dept|YouTube …），以及 單位 × 平台（newsroom|YouTube …；Connected IG 已停更不列）。
為了省錢，先把每日序列存成 dev 小表 dbt_joy.fc_daily_series（直接讀 view 每次要掃約 0.76 GB，
ARIMA 訓練又會乘上候選模型數）。ARIMA 模型建在 dbt_joy，跑完刪除。

用法（在 taiwanplus_dbt/ 下）：
    python scripts/run_forecast_backtest.py
輸出：analyses/forecast_backtest_results.md
"""
import datetime as dt
import os
import sys

import pandas as pd
from google.cloud import bigquery

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.environ.get("GCP_PROJECT") or sys.exit("請先設定環境變數 GCP_PROJECT（GCP 專案 ID，見 .env.example）")
DEV = f"{PROJECT}.dbt_joy"
SERIES = f"{DEV}.fc_daily_series"
DATA_END = dt.date(2026, 10, 10)  # 四個平台都有完整資料的最後一天
YT_BREAK = dt.date(2026, 8, 27)
IG_BREAK = dt.date(2026, 6, 1)
STEP_DAYS = 14
N_CUTOFFS = 6
HORIZONS = [28, 91]
CONF = 0.8
OUT = os.path.join(ROOT, "analyses", "forecast_backtest_results.md")


def cutoffs(h):
    last = DATA_END - dt.timedelta(days=h)
    return [last - dt.timedelta(days=STEP_DAYS * i) for i in range(N_CUTOFFS)]


def build_series(client):
    client.query(f"""
        CREATE OR REPLACE TABLE `{SERIES}` AS
        WITH base AS (
          SELECT date, dept_scope, platform, SUM(views) AS views, SUM(engaged_views) AS engaged_views
          FROM `{PROJECT}.news_dept_social.fct_daily_traffic`
          WHERE date <= '{DATA_END}'
          GROUP BY 1, 2, 3
        )
        SELECT date, CONCAT('news_dept|', platform) AS series_id, platform,
               SUM(views) AS views, SUM(engaged_views) AS engaged_views
        FROM base GROUP BY 1, 2, 3
        UNION ALL
        SELECT date, CONCAT(dept_scope, '|', platform), platform, views, engaged_views
        FROM base WHERE NOT (dept_scope = 'connected' AND platform = 'Instagram')
    """).result()
    return client.query(f"SELECT * FROM `{SERIES}`").to_dataframe()


def timesfm(client, cutoff, h, col="views", where="TRUE"):
    sql = f"""
        SELECT series_id, DATE(forecast_timestamp) AS date, forecast_value AS fc,
               prediction_interval_lower_bound AS lo, prediction_interval_upper_bound AS hi
        FROM AI.FORECAST(
          (SELECT date, series_id, {col} AS y FROM `{SERIES}` WHERE date <= '{cutoff}' AND {where}),
          data_col => 'y', timestamp_col => 'date', id_cols => ['series_id'],
          horizon => {h}, confidence_level => {CONF})
    """
    return client.query(sql).to_dataframe()


def arima(client, cutoff, h):
    model = f"{DEV}.fc_arima_{cutoff:%Y%m%d}"
    client.query(f"""
        CREATE OR REPLACE MODEL `{model}`
        OPTIONS (model_type = 'ARIMA_PLUS', time_series_timestamp_col = 'date',
                 time_series_data_col = 'views', time_series_id_col = 'series_id',
                 data_frequency = 'DAILY', holiday_region = 'TW', horizon = {max(HORIZONS)},
                 clean_spikes_and_dips = TRUE, adjust_step_changes = TRUE)
        AS SELECT date, series_id, views FROM `{SERIES}` WHERE date <= '{cutoff}'
    """).result()
    df = client.query(f"""
        SELECT series_id, DATE(forecast_timestamp) AS date, forecast_value AS fc,
               prediction_interval_lower_bound AS lo, prediction_interval_upper_bound AS hi
        FROM ML.FORECAST(MODEL `{model}`, STRUCT({h} AS horizon, {CONF} AS confidence_level))
    """).to_dataframe()
    return df


def score(fc, series, cutoff, h, method):
    """fc：每日預測。回傳每條序列的總量誤差與區間覆蓋。"""
    end = cutoff + dt.timedelta(days=h)
    act = series[(series.date > cutoff) & (series.date <= end)]
    rows = []
    for sid, f in fc.groupby("series_id"):
        a = act[act.series_id == sid]
        if a.empty:
            continue
        m = f.merge(a[["date", "views"]], on="date")
        total_fc = f.fc.clip(lower=0).sum()
        total_act = a.views.sum()
        rows.append({
            "method": method, "series_id": sid, "horizon": h, "cutoff": cutoff,
            "forecast": total_fc, "actual": total_act,
            "pct_err": (total_fc - total_act) / total_act if total_act else None,
            "in_band_total": f.lo.clip(lower=0).sum() <= total_act <= f.hi.sum(),
            "daily_coverage": ((m.views >= m.lo) & (m.views <= m.hi)).mean(),
        })
    return rows


def naive(series, cutoff, h):
    hist = series[(series.date > cutoff - dt.timedelta(days=28)) & (series.date <= cutoff)]
    avg = hist.groupby("series_id").views.mean()
    dates = [cutoff + dt.timedelta(days=i) for i in range(1, h + 1)]
    return pd.DataFrame([{"series_id": s, "date": d, "fc": v, "lo": None, "hi": None}
                         for s, v in avg.items() for d in dates])


def main():
    client = bigquery.Client(project=PROJECT)
    series = build_series(client)
    series["date"] = pd.to_datetime(series.date).dt.date
    results = []
    models = set()
    for h in HORIZONS:
        for c in cutoffs(h):
            print(f"horizon {h}，切點 {c}", flush=True)
            for method, fc in [("timesfm", timesfm(client, c, h)), ("arima", arima(client, c, h)),
                               ("naive", naive(series, c, h))]:
                fc["date"] = pd.to_datetime(fc.date).dt.date
                if method == "naive":
                    fc[["lo", "hi"]] = float("nan")
                results += score(fc, series, c, h, method)
            models.add(f"{DEV}.fc_arima_{c:%Y%m%d}")

            # YouTube：預測 engaged_views × 近 28 天 views/engaged 比例
            yt = timesfm(client, c, h, col="engaged_views", where="platform = 'YouTube'")
            hist = series[(series.platform == "YouTube") & (series.date > c - dt.timedelta(days=28)) & (series.date <= c)]
            sums = hist.groupby("series_id")[["views", "engaged_views"]].sum()
            ratio = sums.views / sums.engaged_views
            for col in ("fc", "lo", "hi"):
                yt[col] = yt[col] * yt.series_id.map(ratio)
            yt["date"] = pd.to_datetime(yt.date).dt.date
            results += score(yt, series, c, h, "timesfm_yt_engaged")

            # Instagram：只用 6/1 換算法之後的資料（至少 60 天歷史才跑）
            if (c - IG_BREAK).days >= 60:
                ig = timesfm(client, c, h, where=f"platform = 'Instagram' AND date >= '{IG_BREAK}'")
                ig["date"] = pd.to_datetime(ig.date).dt.date
                results += score(ig, series, c, h, "timesfm_ig_post0601")

    for m in models:
        client.delete_model(m, not_found_ok=True)

    df = pd.DataFrame(results)
    df["abs_err"] = df.pct_err.abs()
    df.to_csv(OUT.replace(".md", ".csv"), index=False, encoding="utf-8-sig")
    write_report(df)
    print(f"已輸出 {OUT}")


def write_report(df):
    lines = [
        "# 新聞部社群觀看數預測：多切點回測結果", "",
        f"- 產生時間：{dt.datetime.now():%Y-%m-%d %H:%M}（`scripts/run_forecast_backtest.py`）",
        f"- 資料：`news_dept_social.fct_daily_traffic`，至 {DATA_END}",
        f"- 切點：每 {STEP_DAYS} 天一個、各 {N_CUTOFFS} 個；預測未來 28 天與 91 天的**總觀看數**",
        f"- 指標：總量平均絕對誤差（MAPE of total，越低越好）；區間 = {int(CONF * 100)}% 預測區間"
        "（總量區間用每日上下界加總，偏保守）", "",
    ]
    for h in HORIZONS:
        d = df[df.horizon == h]
        lines += [f"## 未來 {h} 天", "", "### 平均絕對誤差（各切點平均）", ""]
        pivot = d.pivot_table(index="series_id", columns="method", values="abs_err", aggfunc="mean")
        lines += [_md_table(pivot.map(lambda v: "" if pd.isna(v) else f"{v:.0%}")), ""]
        lines += ["### 實際值落在預測區間內的比例（總量 / 每日）", ""]
        cov = d[d.method.isin(["timesfm", "arima"])].groupby(["series_id", "method"]).agg(
            total=("in_band_total", "mean"), daily=("daily_coverage", "mean")).unstack("method")
        cov.columns = [f"{m}_{k}" for k, m in cov.columns]
        lines += [_md_table(cov.map(lambda v: f"{v:.0%}")), ""]
        lines += ["### 各切點明細（新聞部合計）", ""]
        det = d[d.series_id.str.startswith("news_dept")].pivot_table(
            index=["series_id", "cutoff"], columns="method", values="pct_err")
        lines += [_md_table(det.map(lambda v: "" if pd.isna(v) else f"{v:+.0%}")), ""]
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def _md_table(frame):
    frame = frame.reset_index()
    cols = [str(c) for c in frame.columns]
    out = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for _, r in frame.iterrows():
        out.append("| " + " | ".join(str(v) for v in r.values) + " |")
    return "\n".join(out)


if __name__ == "__main__":
    main()
