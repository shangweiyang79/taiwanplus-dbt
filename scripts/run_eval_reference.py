"""執行 ai_context/eval_questions.yml 每題的 reference_sql，印出當下的標準答案。

用法（在 taiwanplus_dbt/ 下）：
    python scripts/run_eval_reference.py                 # 查正式環境 news_dept_social
    python scripts/run_eval_reference.py --dataset dbt_joy   # 查開發環境
    python scripts/run_eval_reference.py --only q1_news_dept_recent
"""
import argparse
import os

import yaml
from google.cloud import bigquery

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = "ivory-airfoil-418408"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="news_dept_social")
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()

    with open(os.path.join(ROOT, "ai_context", "eval_questions.yml"), encoding="utf-8") as f:
        questions = yaml.safe_load(f)["questions"]

    client = bigquery.Client(project=PROJECT)
    for q in questions:
        if args.only and q["id"] not in args.only:
            continue
        sql = q["reference_sql"].replace(f"{PROJECT}.news_dept_social.", f"{PROJECT}.{args.dataset}.")
        print(f"\n## {q['id']}：{q['question']}")
        for key, value in q["expected"].items():
            print(f"   {key}: {value}")
        rows = list(client.query(sql).result())
        if not rows:
            print("   （查無資料）")
            continue
        cols = list(rows[0].keys())
        print("   " + " | ".join(cols))
        for r in rows:
            print("   " + " | ".join(_fmt(r[c]) for c in cols))


def _fmt(v):
    if isinstance(v, float):
        return f"{v:.4f}" if abs(v) < 10 else f"{v:,.0f}"
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


if __name__ == "__main__":
    main()
