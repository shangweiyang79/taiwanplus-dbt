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

各平台的原生指標名稱與定義不同，這裡統一叫 `video_views`：

| 平台 | 原生欄位 | 平台上的名稱 | 定義 |
|---|---|---|---|
| YouTube | total_views | Views | YouTube 觀看次數 |
| Instagram | Total Plays | Plays | Reels 播放次數（取最新一天的累計快照） |
| Facebook | video_views_3s | 3-second video views | 播放滿 3 秒的次數，門檻最低 |
| X | total_video_views | Video views | X 影片觀看次數 |

解讀規則：
1. **不能跨平台比較優劣**。FB 用 3 秒門檻，數字天生最大（2026 年 FB 的數字遠大於 YouTube），差距主要來自定義而不是成效。跨平台加總只能看整體量級與趨勢。
2. **要比較時，看同一平台自己的逐月趨勢**。
3. **數字都是累計值**，愈晚發布的影片累計天數愈少，最新月份天生偏低，不代表成效衰退。
4. 對照表也存在 seed `platform_metric_glossary`。
{% enddocs %}


{% docs fct_social_post_performance %}
一列 = 新聞部（Newsroom + Talks + Connected）在任一平台上的一則影片貼文，是新聞部社群成效的主表。

{{ doc('news_dept_definition') }}

母體是「平台上所有影片」，包含沒走 CMS 的貼文、newscasts、直播，不經過 post_map。
post_map 只當附加維度，用來補上 vod_id 和主題分類；對不到就是 NULL。
post_map 和主題分類只涵蓋 Newsroom，所以 Talks / Connected 的 vod_id、program、new_category 一律為 NULL。

其他注意事項：
- impressions / ctr 只有 YouTube 有；X 沒有觀看時長。
- Talks / Connected 的 YouTube Shorts 目前無法辨識（yt_shorts 清單只涵蓋 TaiwanPlus News 與 Taiwan Explained），orientation 會是 'video'。
- YouTube 資料只從 2026-01-01 起；IG 從 2023 年起；X 早期月份可能不完整。
{% enddocs %}
