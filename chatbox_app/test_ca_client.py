"""ca_client.fix_month_axis 的測試：python -m pytest chatbox_app/test_ca_client.py（需設定 GCP_PROJECT）。"""
from ca_client import fix_month_axis


def test_temporal_month_axis_becomes_monthly():
    # 2026-10-27 chatbox 實際出現的寫法：year_month 標成 temporal，橫軸變成週刻度
    spec = {"mark": "line", "encoding": {
        "x": {"field": "year_month", "type": "temporal"},
        "y": {"field": "views", "type": "quantitative"},
        "tooltip": [{"field": "year_month", "type": "temporal"}, {"field": "views", "type": "quantitative"}],
    }}
    fix_month_axis(spec)
    x = spec["encoding"]["x"]
    assert x["type"] == "ordinal" and x["timeUnit"] == "utcyearmonth" and x["axis"]["format"] == "%Y-%m"
    assert spec["encoding"]["tooltip"][0] == {"field": "year_month", "type": "temporal",
                                              "timeUnit": "utcyearmonth", "format": "%Y-%m"}
    assert spec["encoding"]["y"] == {"field": "views", "type": "quantitative"}


def test_layered_spec_and_existing_axis_options():
    spec = {"layer": [{"mark": "line", "encoding": {
        "x": {"field": "month_start", "type": "temporal", "axis": {"title": "月份"}}}}]}
    fix_month_axis(spec)
    axis = spec["layer"][0]["encoding"]["x"]["axis"]
    assert axis["title"] == "月份" and axis["format"] == "%Y-%m"


def test_leaves_other_specs_alone():
    nominal = {"encoding": {"x": {"field": "year_month", "type": "nominal"}}}
    daily = {"encoding": {"x": {"field": "date", "type": "temporal"}}}
    assert fix_month_axis(nominal) == {"encoding": {"x": {"field": "year_month", "type": "nominal"}}}
    assert fix_month_axis(daily) == {"encoding": {"x": {"field": "date", "type": "temporal"}}}


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
