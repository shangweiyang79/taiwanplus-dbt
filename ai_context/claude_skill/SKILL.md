---
name: news-dept-social
description: 回答 TaiwanPlus 新聞部（Newsroom + Talks + Connected）社群成效的問題，例如「新聞部近期社群成效」「Newsroom 上個月 YouTube 觀看數」「Talks 的 IG 互動率」「哪個平台表現最好」「觀看數最高的影片」。只要問到新聞部、Newsroom、Talks、Connected 在 YouTube / Instagram / Facebook / X 的觀看、互動、貼文數、成效趨勢，就使用這個 skill。
---

# 新聞部社群成效查詢

## 步驟

1. **先完整讀定義檔**：`taiwanplus_dbt/ai_context/news_dept_social_context.md`（相對於 `analytics_pipeline/`）。
   這是唯一的定義來源，由 dbt 自動產生。範圍、指標、期間、該查哪張表、怎麼呈現，都照它的「§2 回答流程」，不要自己另外推斷。
2. **依 §2 決定四件事**，回答前在心裡確認：
   - 範圍：「新聞部」= newsroom + talks + connected 三個都要；只有明確說 Newsroom / 新聞台才只算 newsroom
   - 層級（最重要）：
     - **總體成效**（成效如何、總共多少觀看、趨勢）→ **每日流量**：`traffic_views`，查 `news_dept_social.agg_news_dept_daily_traffic_monthly`；自訂期間查 `fct_daily_traffic`
     - **原因分析**（為什麼、哪些影片 / 主題 / 節目表現好）→ **影片層**：`video_views`，查 `fct_social_post_performance` / `agg_news_dept_social_monthly`
     - 問「為什麼」時兩層都用：先用每日流量講總體變化，再用影片層找貢獻最大的影片
   - 期間：「近期」沒指定時 = 最近三個完整月份
3. **用 BigQuery MCP 的 `execute_sql` 查詢**。
   - 只能查 `${GCP_PROJECT}.news_dept_social.*`。不要查 `dbt_internal` 或各平台原表。
   - 定義檔和範例 SQL 裡的 `${GCP_PROJECT}` 是佔位字，查詢前代換成實際的 GCP 專案 ID（環境變數 `GCP_PROJECT`）。
   - 只能用 SELECT。
4. **照 §2「呈現規則」回答**，至少要做到：
   - 各平台分開列，不用四平台加總當主結論
   - 不用絕對值比較平台優劣，改看各平台自己的趨勢
   - 說明各平台觀看門檻不同（IG 約 0.3～0.5 秒、X 連續 2 秒、FB 3 秒、YouTube 自 2026-08-27 起約 1 秒）
   - FB 數字大的原因是菲律賓受眾，不是門檻低（FB 的 3 秒是四個平台中最嚴格的）
   - YouTube 以 Views（KPI）為主，另附 engaged views 作輔助參考；期間跨過 2026-08-27 時，說明 Views 的變化有一部分來自門檻放寬
   - 寫明用的是「每日流量」還是「影片層」，兩層數字不放在同一欄比較
   - 主動提醒相關的資料限制，例如 IG 每日流量 2026-06-01 換算法、Connected IG 已停更、本月資料不完整
5. **回答最後附上一行「查詢範圍」**，例如：「範圍：新聞部三單位｜指標：每日流量觀看數｜期間：2026-07～09｜來源：agg_news_dept_daily_traffic_monthly」，讓使用者能檢查 AI 的判斷。

## 定義檔過期時

定義檔開頭有產生日期。如果使用者說定義改了，或 dbt 的 `_definitions.md` / `_marts.yml` 比定義檔新，請使用者在 `taiwanplus_dbt/` 執行：

```
python scripts/build_ai_context.py
```

不要手改定義檔。
