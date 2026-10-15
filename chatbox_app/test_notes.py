"""notes.py 的測試：python -m pytest chatbox_app/test_notes.py（或直接 python chatbox_app/test_notes.py）。"""
import datetime as dt

from notes import build_notes, route_mode, scope_line, unsaid

TODAY = dt.date(2026, 10, 15)


def test_route_mode_eval_questions():
    # 題庫中需要判斷的題目要走 THINKING
    for q in ["新聞部近期社群成效如何？", "新聞部哪個平台表現最好？", "為什麼 Talks 9 月表現變好？",
              "新聞部 YouTube 9 月的觀看數比 7 月成長很多，是真的成長嗎？", "Connected 最近在 IG 的表現怎麼樣？",
              "Why did Talks perform better in September?"]:
        assert route_mode(q), q
    # 單純查數走 FAST
    for q in ["Newsroom 上個月 YouTube 的觀看數是多少？", "Talks 今年 IG 的互動率是多少？",
              "上個月 Newsroom 在 YouTube 觀看數最高的 5 支影片是哪些？", "How many YouTube views did Newsroom get last month?"]:
        assert not route_mode(q), q


def test_youtube_crossing_break():
    res = [{"rows": [{"year_month": "2026-07", "platform": "YouTube"}, {"year_month": "2026-09", "platform": "YouTube"}],
            "sql": "FROM `p.news_dept_social.agg_news_dept_daily_traffic_monthly`"}]
    notes = build_notes(res, TODAY)
    assert any("跨過 2026-08-27" in n for n in notes)
    assert not any("各平台觀看門檻" in n for n in notes)  # 只有一個平台


def test_ig_old_method_and_multi_platform():
    res = [{"rows": [{"year_month": "2026-05", "platform": "Instagram", "dept_scope": "newsroom"},
                     {"year_month": "2026-05", "platform": "Facebook", "dept_scope": "newsroom"}],
            "sql": "FROM `p.news_dept_social.agg_news_dept_daily_traffic_monthly` WHERE year_month = '2026-05'"}]
    notes = build_notes(res, TODAY)
    assert any("2026-06-01" in n for n in notes)
    assert any("各平台觀看門檻" in n for n in notes)
    assert not any("Connected" in n for n in notes)  # 只有 newsroom
    assert not any("YouTube 自" in n for n in notes)


def test_current_month_and_scope_line():
    res = [{"rows": [{"date": "2026-10-03", "platform": "X", "dept_scope": "newsroom"}],
            "sql": "SELECT * FROM `p.news_dept_social.fct_daily_traffic` WHERE dept_scope = 'newsroom' AND platform = 'X'"}]
    assert any("本月" in n for n in build_notes(res, TODAY))
    line = scope_line(res)
    assert line.startswith("查詢範圍：Newsroom｜X｜每日流量")
    assert "fct_daily_traffic" in line


def test_scope_line_all_units_video_layer():
    res = [{"rows": [{"publish_date": "2026-09-01", "dept_scope": "talks"}, {"publish_date": "2026-09-20", "dept_scope": "newsroom"},
                     {"publish_date": "2026-09-21", "dept_scope": "connected"}],
            "sql": "FROM `p.news_dept_social.fct_social_post_performance`"}]
    assert scope_line(res).startswith("查詢範圍：新聞部（Newsroom + Talks + Connected）｜影片層")


def test_period_from_sql_literals_and_unsaid():
    # 實測：SQL 用 WHERE year_month = '2026-05' 篩，結果沒有日期欄位
    res = [{"rows": [], "sql": "SELECT platform, views FROM `p.news_dept_social.agg_news_dept_daily_traffic_monthly` "
                                "WHERE year_month = '2026-05'"},
           {"rows": [{"platform": "Instagram", "dept_scope": "newsroom", "views": 1.0},
                     {"platform": "YouTube", "dept_scope": "talks", "views": 2.0}], "sql": ""}]
    notes = build_notes(res, TODAY)
    assert any("2026-06-01" in n for n in notes)
    assert not any("YouTube 自" in n for n in notes)  # 5 月在 8/27 之前
    answer = "各平台計算門檻與受眾不同，分開列出。"
    left = unsaid(notes, answer)
    assert not any(n.startswith("各平台觀看門檻") for n in left)
    assert any("2026-06-01" in n for n in left)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
