"""Generate ignored localhost config files from `supabase status -o env`."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


SITE_ROOT = Path(__file__).resolve().parent.parent
WORKSPACE_ROOT = SITE_ROOT.parent
LOCAL_BROWSER_CONFIG = SITE_ROOT / "assets" / "supabase-config.local.js"
LOCAL_WORKER_ENV = WORKSPACE_ROOT / "snu-qff" / "worker" / ".env.local"


def parse_env(output: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key.replace("_", "").isalnum():
            continue
        try:
            parts = shlex.split(value.strip())
            values[key] = parts[0] if parts else ""
        except ValueError:
            values[key] = value.strip().strip("\"'")
    return values


def main() -> int:
    command = ["npx", "--yes", "supabase@latest", "status", "-o", "env"]
    result = subprocess.run(command, cwd=SITE_ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        print(result.stderr or result.stdout, file=sys.stderr)
        print("Start the local Supabase stack before running this script.", file=sys.stderr)
        return result.returncode

    values = parse_env(result.stdout)
    api_url = values.get("API_URL") or values.get("SUPABASE_URL")
    anon_key = values.get("ANON_KEY") or values.get("PUBLISHABLE_KEY")
    service_key = values.get("SERVICE_ROLE_KEY") or values.get("SECRET_KEY")
    if not api_url or not anon_key or not service_key:
        print("Could not find API_URL, ANON_KEY, and SERVICE_ROLE_KEY in Supabase status.", file=sys.stderr)
        return 1

    browser_config = (
        "// Generated for localhost by scripts/configure_local_supabase.py.\n"
        "window.QFF_SUPABASE_CONFIG = {\n"
        f"  url: {json.dumps(api_url)},\n"
        f"  anonKey: {json.dumps(anon_key)},\n"
        '  listTeamsFunction: "list_active_teams",\n'
        '  submitFunction: "submit_solution",\n'
        '  leaderboardTable: "qff_leaderboard",\n'
        "};\n"
    )
    LOCAL_BROWSER_CONFIG.write_text(browser_config)

    worker_env = (
        "# Generated localhost-only credentials. This file is ignored by Git.\n"
        f"SUPABASE_URL={api_url}\n"
        f"SUPABASE_SERVICE_ROLE_KEY={service_key}\n"
        "QFF_WORKER_ID=qff-local-dev\n"
        "QFF_POLL_SECONDS=1\n"
        "QFF_JOB_TIMEOUT_SECONDS=30\n"
        "QFF_LEASE_SECONDS=120\n"
        "QFF_MAX_INSTRUCTIONS=5000\n"
    )
    LOCAL_WORKER_ENV.parent.mkdir(parents=True, exist_ok=True)
    LOCAL_WORKER_ENV.write_text(worker_env)
    try:
        os.chmod(LOCAL_WORKER_ENV, 0o600)
    except OSError:
        pass

    print(f"Wrote {LOCAL_BROWSER_CONFIG}")
    print(f"Wrote {LOCAL_WORKER_ENV} with owner-only permissions")
    print("No production project or public website was changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
