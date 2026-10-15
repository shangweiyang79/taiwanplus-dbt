"""TaiwanPlus 新聞部社群成效 Data Chatbox（Streamlit）。

後端是 Conversational Analytics API 的 Data Agent `news-dept-social`，以唯讀 SA data-chatbox-ro 執行，
只能讀 news_dept_social（唯讀設計見 ai_context/ca_agent/）。

本機執行（在 taiwanplus_dbt/chatbox_app/ 下）：
    streamlit run app.py
部署：見 README.md
"""
import json
import time

import pandas as pd
import streamlit as st

from ca_client import ChatClient
from config import credentials
from notes import build_notes, route_mode, scope_line, unsaid

st.set_page_config(page_title="新聞部社群成效 Chatbox", page_icon="📊", layout="wide")

EXAMPLES = [
    "新聞部近期社群成效如何？",
    "Newsroom 上個月 YouTube 的觀看數是多少？",
    "上個月 Newsroom 在 YouTube 觀看數最高的 5 支影片是哪些？",
    "新聞部 YouTube 9 月的觀看數比 7 月成長很多，是真的成長嗎？",
]
MODES = {"自動": None, "快速": False, "深入分析": True}


@st.cache_resource
def get_client():
    return ChatClient(credentials())


def user_email():
    raw = st.context.headers.get("X-Goog-Authenticated-User-Email", "local")
    return raw.split(":", 1)[-1]


def log(**fields):
    # Cloud Run 會把 stdout 的 JSON 收進 Cloud Logging，之後可依 question / mode / seconds 分析
    print(json.dumps({"component": "data-chatbox", **fields}, ensure_ascii=False), flush=True)


def to_frame(rows):
    df = pd.DataFrame(rows)
    for col in df.columns:
        s = df[col]
        if pd.api.types.is_float_dtype(s) and s.dropna().apply(float.is_integer).all():
            df[col] = s.astype("Int64")
    return df


def render(msg):
    if msg.get("error"):
        st.error(msg["error"])
    if msg.get("answer"):
        st.markdown(msg["answer"])
    if msg.get("notes"):
        st.info("**資料提醒**\n\n" + "\n".join(f"- {n}" for n in msg["notes"]))
    if msg.get("scope"):
        st.caption(msg["scope"])
    for spec in msg.get("charts", []):
        try:
            st.vega_lite_chart(spec=spec)
        except Exception:  # 圖表格式偶爾不相容，不影響其他內容
            pass
    tables = [r for r in msg.get("results", []) if r["rows"]]
    sqls = [r["sql"] for r in msg.get("results", []) if r.get("sql")]
    if tables or sqls:
        with st.expander("查看資料與 SQL"):
            for r in tables:
                st.dataframe(to_frame(r["rows"]), hide_index=True)
            for sql in sqls:
                st.code(sql, language="sql")
    if msg.get("meta"):
        st.caption(msg["meta"])


def ask(question, thinking):
    client = get_client()
    if "conversation" not in st.session_state:
        st.session_state.conversation = client.new_conversation()

    msg = {"role": "assistant", "results": [], "charts": [], "followups": []}
    answer_parts = []
    start = time.time()
    label = "🧠 深入分析中（約 20–50 秒）…" if thinking else "⚡ 查詢中（約 5–20 秒）…"
    with st.status(label, expanded=False) as status:
        try:
            for kind, payload in client.ask(st.session_state.conversation, question, thinking=thinking):
                if kind == "progress":
                    first = payload.splitlines()[0][:80]
                    status.update(label=f"{label}　{first}")
                    st.write(payload[:300])
                elif kind == "data":
                    msg["results"].append(payload)
                elif kind == "chart":
                    msg["charts"].append(payload)
                elif kind == "final":
                    answer_parts.append(payload)
                elif kind == "followups":
                    msg["followups"] = payload
                elif kind == "error":
                    msg["error"] = payload
            status.update(label="完成", state="complete")
        except Exception as e:
            msg["error"] = f"查詢失敗：{type(e).__name__}: {e}"
            status.update(label="失敗", state="error")

    seconds = round(time.time() - start, 1)
    answer = "\n\n".join(answer_parts)
    msg["answer"] = answer
    msg["notes"] = unsaid(build_notes(msg["results"]), answer)
    if "查詢範圍" not in answer and "Query Scope" not in answer:
        msg["scope"] = scope_line(msg["results"])
    msg["meta"] = f"{'🧠 深入分析' if thinking else '⚡ 快速'}模式｜{seconds} 秒"
    log(user=user_email(), question=question, thinking=thinking, seconds=seconds,
        n_results=len(msg["results"]), error=msg.get("error"))
    return msg


# ---- 版面 -----------------------------------------------------------------
with st.sidebar:
    st.header("設定")
    mode = st.radio("回答模式", list(MODES), index=0,
                    help="自動：問「為什麼、是真的嗎、哪個最好、成效如何」等需要判斷的問題時用深入分析，其餘用快速。")
    if st.button("開新對話", use_container_width=True):
        st.session_state.pop("conversation", None)
        st.session_state.messages = []
        st.rerun()
    st.divider()
    st.markdown("**範例問題**")
    for q in EXAMPLES:
        if st.button(q, key=f"ex-{q}", use_container_width=True):
            st.session_state.pending = q
    st.divider()
    st.caption(
        "資料：新聞部（Newsroom + Talks + Connected）在 YouTube / Instagram / Facebook / X 的觀看與互動，"
        "來源 BigQuery `news_dept_social`。只能讀取，不會修改任何資料。"
        f"\n\n登入：{user_email()}"
    )

st.title("📊 新聞部社群成效 Chatbox")
st.caption("用中文或英文問新聞部的社群成效。數字來自 BigQuery 即時查詢；AI 的解讀請搭配「查看資料與 SQL」核對。")

st.session_state.setdefault("messages", [])
for m in st.session_state.messages:
    with st.chat_message(m["role"]):
        if m["role"] == "assistant":
            render(m)
        else:
            st.markdown(m["content"])

question = st.chat_input("例如：Talks 今年 IG 的互動率是多少？") or st.session_state.pop("pending", None)
if question:
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)
    thinking = MODES[mode] if MODES[mode] is not None else route_mode(question)
    with st.chat_message("assistant"):
        msg = ask(question, thinking)
        render(msg)
    st.session_state.messages.append(msg)

# 建議追問（只顯示最新一則回答的）
last = st.session_state.messages[-1] if st.session_state.messages else None
if last and last["role"] == "assistant" and last.get("followups"):
    st.markdown("**可以接著問：**")
    cols = st.columns(len(last["followups"][:3]))
    for col, q in zip(cols, last["followups"][:3]):
        if col.button(q, key=f"fu-{len(st.session_state.messages)}-{q}"):
            st.session_state.pending = q
            st.rerun()
