"""逐列對帳：dbt 建出的 view 與舊 social_hub view 是否一致。

非小數欄位（含 ARRAY）必須完全相同；FLOAT 欄位允許相對誤差 1e-6
（不同排程查詢的浮點加總順序不同，會有 1e-12 等級的誤差）。

用法：
    python scripts/reconcile_social_hub.py                       # dbt_joy vs social_hub
    python scripts/reconcile_social_hub.py --new dbt_joy --old social_hub_bak_20261012
    python scripts/reconcile_social_hub.py --views vod_category v_vertical_monthly
"""
import argparse
import sys

from google.cloud import bigquery

PROJECT = "ivory-airfoil-418408"
VIEWS = [
    "vod_category",
    "v_metrics_youtube",
    "v_metrics_instagram",
    "v_metrics_facebook",
    "v_metrics_x",
    "v_vod_social_performance",
    "v_vod_social_summary",
    "v_tag_platform_summary",
    "v_platform_post_performance",
    "v_platform_monthly_wide",
    "v_vertical_monthly",
    "v_vertical_category_performance",
    "v_category_gap",
]
REL_TOL = 1e-6


def build_sql(client, new_ds, old_ds, view):
    old_table = client.get_table(f"{PROJECT}.{old_ds}.{view}")
    new_table = client.get_table(f"{PROJECT}.{new_ds}.{view}")
    old_cols = [f.name for f in old_table.schema]
    new_cols = [f.name for f in new_table.schema]
    if old_cols != new_cols:
        return None, f"欄位不同：old={old_cols} new={new_cols}"

    floats = [f.name for f in old_table.schema if f.field_type in ("FLOAT", "FLOAT64") and f.mode != "REPEATED"]
    others = [c for c in old_cols if c not in floats]
    key = f"TO_JSON_STRING(STRUCT({', '.join(f'`{c}`' for c in others)}))"
    order = ", ".join(f"`{c}`" for c in floats) or "1"
    float_sel = "".join(f", `{c}`" for c in floats)

    def side(ds):
        return (
            f"SELECT {key} AS k{float_sel}, "
            f"ROW_NUMBER() OVER (PARTITION BY {key} ORDER BY {order}) AS rn "
            f"FROM `{PROJECT}.{ds}.{view}`"
        )

    mismatch = " OR ".join(
        f"(n.`{c}` IS NULL) != (o.`{c}` IS NULL) "
        f"OR ABS(n.`{c}` - o.`{c}`) > {REL_TOL} * GREATEST(1, ABS(o.`{c}`))"
        for c in floats
    ) or "FALSE"

    sql = f"""
    WITH n AS ({side(new_ds)}), o AS ({side(old_ds)})
    SELECT
      COUNTIF(o.k IS NOT NULL) AS old_rows,
      COUNTIF(n.k IS NOT NULL) AS new_rows,
      COUNTIF(n.k IS NULL) AS only_old,
      COUNTIF(o.k IS NULL) AS only_new,
      COUNTIF(n.k IS NOT NULL AND o.k IS NOT NULL AND ({mismatch})) AS float_mismatch
    FROM n FULL JOIN o USING (k, rn)
    """
    return sql, None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--new", default="dbt_joy")
    parser.add_argument("--old", default="social_hub")
    parser.add_argument("--views", nargs="*", default=VIEWS)
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)
    failed = 0
    print(f"{'view':34} {'old':>7} {'new':>7} {'only_old':>9} {'only_new':>9} {'float_diff':>11}  result")
    for view in args.views:
        sql, err = build_sql(client, args.new, args.old, view)
        if err:
            print(f"{view:34} {err}")
            failed += 1
            continue
        r = list(client.query(sql).result())[0]
        ok = r.only_old == 0 and r.only_new == 0 and r.float_mismatch == 0
        failed += not ok
        print(
            f"{view:34} {r.old_rows:>7} {r.new_rows:>7} {r.only_old:>9} {r.only_new:>9} "
            f"{r.float_mismatch:>11}  {'OK' if ok else 'DIFF'}"
        )
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
