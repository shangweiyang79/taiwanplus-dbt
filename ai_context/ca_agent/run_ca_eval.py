"""以唯讀 SA 的身分，用題庫問 Data Agent，輸出逐題紀錄供評分。

每題開一個新的 stateful conversation，記錄：最終回答、產生的 SQL、是否命中範例查詢、
BigQuery bytes billed、延遲，以及「標準答案的關鍵數字有幾個出現在回答裡」的自動比對。
must_mention / must_not 需要人工（或 Claude）讀紀錄評分，評分表寫在同一份 md 的最後。

題組：
    original    eval_questions.yml 原題（也是 agent 的範例查詢，會偏高）
    paraphrase  eval_variants.yml 換句話說的中文版
    en          eval_variants.yml 英文版

用法（在 taiwanplus_dbt/ 下）：
    python ai_context/ca_agent/run_ca_eval.py                       # 三組全跑
    python ai_context/ca_agent/run_ca_eval.py --sets paraphrase --only q2_newsroom_yt_last_month
"""
import argparse
import datetime
import os
import sys
import time
import uuid

import yaml
from google.cloud import bigquery
from google.cloud import geminidataanalytics as gda

from common import AGENT_NAME, PARENT, PROJECT, operator_credentials, sa_credentials

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SKIP_COLS = {"days_with_data", "year_month", "month_start", "publish_date", "active_to"}


def load_questions():
    with open(os.path.join(ROOT, "ai_context", "eval_questions.yml"), encoding="utf-8") as f:
        questions = yaml.safe_load(f)["questions"]
    with open(os.path.join(HERE, "eval_variants.yml"), encoding="utf-8") as f:
        variants = yaml.safe_load(f)["variants"]
    for q in questions:
        q["texts"] = {"original": q["question"], **variants.get(q["id"], {})}
    return questions


def ask(chat_client, question, thinking=False):
    """開新對話問一題，回傳整理後的結果。"""
    conv = chat_client.create_conversation(
        parent=PARENT,
        conversation_id=f"eval-{uuid.uuid4().hex[:12]}",
        conversation=gda.Conversation(agents=[AGENT_NAME]),
    )
    request = gda.ChatRequest(
        parent=PARENT,
        messages=[gda.Message(user_message=gda.UserMessage(text=question))],
        conversation_reference=gda.ConversationReference(
            conversation=conv.name,
            data_agent_context=gda.DataAgentContext(data_agent=AGENT_NAME),
        ),
        thinking_mode=gda.ChatRequest.ThinkingMode.THINKING if thinking else gda.ChatRequest.ThinkingMode.FAST,
    )
    out = {"final": [], "sql": [], "jobs": [], "errors": [], "matched": [], "charts": 0}
    start = time.time()
    try:
        for msg in chat_client.chat(request=request, timeout=600):
            sm = msg.system_message
            kind = sm._pb.WhichOneof("kind")
            if kind == "text" and sm.text.text_type == gda.TextMessage.TextType.FINAL_RESPONSE:
                out["final"].append("".join(sm.text.parts))
            elif kind == "data":
                if sm.data.generated_sql:
                    out["sql"].append(sm.data.generated_sql)
                if sm.data.big_query_job.job_id:
                    out["jobs"].append(sm.data.big_query_job)
                if sm.data.matched_query.example_query.natural_language_question:
                    out["matched"].append(sm.data.matched_query.example_query.natural_language_question)
            elif kind == "chart":
                out["charts"] += 1
            elif kind == "error":
                out["errors"].append(sm.error.text)
    except Exception as e:  # 記錄下來，不中斷整輪評估
        out["errors"].append(f"{type(e).__name__}: {e}")
    out["seconds"] = round(time.time() - start, 1)
    out["answer"] = "\n\n".join(out["final"]).strip()
    return out


def reference(bq, q):
    rows = [dict(r) for r in bq.query(q["reference_sql"].replace("${GCP_PROJECT}", PROJECT)).result()]
    return rows


def key_numbers(rows):
    nums = []
    for r in rows:
        for k, v in r.items():
            if k in SKIP_COLS or v is None or isinstance(v, bool):
                continue
            if isinstance(v, int) and abs(v) >= 100:
                nums.append(("int", k, v))
            elif isinstance(v, float) and abs(v) < 5:
                nums.append(("rate", k, v))
    return nums


def found(kind, v, text):
    t = text.replace(",", "").replace(" ", "")
    if kind == "int":
        cands = {str(v)}
        for d in (0, 1, 2):
            cands.add(f"{v / 1e4:.{d}f}萬")
            cands.add(f"{v / 1e6:.{d}f}M")
            cands.add(f"{v / 1e6:.{d}f}million")
        cands.add(f"{v / 1e8:.2f}億")
    else:
        cands = {f"{v * 100:.{d}f}%" for d in (0, 1, 2)} | {f"{v:.4f}", f"{v:.3f}"}
    return any(c in t for c in cands)


def bytes_billed(bq_sa, jobs):
    total = 0
    for j in jobs:
        try:
            total += bq_sa.get_job(j.job_id, project=j.project_id or PROJECT, location=j.location or None).total_bytes_billed or 0
        except Exception:
            pass
    return total


def fmt_rows(rows, limit=30):
    if not rows:
        return "（查無資料）"
    cols = list(rows[0].keys())
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for r in rows[:limit]:
        lines.append("| " + " | ".join(_cell(r[c]) for c in cols) + " |")
    return "\n".join(lines)


def _cell(v):
    if isinstance(v, float):
        return f"{v:.4f}" if abs(v) < 10 else f"{v:,.0f}"
    if isinstance(v, int):
        return f"{v:,}"
    return str(v).replace("|", "/")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sets", nargs="*", default=["original", "paraphrase", "en"])
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--thinking", action="store_true", help="用 THINKING 模式（預設 FAST）")
    args = parser.parse_args()

    questions = [q for q in load_questions() if not args.only or q["id"] in args.only]
    chat_client = gda.DataChatServiceClient(credentials=sa_credentials())
    bq_me = bigquery.Client(project=PROJECT, credentials=operator_credentials())
    bq_sa = bigquery.Client(project=PROJECT, credentials=sa_credentials())

    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    out_dir = os.path.join(HERE, "eval_results")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{stamp}.md")

    md = [f"# Data Agent 評估紀錄 {stamp}", "",
          f"- agent：`{AGENT_NAME}`", "- 身分：data-chatbox-ro（唯讀 SA）",
          f"- 題組：{', '.join(args.sets)}｜模式：{'THINKING' if args.thinking else 'FAST'}", ""]
    summary = []
    for q in questions:
        ref = reference(bq_me, q)
        nums = key_numbers(ref)
        md += [f"## {q['id']}", "", "**評分標準**", "",
               "- expected：" + "；".join(f"{k}={v}" for k, v in q["expected"].items()),
               "- must_mention：" + "；".join(q["must_mention"]),
               "- must_not：" + "；".join(q["must_not"]), "",
               "<details><summary>標準答案（reference_sql 當下結果）</summary>", "", fmt_rows(ref), "", "</details>", ""]
        for s in args.sets:
            text = q["texts"].get(s)
            if not text:
                continue
            print(f"[{q['id']} / {s}] {text}", flush=True)
            r = ask(chat_client, text, thinking=args.thinking)
            hit = sum(found(k, v, r["answer"]) for k, _, v in nums)
            gb = bytes_billed(bq_sa, r["jobs"]) / 1e9
            summary.append((q["id"], s, r["seconds"], len(r["sql"]), bool(r["matched"]), hit, len(nums), gb, bool(r["errors"])))
            md += [f"### {s}：{text}", "",
                   f"- 延遲 {r['seconds']} 秒｜SQL {len(r['sql'])} 段｜命中範例：{'是' if r['matched'] else '否'}"
                   f"｜圖表 {r['charts']}｜bytes billed {gb:.2f} GB"
                   f"｜標準答案數字出現 {hit}/{len(nums)}", ""]
            if r["errors"]:
                md += ["**錯誤**：" + " / ".join(r["errors"]), ""]
            md += ["**回答**", "", r["answer"] or "（沒有最終回答）", ""]
            for i, sql in enumerate(r["sql"], 1):
                md += [f"<details><summary>SQL {i}</summary>", "", "```sql", sql.strip(), "```", "", "</details>", ""]

    md += ["## 摘要", "", "| 題目 | 題組 | 秒 | SQL 段數 | 命中範例 | 數字出現 | GB | 錯誤 |", "|---|---|---|---|---|---|---|---|"]
    for qid, s, sec, nsql, matched, hit, n, gb, err in summary:
        md.append(f"| {qid} | {s} | {sec} | {nsql} | {'是' if matched else '否'} | {hit}/{n} | {gb:.2f} | {'有' if err else ''} |")
    md += ["", "## 評分（人工）", "", "| 題目 | 題組 | 層級/範圍/期間正確 | 數字正確 | must_mention | 沒犯 must_not | 結果 |",
           "|---|---|---|---|---|---|---|", ""]

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print(f"\n已輸出 {out_path}")


if __name__ == "__main__":
    sys.exit(main())
