"""模式判斷與規則式資料提醒。

PoC 評估（ai_context/ca_agent/eval_results/）發現：FAST 模式取數正確，但回答常漏掉業務提醒，
判斷型問題還會下錯結論；THINKING 模式品質完整但要 19–50 秒。所以：
- route_mode：判斷型問題（為什麼、是真的嗎、哪個最好、成效如何…）自動用 THINKING，其餘用 FAST。
- build_notes / scope_line：FAST 模式下，依查詢結果用固定規則補上提醒與「查詢範圍」，不靠模型記得。
提醒的內容與 ai_context/news_dept_social_context.md §1–2 一致；定義改了要一起改這裡。
"""
import calendar
import datetime as dt
import re

THINKING_PATTERN = re.compile(
    r"為什麼|為何|原因|是真的|真的|實際的|比較|對比|哪個|哪一|最好|最差|最亮眼|趨勢|成長|下滑|衰退|"
    r"表現|成效|怎麼樣|如何|分析|建議|"
    r"\bwhy\b|compare|\bbest\b|\bworst\b|trend|growth|perform|\breal\b",
    re.IGNORECASE,
)

YT_BREAK = dt.date(2026, 8, 27)
IG_BREAK = dt.date(2026, 6, 1)
# 影片層 YouTube / X 從這天起；更早只有 IG（2023 起）與 FB（2024 起，2024–2025 是凍結快照）
VIDEO_LAYER_ALL_PLATFORMS = dt.date(2026, 1, 1)
DAILY_TABLES = {"agg_news_dept_daily_traffic_monthly", "fct_daily_traffic"}
VIDEO_TABLES = {"fct_social_post_performance", "agg_news_dept_social_monthly"}
SCOPE_LABELS = {"newsroom": "Newsroom", "talks": "Talks", "connected": "Connected"}
PLATFORMS = ("YouTube", "Instagram", "Facebook", "X")


def route_mode(question):
    """回傳 True 表示用 THINKING。"""
    return bool(THINKING_PATTERN.search(question))


def _month_bounds(d):
    return [d.replace(day=1), d.replace(day=calendar.monthrange(d.year, d.month)[1])]


def _dates(rows):
    """回傳結果涵蓋的日期。`date`（每日）照實際日期；`month_start`、`publish_date` 擴成整個月：
    排行類問題（例如上個月前 5 支影片）的查詢期間是整個月，不是前 5 支剛好落在的 9/1～9/21。"""
    out = []
    for r in rows:
        v = r.get("date")
        if isinstance(v, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", v[:10]):
            out.append(dt.date.fromisoformat(v[:10]))
        for key in ("month_start", "publish_date"):
            v = r.get(key)
            if isinstance(v, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", v[:10]):
                out += _month_bounds(dt.date.fromisoformat(v[:10]))
        ym = r.get("year_month")
        if isinstance(ym, str) and re.fullmatch(r"\d{4}-\d{2}", ym):
            y, m = map(int, ym.split("-"))
            out += [dt.date(y, m, 1), dt.date(y, m, calendar.monthrange(y, m)[1])]
        # 依年份彙總的結果（例如 EXTRACT(YEAR ...) AS publish_year，CA 回傳的數字常是 2025.0）擴成整年
        for key in ("year", "publish_year"):
            y = _year(r.get(key))
            if y:
                out += [dt.date(y, 1, 1), dt.date(y, 12, 31)]
    return out


def _year(v):
    try:
        y = int(float(v))
    except (TypeError, ValueError):
        return None
    return y if 2000 <= y <= 2100 else None


# SQL 用年份篩選時（EXTRACT(YEAR FROM publish_date) = 2025 或 IN (2025, 2026)），結果可能沒有日期欄位
_SQL_YEAR = re.compile(r"EXTRACT\s*\(\s*YEAR\s+FROM\s+[\w.`]+\s*\)\s*(?:=\s*(\d{4})|IN\s*\(([\d,\s]+)\))",
                       re.IGNORECASE)


def _sql_years(sql):
    years = []
    for eq, in_list in _SQL_YEAR.findall(sql):
        years += [int(y) for y in re.findall(r"\d{4}", eq or in_list)]
    return [{"year": y} for y in years]


def _facts(results):
    rows = [r for res in results for r in res["rows"]]
    sql = "\n".join(res.get("sql") or "" for res in results)
    platforms = {r["platform"] for r in rows if r.get("platform") in PLATFORMS}
    platforms |= {p for p in PLATFORMS if re.search(rf"'{p}'", sql)}
    scopes = {r["dept_scope"] for r in rows if r.get("dept_scope") in SCOPE_LABELS}
    scopes |= {s for s in SCOPE_LABELS if re.search(rf"'{s}'", sql)}
    tables = sorted(set(re.findall(r"news_dept_social\.(\w+)", sql)))
    # 結果沒有日期欄位時（例如 WHERE year_month = '2026-05'），改從 SQL 的日期字串推期間
    dates = _dates(rows) or _dates([{"year_month": m} for m in re.findall(r"'(\d{4}-\d{2})'", sql)]
                                   + [{"date": d} for d in re.findall(r"'(\d{4}-\d{2}-\d{2})'", sql)]
                                   + _sql_years(sql))
    return platforms, scopes, tables, (min(dates), max(dates)) if dates else None


def build_notes(results, today=None):
    """依查詢結果產生資料提醒（list[str]）。"""
    today = today or dt.date.today()
    platforms, scopes, tables, period = _facts(results)
    notes = []
    if "YouTube" in platforms and period and period[1] >= YT_BREAK:
        crossed = "本次期間跨過 2026-08-27，" if period[0] < YT_BREAK else ""
        notes.append(f"YouTube 自 2026-08-27 起放寬 Views 門檻（約 30 秒 → 約 1 秒）。{crossed}"
                     "Views 的成長有一部分來自定義放寬，請搭配 Engaged views 判讀。")
    if "Instagram" in platforms and period and period[0] < IG_BREAK and DAILY_TABLES & set(tables):
        notes.append("IG 每日流量在 2026-06-01 前是舊算法（快照相減），通常比之後的官方 API 偏高 10～20%。")
    if (VIDEO_TABLES & set(tables) and period and period[0] < VIDEO_LAYER_ALL_PLATFORMS
            and platforms != {"Instagram"}):
        notes.append("影片層各平台起始日不同：IG 2023 年、FB 2024-01-01、YouTube 與 X 2026-01-01 起。"
                     "2026 年以前只有 IG 和 FB，跨年比較不要用多平台合計；"
                     "FB 2024–2025 是 2026-11-02 匯出的凍結快照，之後不再更新。")
    if "Instagram" in platforms and (not scopes or "connected" in scopes):
        notes.append("Connected 的 IG 已於 2026-07-04 停更，之後的觀看來自舊貼文；"
                     "2026-09-29 起暫停收集每日流量，之後沒有資料（不是 0 次觀看）。")
    if len(platforms) >= 2:
        notes.append("各平台觀看門檻與受眾不同（FB 3 秒、X 連續 2 秒、IG 約 0.3～0.5 秒、YouTube 約 1 秒），"
                     "不能用絕對值比較平台優劣；FB 數字大是因為菲律賓受眾，不是門檻低。")
    if period and period[1] >= today.replace(day=1):
        notes.append("期間包含本月，本月資料尚未完整。")
    return notes


# 回答裡已經講過就不重複提醒：提醒的開頭 → 回答中出現任一關鍵字即視為已提過
_ALREADY_SAID = {
    "YouTube 自": ("8-27", "8/27", "08/27", "8 月 27", "August 27"),
    "IG 每日流量": ("06-01", "6/1", "6 月 1", "June 1"),
    "影片層各平台起始日": ("起始日", "2026 年以前", "凍結", "snapshot", "2026-01-01 起"),
    # 只講停更、沒講暫停收集時仍要補提醒，所以關鍵字用「暫停收集」相關的字
    "Connected 的 IG": ("暫停收集", "9-29", "9/29", "9 月 29", "paused"),
    "各平台觀看門檻": ("門檻", "threshold"),
    "期間包含本月": ("本月", "尚未完整", "incomplete"),
}


def unsaid(notes, answer):
    """去掉回答裡已經提過的提醒。"""
    out = []
    for n in notes:
        keys = next((v for k, v in _ALREADY_SAID.items() if n.startswith(k)), ())
        if not any(k in answer for k in keys):
            out.append(n)
    return out


def scope_line(results):
    """「查詢範圍：範圍｜指標｜期間｜來源」。查不出來的部分就省略。"""
    platforms, scopes, tables, period = _facts(results)
    if not tables:
        return ""
    if not scopes or scopes == set(SCOPE_LABELS):
        scope = "新聞部（Newsroom + Talks + Connected）"
    else:
        scope = "、".join(SCOPE_LABELS[s] for s in SCOPE_LABELS if s in scopes)
    if platforms and len(platforms) < len(PLATFORMS):
        scope += "｜" + "、".join(p for p in PLATFORMS if p in platforms)
    layers = []
    if DAILY_TABLES & set(tables):
        layers.append("每日流量（觀看發生日）")
    if VIDEO_TABLES & set(tables):
        layers.append("影片層（依發布日累計）")
    parts = [scope, " + ".join(layers) or "—"]
    if period:
        end = min(period[1], dt.date.today())  # 本月只算到今天
        parts.append(f"{period[0]:%Y-%m-%d} ～ {end:%Y-%m-%d}")
    parts.append("、".join(tables))
    return "查詢範圍：" + "｜".join(parts)
