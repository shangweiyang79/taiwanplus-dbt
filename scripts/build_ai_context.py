"""從 dbt 的定義產生給 AI chatbot 讀的說明文件 ai_context/news_dept_social_context.md。

定義的唯一來源是 dbt（models/docs/_definitions.md、_marts.yml 的 metric / saved query、seeds），
這支腳本只負責「翻譯」：把 metric 轉成可直接執行的 BigQuery SQL、把表名換成正式環境的名稱。
改了定義之後重跑一次即可，不要手改產出的 md。

用法（在 taiwanplus_dbt/ 下）：
    python scripts/build_ai_context.py
"""
import csv
import datetime
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "target")
OUT_DIR = os.path.join(ROOT, "ai_context")
OUT_FILE = os.path.join(OUT_DIR, "news_dept_social_context.md")

PROJECT = "taiwanplus_dbt"
# 給 AI 看的表，依重要性排序：總體成效（每日流量）→ 原因分析（影片層）→ 對照表
TABLES = [
    "agg_news_dept_daily_traffic_monthly",
    "fct_daily_traffic",
    "agg_news_dept_social_monthly",
    "fct_social_post_performance",
    "dept_accounts",
    "platform_metric_glossary",
    "youtube_channels",
]


def parse_prod():
    """用 prod target 重新 parse，讓 manifest 裡的表名是正式環境的 dataset。"""
    env = dict(os.environ, DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION="1")
    result = subprocess.run(
        ["dbt", "parse", "--target", "prod"], cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8"
    )
    if result.returncode != 0:
        sys.exit("dbt parse --target prod 失敗：\n" + result.stdout + result.stderr)


def load(name):
    with open(os.path.join(TARGET, name), encoding="utf-8") as f:
        return json.load(f)


def relation(node):
    return f"`{node['database']}.{node['schema']}.{node.get('alias') or node['name']}`"


def find_node(manifest, name):
    for node in manifest["nodes"].values():
        if node["name"] == name and node["package_name"] == PROJECT:
            return node
    raise KeyError(name)


def doc(manifest, name):
    return manifest["docs"][f"doc.{PROJECT}.{name}"]["block_contents"].strip()


# --- semantic → SQL ---------------------------------------------------------

def render_filter(template):
    """{{ Dimension('post__platform') }} = 'X' → platform = 'X'"""
    sql = re.sub(r"\{\{\s*Dimension\('(?:\w+__)?(\w+)'\)\s*\}\}", r"\1", template)
    sql = re.sub(r"\{\{\s*TimeDimension\('(?:\w+__)?(\w+)'(?:,\s*'\w+')?\)\s*\}\}", r"\1", sql)
    return sql.strip().strip('"')


def filters_of(obj):
    if not obj:
        return []
    return [render_filter(w["where_sql_template"]) for w in obj.get("where_filters", [])]


def metric_model(metrics, name):
    """metric 所屬的 semantic model 名稱與預設時間欄位；ratio 依分子。"""
    m = metrics[name]
    if m["type"] == "simple":
        params = m["type_params"]["metric_aggregation_params"]
        return params["semantic_model"], params["agg_time_dimension"]
    if m["type"] == "ratio":
        return metric_model(metrics, m["type_params"]["numerator"]["name"])
    raise ValueError(f"尚未支援的 metric 類型：{m['type']}（{name}）")


def metric_sql(metrics, name):
    m = metrics[name]
    tp = m["type_params"]
    if m["type"] == "simple":
        agg = tp["metric_aggregation_params"]["agg"].upper()
        expr = tp["metric_aggregation_params"]["expr"] or tp["expr"]
        conds = filters_of(m.get("filter"))
        if conds:
            expr = f"IF({' AND '.join(conds)}, {expr}, NULL)"
        if agg == "COUNT_DISTINCT":
            return f"COUNT(DISTINCT {expr})"
        return f"{agg}({expr})"
    if m["type"] == "ratio":
        num = metric_sql(metrics, tp["numerator"]["name"])
        den = metric_sql(metrics, tp["denominator"]["name"])
        return f"SAFE_DIVIDE({num}, {den})"
    raise ValueError(f"尚未支援的 metric 類型：{m['type']}（{name}）")


def group_by_sql(item, time_column):
    """TimeDimension('metric_time', 'month') / Dimension('post__platform') → (select 運算式, 別名)"""
    t = re.match(r"TimeDimension\('metric_time',\s*'(\w+)'\)", item)
    if t:
        grain = t.group(1)
        return f"DATE_TRUNC({time_column}, {grain.upper()})", f"{grain}_start"
    d = re.match(r"Dimension\('(?:\w+__)?(\w+)'\)", item)
    if d:
        return d.group(1), d.group(1)
    raise ValueError(f"尚未支援的 group_by：{item}")


def saved_query_sql(sq, metrics, model_relations):
    qp = sq["query_params"]
    model, time_column = metric_model(metrics, qp["metrics"][0])
    fact_relation = model_relations[model]
    groups = [group_by_sql(g, time_column) for g in qp["group_by"]]
    select = [f"  {expr} AS {alias}" if expr != alias else f"  {expr}" for expr, alias in groups]
    select += [f"  {metric_sql(metrics, m)} AS {m}" for m in qp["metrics"]]
    where = filters_of(qp.get("where"))
    lines = ["SELECT", ",\n".join(select), f"FROM {fact_relation}"]
    if where:
        lines.append("WHERE " + "\n  AND ".join(where))
    if groups:
        lines.append("GROUP BY " + ", ".join(str(i + 1) for i in range(len(groups))))
        lines.append("ORDER BY " + ", ".join(str(i + 1) for i in range(len(groups))))
    return "\n".join(lines)


# --- markdown ----------------------------------------------------------------

def first_paragraph(text):
    return text.strip().split("\n\n")[0].replace("\n", " ")


def csv_table(path):
    with open(path, encoding="utf-8") as f:
        rows = list(csv.reader(f))
    out = ["| " + " | ".join(rows[0]) + " |", "|" + "---|" * len(rows[0])]
    out += ["| " + " | ".join(r) + " |" for r in rows[1:]]
    return "\n".join(out)


def main():
    parse_prod()
    manifest = load("manifest.json")
    sem = load("semantic_manifest.json")
    metrics = {m["name"]: m for m in sem["metrics"]}
    model_relations = {
        sm["name"]: f"`{sm['node_relation']['database']}.{sm['node_relation']['schema_name']}.{sm['node_relation']['alias']}`"
        for sm in sem["semantic_models"]
    }

    md = [
        "# TaiwanPlus 新聞部社群成效：AI 查詢說明",
        "",
        f"> 由 `taiwanplus_dbt/scripts/build_ai_context.py` 自動產生（{datetime.date.today().isoformat()}），**不要手改**。",
        "> 定義的來源是 dbt 專案：`models/docs/_definitions.md`、`models/marts/_marts.yml`、`seeds/`。",
        "> 資料庫是 BigQuery（專案 `ivory-airfoil-418408`，位置 asia-east1），SQL 一律用 GoogleSQL。",
        "",
        "## 1. 業務定義",
        "",
        "### 新聞部",
        "",
        doc(manifest, "news_dept_definition"),
        "",
        "### 每日流量與影片層（兩種觀看數）",
        "",
        doc(manifest, "traffic_vs_video_level"),
        "",
        "### 各平台觀看的計算門檻",
        "",
        doc(manifest, "video_views_definition"),
        "",
        "## 2. 回答流程",
        "",
        doc(manifest, "ai_answering_guide"),
        "",
        "## 3. 資料表",
        "",
    ]

    for name in TABLES:
        node = find_node(manifest, name)
        md += [f"### {relation(node)}", "", first_paragraph(node["description"]), ""]
        cols = node.get("columns") or {}
        if cols:
            md += ["| 欄位 | 說明 |", "|---|---|"]
            for col in cols.values():
                desc = first_paragraph(col.get("description") or "")
                if col["name"] == "views":
                    desc = "影片觀看數，各平台定義不同（見 §1）。"
                md.append(f"| `{col['name']}` | {desc} |")
            md.append("")

    md += [
        "## 4. 指標與對應 SQL",
        "",
        "每個指標都是對「所屬表」的聚合。逐月結果已分別算好在 `agg_news_dept_daily_traffic_monthly`（每日流量）"
        "與 `agg_news_dept_social_monthly`（影片層）。",
        "",
        "| 指標 | 名稱 | 所屬表 | SQL | 說明 |",
        "|---|---|---|---|---|",
    ]
    for name in sorted(metrics, key=lambda n: (metric_model(metrics, n)[0] != "daily_traffic", n)):
        m = metrics[name]
        model, _ = metric_model(metrics, name)
        table = model_relations[model].split(".")[-1].rstrip("`")
        desc = "兩層差異見 §1" if name == "traffic_views" else first_paragraph(m.get("description") or "")
        md.append(f"| `{name}` | {m.get('label') or ''} | `{table}` | `{metric_sql(metrics, name)}` | {desc} |")
    md.append("")

    md += ["## 5. 預設查詢", ""]
    for sq in sem["saved_queries"]:
        md += [
            f"### {sq.get('label') or sq['name']}（`{sq['name']}`）",
            "",
            first_paragraph(sq.get("description") or ""),
            "",
            "```sql",
            saved_query_sql(sq, metrics, model_relations),
            "```",
            "",
        ]

    md += [
        "## 6. 對照表內容",
        "",
        "### dept_accounts（單位 × 平台）",
        "",
        csv_table(os.path.join(ROOT, "seeds", "dept_accounts.csv")),
        "",
        "### platform_metric_glossary（指標 × 平台）",
        "",
        csv_table(os.path.join(ROOT, "seeds", "platform_metric_glossary.csv")),
        "",
        "### youtube_channels（YouTube 頻道 × 單位）",
        "",
        csv_table(os.path.join(ROOT, "seeds", "youtube_channels.csv")),
        "",
    ]

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(md))
    print(f"已產生 {os.path.relpath(OUT_FILE, ROOT)}（{len(metrics)} 個指標、{len(sem['saved_queries'])} 個預設查詢）")

    # 開發時通常是 dev target，產生完切回來，避免下一個 dbt 指令誤用 prod 的 manifest
    subprocess.run(["dbt", "parse"], cwd=ROOT, capture_output=True,
                   env=dict(os.environ, DBT_ENGINE_NO_WARN_SEMANTIC_MANIFEST_VALIDATION="1"))


if __name__ == "__main__":
    main()
