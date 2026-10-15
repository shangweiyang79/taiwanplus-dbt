"""TaiwanPlus 新聞部社群成效 Data Chatbox（Streamlit）。

後端是 Conversational Analytics API 的 Data Agent `news-dept-social`，以唯讀 SA data-chatbox-ro 執行，
只能讀 news_dept_social（唯讀設計見 ai_context/ca_agent/）。

- 快速：CA API FAST 模式取數並回答，再用 notes.py 的規則補上資料提醒。
- 深入分析：CA API FAST 模式取數，再由 narrator.py（Gemini Flash）依 agent 的同一套規則串流撰寫分析。

本機執行（在 taiwanplus_dbt/chatbox_app/ 下）：
    streamlit run app.py
部署：見 README.md
"""
import base64
import json
import pathlib
import time

import pandas as pd
import streamlit as st

from ca_client import ChatClient
from config import credentials
from narrator import narrate, unmatched_numbers
from notes import build_notes, route_mode, scope_line, unsaid

ASSETS = pathlib.Path(__file__).parent / "assets"


def data_uri(name):
    # 用 data URI 而不是檔案路徑：Streamlit 1.57 的 /media 路徑經過 IAP 時會回 500
    # （Expected ASGI message 'http.response.start'…，2026-10-15 實測），data URI 不經過 /media
    return "data:image/png;base64," + base64.b64encode((ASSETS / name).read_bytes()).decode()


ICON = data_uri("taiwanplus_news.png")           # 方形原圖，給分頁圖示
LOGO = data_uri("taiwanplus_news_wide.png")      # 裁掉白邊的橫式版，給側欄與標題
st.set_page_config(page_title="新聞部社群成效 Chatbox｜TaiwanPlus News", page_icon=ICON, layout="wide")
st.logo(LOGO, size="large")

EXAMPLES = [
    "新聞部近期社群成效如何？",
    "Newsroom 上個月 YouTube 的觀看數是多少？",
    "上個月 Newsroom 在 YouTube 觀看數最高的 5 支影片是哪些？",
    "新聞部 YouTube 9 月的觀看數比 7 月成長很多，是真的成長嗎？",
]
MODES = {"自動": None, "快速": False, "深入分析": True}


@st.cache_resource
def get_credentials():
    return credentials()


@st.cache_resource
def get_client():
    return ChatClient(get_credentials())


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


def render(msg, skip_answer=False):
    if msg.get("error"):
        st.error(msg["error"])
    if msg.get("answer") and not skip_answer:
        st.markdown(msg["answer"])
    if msg.get("unmatched"):
        st.warning("以下數字在查詢結果中找不到完全相同的值（可能是 AI 加總或推算，也可能抄錯），請展開「查看資料與 SQL」核對："
                   + "、".join(f"{n:,}" for n in msg["unmatched"]))
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


def ask(question, deep, history):
    """問一題並即時顯示；回傳要存進對話紀錄的 msg。"""
    client = get_client()
    if "conversation" not in st.session_state:
        st.session_state.conversation = client.new_conversation()

    msg = {"role": "assistant", "results": [], "charts": []}
    fast_answer = []
    start = time.time()
    label = "⚡ 查詢資料中…"
    with st.status(label, expanded=False) as status:
        try:
            for kind, payload in client.ask(st.session_state.conversation, question, thinking=False):
                if kind == "progress":
                    status.update(label=f"{label}　{payload.splitlines()[0][:80]}")
                    st.write(payload[:300])
                elif kind == "data":
                    msg["results"].append(payload)
                elif kind == "chart":
                    msg["charts"].append(payload)
                elif kind == "final":
                    fast_answer.append(payload)
                elif kind == "error":
                    msg["error"] = payload
            status.update(label=f"資料取得完成（{time.time() - start:.0f} 秒）", state="complete")
        except Exception as e:
            msg["error"] = f"查詢失敗：{type(e).__name__}: {e}"
            status.update(label="查詢失敗", state="error")
    fetch_seconds = round(time.time() - start, 1)

    answer = "\n\n".join(fast_answer)
    narrated = False
    if deep and any(r["rows"] for r in msg["results"]):
        try:
            answer = st.write_stream(narrate(get_credentials(), question, msg["results"], history))
            narrated = True
        except Exception as e:  # 撰寫失敗就退回快速模式的回答
            log(user=user_email(), question=question, narrator_error=f"{type(e).__name__}: {e}")
            st.markdown(answer)
    else:
        st.markdown(answer)

    seconds = round(time.time() - start, 1)
    msg["answer"] = answer
    msg["unmatched"] = unmatched_numbers(answer, msg["results"]) if narrated else []
    msg["notes"] = unsaid(build_notes(msg["results"]), answer)
    if "查詢範圍" not in answer and "Query Scope" not in answer:
        msg["scope"] = scope_line(msg["results"])
    msg["meta"] = (f"🧠 深入分析｜取數 {fetch_seconds} 秒＋撰寫 {round(seconds - fetch_seconds, 1)} 秒" if narrated
                   else f"⚡ 快速｜{seconds} 秒")
    render(msg, skip_answer=True)
    log(user=user_email(), question=question, deep=deep, narrated=narrated, seconds=seconds,
        fetch_seconds=fetch_seconds, n_results=len(msg["results"]), unmatched=msg["unmatched"], error=msg.get("error"))
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

head_logo, head_title = st.columns([1, 10], vertical_alignment="center")
head_logo.image(LOGO, width=90)
head_title.title("新聞部社群成效 Chatbox")
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
    history = [m["content"] for m in st.session_state.messages if m["role"] == "user"]
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)
    deep = MODES[mode] if MODES[mode] is not None else route_mode(question)
    with st.chat_message("assistant"):
        msg = ask(question, deep, history)
    st.session_state.messages.append(msg)

# 不顯示 CA API 的「建議追問」：有些建議的問題資料表裡根本沒有資料可答（2026-10-15 使用者回饋）
