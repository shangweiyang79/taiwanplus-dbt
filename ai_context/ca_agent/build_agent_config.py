"""產生 Conversational Analytics Data Agent 的設定 agent_config.yaml。

定義不另寫一份，全部取自既有來源：
- system_instruction：ai_context/news_dept_social_context.md 的 §1 業務定義、§2 回答流程
  （由 scripts/build_ai_context.py 從 dbt 產生）＋ 本檔的回答格式要求
- 資料表：scripts/build_ai_context.py 的 TABLES
- 範例查詢（verified queries）：ai_context/eval_questions.yml 的 question + reference_sql
- 術語：本檔的 GLOSSARY（中文口語 ↔ 欄位 / 範圍的對應，dbt 裡沒有這一層）

用法（在 taiwanplus_dbt/ 下）：
    python scripts/build_ai_context.py              # 定義有變時先重產 context md
    python ai_context/ca_agent/build_agent_config.py
    python ai_context/ca_agent/deploy_agent.py
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from build_ai_context import OUT_FILE as CONTEXT_MD, TABLES  # noqa: E402

from common import PROJECT  # noqa: E402

DATASET = "news_dept_social"
OUT = os.path.join(HERE, "agent_config.yaml")

HEADER = """\
你是 TaiwanPlus 新聞部社群成效的資料分析助理，使用者是 TaiwanPlus 內部同事。

回答規則：
- 一律用繁體中文回答（使用者用英文問時才用英文）。
- 只能查 `{project}.{dataset}` 裡的表，只能用 SELECT。
- 數字用千分位（例如 1,234,567），大數字可另附「約 123 萬」。
- 回答最後一行固定附「查詢範圍：範圍｜指標（每日流量或影片層）｜期間｜來源表」。
- 下面的業務定義與回答流程優先於你自己的推斷；有衝突時以下面為準。
"""

GLOSSARY = [
    ("新聞部", "Newsroom + Talks + Connected 三個單位，dept_scope IN ('newsroom','talks','connected')，三個都要算。",
     ["新聞部門", "news department", "news dept"]),
    ("Newsroom", "新聞台，dept_scope = 'newsroom'。YouTube 含 TaiwanPlus News / Livestream / Taiwan Explained 三個頻道。",
     ["新聞台", "TaiwanPlus News"]),
    ("Talks", "dept_scope = 'talks'，平台只有 YouTube 與 Instagram。", ["Taiwan Talks"]),
    ("Connected", "dept_scope = 'connected'，YouTube 持續經營；Instagram 於 2026-07-04 停更。", ["CONNECTED"]),
    ("社群成效", "沒指定指標時 = 每日流量的觀看數（agg_news_dept_daily_traffic_monthly.views），各平台分開列。",
     ["成效", "表現", "performance", "總體成效"]),
    ("觀看數", "影片觀看數 views；各平台門檻不同（YouTube 2026-08-27 起約 1 秒、IG 約 0.3～0.5 秒、X 連續 2 秒、FB 3 秒）。",
     ["views", "觀看", "播放數", "plays"]),
    ("每日流量", "期間內實際發生的觀看（依觀看日），用於總體成效 KPI。表：agg_news_dept_daily_traffic_monthly、fct_daily_traffic。",
     ["daily traffic", "實際觀看"]),
    ("影片層", "期間內發布的影片到今天的累計觀看（依發布日），用於原因分析與影片排行。表：fct_social_post_performance、agg_news_dept_social_monthly。",
     ["video level", "影片累計"]),
    ("互動率", "engagement_rate = SUM(engagements) / SUM(views)，整體加總後相除，不可平均各月比率。",
     ["engagement rate", "互動比率"]),
    ("近期", "沒指定期間時 = 最近三個完整月份（不含本月）。", ["最近", "recent", "lately"]),
    ("Engaged views", "YouTube 的 engaged_views，計算方式接近 2026-08-27 之前的舊 Views，只作輔助參考，KPI 仍是 views。",
     ["engaged views", "有效觀看"]),
]


def system_instruction():
    with open(CONTEXT_MD, encoding="utf-8") as f:
        md = f.read()
    m = re.search(r"^## 1\. .*?(?=^## 3\. )", md, flags=re.S | re.M)
    if not m:
        sys.exit(f"{CONTEXT_MD} 找不到 §1～§2，請先重跑 scripts/build_ai_context.py")
    return HEADER.format(project=PROJECT, dataset=DATASET) + "\n" + m.group(0).strip() + "\n"


def example_queries():
    with open(os.path.join(ROOT, "ai_context", "eval_questions.yml"), encoding="utf-8") as f:
        questions = yaml.safe_load(f)["questions"]
    return [{"question": q["question"], "sql": q["reference_sql"].strip()} for q in questions]


def main():
    config = {
        "project": PROJECT,
        "dataset": DATASET,
        "tables": TABLES,
        "system_instruction": system_instruction(),
        "glossary": [{"term": t, "description": d, "synonyms": s} for t, d, s in GLOSSARY],
        "example_queries": example_queries(),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        yaml.safe_dump(config, f, allow_unicode=True, sort_keys=False, width=200)
    print(f"已產生 {OUT}")
    print(f"  system_instruction {len(config['system_instruction']):,} 字元、{len(TABLES)} 張表、"
          f"{len(GLOSSARY)} 個術語、{len(config['example_queries'])} 個範例查詢")


if __name__ == "__main__":
    main()
