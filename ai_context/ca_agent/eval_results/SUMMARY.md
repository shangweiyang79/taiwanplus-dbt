# Data Agent 評估摘要（2026-10-15）

逐題的完整紀錄（含實際查詢結果與回答全文）有業務數字，只留在本機，不進版控；這裡只放評分與延遲。
題庫見 `ai_context/eval_questions.yml`（10 題，每題有 `must_mention` / `must_not`）；身分一律是唯讀 SA。

| 流程 | 題組 | 通過 | 延遲中位數 | 紀錄（本機） |
|---|---|---|---|---|
| CA API FAST | 原題 / 換句話說 / 英文 | 6/30（中文原題 2/10） | 約 8 秒 | `20261015_1435_fast.md` |
| CA API THINKING | 原題 / 換句話說 / 英文 | **30/30** | 約 29 秒（19–50） | `20261015_1445.md` |
| **FAST 取數 + Gemini Flash 撰寫**（上線版） | 原題 / 換句話說 | **20/20** | **20.4 秒**（10.3–32.4） | `20261015_1626_deep.md` |

## FAST：取數全對，但不遵守呈現規則

- 30/30 都命中範例查詢，給出的數字沒有錯誤。
- 但最終文字常沒照 system_instruction：摘要空泛、把「新聞部」寫成只有 newsroom、用 FB 絕對值最高當主結論、沒提 YouTube 2026-08-27 門檻放寬、四平台加總不加說明。
- 結論：不能單獨上線 → 上線版的快速模式用 `chatbox_app/notes.py` 依查詢結果補上固定提醒。

| 題目 | 結果 | 主要問題 |
|---|---|---|
| q1_news_dept_recent | 不通過 | 摘要空泛；以 FB 最高當主結論 |
| q2_newsroom_yt_last_month | 通過 | 沒說是當月實際發生的觀看 |
| q3_talks_ig_engagement_rate | 通過 | 沒說明是加總後相除 |
| q4_connected_ig_recent | 部分 | 有提停更，沒建議改看 YouTube |
| q5_best_platform | 不通過 | 以絕對值 / YouTube 月增率下結論，沒提門檻差異 |
| q6_top_videos | 不通過 | 文字只列第 1 名，沒附標題與連結 |
| q7_ytd_total | 部分 / 英文不通過 | 英文版只給四平台加總、未說明 |
| q8_youtube_definition_change | 不通過 | 沒提 8/27，回答「成長屬實」 |
| q9_why_talks_september | 部分 | 兩層都有，但沒提 8/27 與口徑差異 |
| q10_may_overall | 不通過 | 沒提 IG 2026-06-01 換算法 |

## THINKING：品質達標，但太慢

30/30 通過（中文原題 10/10，門檻 ≥ 8/10）。延遲約為 FAST 的 4 倍，而且「撰寫分析」占 20–22 秒、資料要到最後才送回。

## FAST 取數 + Gemini Flash 撰寫（上線的「深入分析」模式）

| 題目 | 原題 / 換句話說 | 重點 |
|---|---|---|
| q1_news_dept_recent | ✓ / ✓ | 三單位分開、門檻、8/27、IG Stories、Connected 停更、查詢範圍 |
| q2_newsroom_yt_last_month | ✓ / ✓ | |
| q3_talks_ig_engagement_rate | ✓ / ✓ | 註明互動數 ÷ 觀看數、影片層 |
| q4_connected_ig_recent | ✓ / ✓ | 停更、舊貼文長尾、每日流量不為 0 |
| q5_best_platform | ✓ / ✓ | 先說不可比絕對值，以月增率判斷，附 engaged views |
| q6_top_videos | ✓ / ✓ | 標題、連結、累計口徑 |
| q7_ytd_total | ✓ / ✓ | 四平台加總有註明只看量級 |
| q8_youtube_definition_change | ✓ / ✓ | 指出 Newsroom 的 Views 成長、engaged views 卻下降約 30% |
| q9_why_talks_september | ✓ / ✓ | 兩層都用、8/27 |
| q10_may_overall | ✓ / ✓ | IG 換算法 |

- 品質與 THINKING 相當，總時間中位數 20.4 秒；判斷型問題約 20–24 秒（THINKING 35–50 秒），取完數就開始串流出字。
- 自動數字檢查（`narrator.unmatched_numbers`）在 3 題列出查詢結果裡沒有的數字，人工確認都是模型自己算的加總，沒有抄錯。
