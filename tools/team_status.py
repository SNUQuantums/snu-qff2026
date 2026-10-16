"""Flip the Ideathon team status of one or more participants.

Examples (run from the repository root; needs the Supabase CLI login that
`npx supabase link` was done with):

  python tools/team_status.py --team  a@snu.ac.kr 홍길동
  python tools/team_status.py --team  a@snu.ac.kr --name "Team Bell"
  python tools/team_status.py --solo  a@snu.ac.kr
  python tools/team_status.py --test --team a@snu.ac.kr      # test tables

People are matched by email (any case) or by exact name. The affected rows
are printed afterwards so a wrong or ambiguous name is visible immediately.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--team", action="store_true", help="mark as having a team")
    mode.add_argument("--solo", action="store_true", help="mark as looking for a team")
    ap.add_argument("--name", default=None, help="team name to record (only with --team)")
    ap.add_argument("--test", action="store_true", help="apply to the qff_test_* tables instead of the real ones")
    ap.add_argument("keys", nargs="+", help="emails or exact names")
    a = ap.parse_args()

    def lit(s: str) -> str:
        return "'" + s.replace("'", "''") + "'"

    fn = "public.admin_set_team_status" + ("_test" if a.test else "")
    keys = "array[" + ",".join(lit(k) for k in a.keys) + "]"
    team_name = lit(a.name) if (a.team and a.name) else "null"
    sql = f"select * from {fn}({keys}, {'true' if a.team else 'false'}, {team_name})"

    res = subprocess.run(
        ["npx", "--yes", "supabase@latest", "db", "query", "--linked", sql, "--output-format", "json"],
        text=True, capture_output=True, encoding="utf-8", shell=(sys.platform == "win32"),
    )
    out = res.stdout
    if '"rows"' not in out:
        print(res.stderr or out, file=sys.stderr)
        return 1
    rows = json.loads(out[out.index("{"):])["rows"]
    if not rows:
        print("No active participant matched:", ", ".join(a.keys))
        return 2
    for r in rows:
        status = "has a team" + (f" ({r['team_name']})" if r.get("team_name") else "") if r["has_team"] else "looking for a team"
        print(f"{r['name']} <{r['email']}> -> {status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
