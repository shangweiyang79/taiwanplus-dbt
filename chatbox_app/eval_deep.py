"""用題庫評估「深入分析」流程（CA FAST 取數 + narrator 撰寫），輸出逐題紀錄供評分。

與 ai_context/ca_agent/run_ca_eval.py 同一份題庫；換撰寫模型（config.NARRATOR_MODEL）或改 narrator 的 prompt 後要重跑。

用法（在 taiwanplus_dbt/chatbox_app/ 下）：
    python eval_deep.py                      # 原題 + 換句話說的中文版
    python eval_deep.py --sets en --only q8_youtube_definition_change
"""
import argparse
import datetime
import os
import statistics
import sys
import time

import yaml

from ca_client import ChatClient
from config import NARRATOR_MODEL, credentials
from narrator import narrate, unmatched_numbers

HERE = os.path.dirname(os.path.abspath(__file__))
CA_AGENT = os.path.join(HERE, "..", "ai_context", "ca_agent")


def load_questions():
    with open(os.path.join(HERE, "..", "ai_context", "eval_questions.yml"), encoding="utf-8") as f:
        questions = yaml.safe_load(f)["questions"]
    with open(os.path.join(CA_AGENT, "eval_variants.yml"), encoding="utf-8") as f:
        variants = yaml.safe_load(f)["variants"]
    for q in questions:
        q["texts"] = {"original": q["question"], **variants.get(q["id"], {})}
    return questions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sets", nargs="*", default=["original", "paraphrase"])
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()

    creds = credentials()
    client = ChatClient(creds)
    rows, md = [], [f"# 深入分析流程評估 {datetime.datetime.now():%Y%m%d_%H%M}", "",
                    f"- 流程：CA API FAST 取數 → `{NARRATOR_MODEL}` 撰寫（narrator.py）", "- 身分：data-chatbox-ro", ""]
    for q in load_questions():
        if args.only and q["id"] not in args.only:
            continue
        md += [f"## {q['id']}", "", "- must_mention：" + "；".join(q["must_mention"]),
               "- must_not：" + "；".join(q["must_not"]), ""]
        for s in args.sets:
            text = q["texts"].get(s)
            if not text:
                continue
            print(f"[{q['id']} / {s}] {text}", flush=True)
            t0 = time.time()
            results = []
            for kind, p in client.ask(client.new_conversation(), text, thinking=False):
                if kind == "data":
                    results.append(p)
            t1 = time.time()
            answer = "".join(narrate(creds, text, results)) if any(r["rows"] for r in results) else "（沒有取到資料）"
            t2 = time.time()
            bad = unmatched_numbers(answer, results)
            rows.append((q["id"], s, round(t1 - t0, 1), round(t2 - t1, 1), round(t2 - t0, 1), bad))
            md += [f"### {s}：{text}", "",
                   f"- 取數 {t1 - t0:.1f} 秒＋撰寫 {t2 - t1:.1f} 秒＝{t2 - t0:.1f} 秒｜對不上的數字：{bad or '無'}", "",
                   answer, ""]

    totals = [r[4] for r in rows]
    md += ["## 摘要", "",
           f"- 總時間中位數 {statistics.median(totals):.1f} 秒（{min(totals):.1f}–{max(totals):.1f}）" if totals else "",
           "", "| 題目 | 題組 | 取數 | 撰寫 | 合計 | 對不上的數字 |", "|---|---|---|---|---|---|"]
    md += [f"| {a} | {b} | {c} | {d} | {e} | {', '.join(f'{n:,}' for n in f)} |" for a, b, c, d, e, f in rows]
    md += ["", "## 評分（人工）", ""]
    out = os.path.join(CA_AGENT, "eval_results", f"{datetime.datetime.now():%Y%m%d_%H%M}_deep.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print("已輸出", out)


if __name__ == "__main__":
    sys.exit(main())
