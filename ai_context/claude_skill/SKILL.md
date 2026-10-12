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
   - 指標：沒指定時用 `video_views`，附上 `post_count`
   - 期間：「近期」沒指定時 = 最近三個完整月份
   - 資料表：逐月問題查 `news_dept_social.agg_news_dept_social_monthly`；自訂期間、主題、單則排行才查 `fct_social_post_performance`
3. **用 BigQuery MCP 的 `execute_sql` 查詢**。
   - 只能查 `ivory-airfoil-418408.news_dept_social.*`。不要查 `dbt_internal` 或各平台原表。
   - 只能用 SELECT。
4. **照 §2「呈現規則」回答**，至少要做到：
   - 各平台分開列，不用四平台加總當主結論
   - 不用絕對值比較平台優劣，改看各平台自己的趨勢
   - 說明各平台觀看定義不同（例如 FB 是 3 秒觀看）
   - 主動提醒相關的資料限制，例如 Connected IG 已停更、本月資料不完整
5. **回答最後附上一行「查詢範圍」**，例如：「範圍：新聞部三單位｜指標：影片觀看數｜期間：2026-07～09｜來源：agg_news_dept_social_monthly」，讓使用者能檢查 AI 的判斷。

## 定義檔過期時

定義檔開頭有產生日期。如果使用者說定義改了，或 dbt 的 `_definitions.md` / `_marts.yml` 比定義檔新，請使用者在 `taiwanplus_dbt/` 執行：

```
python scripts/build_ai_context.py
```

不要手改定義檔。
