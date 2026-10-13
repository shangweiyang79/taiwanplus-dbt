{% docs news_dept_definition %}
**新聞部（News Department）= Newsroom + Talks + Connected 三個單位。**

- 問「新聞部」的社群成效時，三個單位都要算；只有明確說 Newsroom（新聞台）時才篩 `dept_scope = 'newsroom'`。
- 各單位經營的平台：
  - Newsroom：YouTube（TaiwanPlus News / TaiwanPlus Livestream / Taiwan Explained by TaiwanPlus）、Instagram、Facebook、X
  - Talks：YouTube（Taiwan Talks）、Instagram
  - Connected：YouTube（CONNECTED on TaiwanPlus）；Instagram 於 2026-07-04 停更，歷史資料保留
- 單位、平台、原表的完整對照見 seed `dept_accounts`。
{% enddocs %}


{% docs dept_scope %}
新聞部內的單位：`newsroom`（新聞台）、`talks`、`connected`。三者合起來就是「新聞部」。
{% enddocs %}


{% docs platform %}
社群平台：`YouTube`、`Instagram`、`Facebook`、`X`。
{% enddocs %}


{% docs video_views_definition %}
**影片觀看數，是「社群成效」的預設主指標。**

各平台的原生指標名稱與計算門檻不同，這裡統一叫 `video_views`：

| 平台 | 原生欄位 | 平台上的名稱 | 計算門檻 |
|---|---|---|---|
| YouTube | total_views | Views | **2026-08-27 起播放約 1 秒即計一次；之前約 30 秒**（舊標準約等於現在的 Engaged views） |
| Instagram | Total Plays | Plays | 播放約 0.3～0.5 秒即計（取最新一天的累計快照） |
| Facebook | video_views_3s | 3-second video views | 播放滿 3 秒，**目前四個平台中門檻最嚴格** |
| X | total_video_views | Video views | 連續播放 2 秒 |

YouTube 另有 `engaged_views`（Engaged views），計算方式接近 8/27 之前的舊 Views，作為**輔助參考**。**KPI 仍是 Views**。

解讀規則：
1. **不能跨平台比較優劣**。各平台的計算門檻不同、受眾結構也不同，絕對值不能直接比較。跨平台加總只能看整體量級。
   - **FB 的數字最大，不是因為門檻低**（FB 的 3 秒其實比 IG、X、現在的 YouTube 都嚴格），而是因為 FB 的觀眾群以**菲律賓**最多，和菲律賓有關的新聞在 FB 表現最好。
   - 實測：2026 年 Newsroom 在 FB 上，標題提到菲律賓的貼文平均觀看是其他貼文的 7.8 倍；這些貼文只占貼文數 1.7%，卻貢獻 FB 總觀看的 12%。
2. **要比較時，看同一平台自己的逐月趨勢**。
3. **YouTube 的 Views 於 2026-08-27 放寬門檻**。KPI 仍以 Views 為準，但期間跨過 8/27 時要說明影響：
   - 實測 8/27 之前 Views 約為 Engaged views 的 1.1～1.3 倍，8/27 起變成 2.1～2.7 倍，所以 8/27 之後 Views 的成長有相當部分來自定義放寬。
   - 同時列出 Engaged views 作為輔助參考，幫助判斷實際的觀看變化。
4. **數字都是累計值**，愈晚發布的影片累計天數愈少，最新月份天生偏低，不代表成效衰退。
5. 對照表也存在 seed `platform_metric_glossary`。
{% enddocs %}


{% docs traffic_vs_video_level %}
**新聞部的觀看數有兩層，口徑不同、數字不同，不能混用：**

| | 每日流量（daily traffic） | 影片層（video level） |
|---|---|---|
| 意思 | 該期間內**實際發生**的觀看，不管影片何時發布 | 該期間**發布**的影片，到今天為止的**累計**觀看 |
| 用途 | **總體成效（KPI）**：某月 / 某期間總共多少觀看、整體趨勢 | **原因分析**：哪些影片 / 主題 / 節目表現好、為什麼 |
| 表 | `agg_news_dept_daily_traffic_monthly`、`fct_daily_traffic` | `agg_news_dept_social_monthly`、`fct_social_post_performance` |
| 指標 | `traffic_views` | `video_views` |

例（2026-09 實測）：YouTube Newsroom 的每日流量約為影片層的 1.5 倍；IG Talks 則相反，影片層約為每日流量的 2 倍。

每日流量的資料限制：
- 起始日：YouTube 2025-06-28、FB 2025-08-01、IG 2025-08-01、IG Stories 2025-09-14、X 2025-12-29。更早的期間沒有每日流量。
- **IG 於 2026-06-01 換算法**：之前是各帳號每天 Total Plays 總和減前一天（`source_method = snapshot_delta`），和之後的官方 API 相比通常偏高 10～20%，偶有負數；跨 6/1 比較 IG 趨勢時要說明。
- IG 的 views 含影片類 Stories（`story_views` 另列）；YouTube / FB 含付費觀看（`paid_views` 另列）。
- Connected 的 IG 停更後，舊貼文每天仍有觀看，所以每日流量不會是 0（影片層的新發布則是 0）。
- TaiwanPlus Livestream 頻道的每日流量到 2026-08-05 為止。
{% enddocs %}


{% docs fct_daily_traffic %}
一列 = 日 × 新聞部單位 × 平台 × 內容類型（video / story），新聞部每日流量的主表。

{{ doc('news_dept_definition') }}

{{ doc('traffic_vs_video_level') }}

{{ doc('video_views_definition') }}
{% enddocs %}


{% docs ai_answering_guide %}
### 判斷範圍

| 使用者說 | 範圍 |
|---|---|
| 新聞部、新聞部門、news department | `dept_scope` in ('newsroom', 'talks', 'connected')，三個都要 |
| Newsroom、新聞台、TaiwanPlus News | `dept_scope = 'newsroom'` |
| Talks、Taiwan Talks | `dept_scope = 'talks'` |
| Connected、CONNECTED | `dept_scope = 'connected'` |
| 沒指定平台 | 該範圍內所有平台（新聞部 = YouTube、Instagram、Facebook、X） |

### 判斷指標

- 「成效」「表現」「performance」「總共多少觀看」沒指定指標時 → **每日流量的 `traffic_views`**（總體成效 KPI）。
- 「為什麼」「原因」「哪些影片 / 主題 / 節目表現好」→ 影片層的 `video_views`，並附上 `post_count`。
- 「互動」→ `engagements`；「互動率」→ `engagement_rate`；「觀看時長」→ `watch_time_hours`（X 沒有）。
- 各平台的觀看指標原生名稱不同（YouTube Views、IG Plays、FB 3-second video views、X Video views），回答時要用統一名稱「影片觀看數」，必要時括號註明原生名稱。
- **YouTube 一律以 Views 為主（KPI）**，同時附上 engaged views（每日流量 `traffic_engaged_views`、影片層 `yt_engaged_views`）作為輔助參考。期間跨過 2026-08-27 時（例如比較 7 月與 9 月），要說明 Views 的變化有一部分來自門檻放寬。

### 判斷期間

- 「近期」「最近」沒指定期間時 → **最近三個完整月份**；若也列出本月，必須標註「本月至今、尚未完整」。
- 每日流量的期間依**觀看發生日**（`date`）；影片層的期間依**影片發布日**（`publish_date`）。

### 選擇資料表

| 問題類型 | 查哪張 |
|---|---|
| **總體成效**：新聞部 / 單位 / 平台的逐月成效、趨勢、某月總共多少觀看（最常見） | `news_dept_social.agg_news_dept_daily_traffic_monthly`，**直接讀，不要自己從明細加總** |
| 總體成效，但期間是自訂的（某幾週、某幾天） | `news_dept_social.fct_daily_traffic` |
| **原因分析**：哪些影片表現最好、依主題 / 節目 / 直式切分、單則貼文排行 | `news_dept_social.fct_social_post_performance` |
| 原因分析的逐月彙總（依發布月份） | `news_dept_social.agg_news_dept_social_monthly` |

**問「為什麼」時兩層都要用**：先用每日流量說明總體變化，再用影片層找出貢獻最大的影片 / 主題，並說明兩層口徑不同（影片層是依發布日累計）。
| 單位、平台、帳號對照，某帳號是否停更 | `news_dept_social.dept_accounts` |
| 指標在各平台的原生欄位與定義 | `news_dept_social.platform_metric_glossary` |

不要查 `dbt_internal` 或各平台原表：原表有快照、重複等陷阱（例如 IG 原表直接 SUM 會灌水上百倍），已在上述表格處理好。

### 呈現規則

1. **各平台分開列**。不要把四個平台的觀看數加總成單一數字當主結論；若列出總和，要註明「各平台定義不同，只能看量級」。
2. **不要用絕對值比較平台優劣**。比較請看各平台自己的逐月趨勢（例如月增率）。
   - 解釋 FB 數字為什麼最大時，原因是**菲律賓受眾**，不是「門檻低」（FB 的 3 秒門檻是四個平台中最嚴格的）。
3. **YouTube 以 Views 為主、Engaged views 為輔**。期間跨過 2026-08-27 時，Views 的成長不能全部歸因於成效，要搭配 Engaged views 說明有多少來自定義放寬。
4. 影片層的最新月份累計天數少、天生偏低，不要解讀成衰退；每日流量的本月則是天數未滿（看 `days_with_data`）。
5. 主動說明資料限制：
   - Connected 的 IG 於 2026-07-04 停更
   - Talks / Connected 沒有主題分類
   - X 沒有觀看時長
   - YouTube Views 定義於 2026-08-27 變更；影片層 YouTube 資料從 2026-01-01 起
   - IG 每日流量於 2026-06-01 換算法（之前偏高 10～20%）
   - 每日流量各平台的起始日不同（見 §1），更早的期間沒有每日流量
6. 平均值易被少數爆量貼文拉高，引用平均時一併看 `max_views_per_post`。
7. **回答時寫明用的是哪一層**（「每日流量」或「影片層」），兩層的數字不要放在同一欄比較。
{% enddocs %}


{% docs fct_social_post_performance %}
一列 = 新聞部（Newsroom + Talks + Connected）在任一平台上的一則影片貼文，是新聞部社群成效的主表。

{{ doc('news_dept_definition') }}

{{ doc('video_views_definition') }}

母體是「平台上所有影片」，包含沒走 CMS 的貼文、newscasts、直播，不經過 post_map。
post_map 只當附加維度，用來補上 vod_id 和主題分類；對不到就是 NULL。
post_map 和主題分類只涵蓋 Newsroom，所以 Talks / Connected 的 vod_id、program、new_category 一律為 NULL。

其他注意事項：
- impressions / ctr 只有 YouTube 有；X 沒有觀看時長。
- Talks / Connected 的 YouTube Shorts 目前無法辨識（yt_shorts 清單只涵蓋 TaiwanPlus News 與 Taiwan Explained），orientation 會是 'video'。
- YouTube 資料只從 2026-01-01 起；IG 從 2023 年起；X 早期月份可能不完整。
{% enddocs %}
