# Private end-to-end testing

This workflow runs the website, database/API, scoring worker, and demo data on
one developer machine. It does not deploy the website, connect a cloud
Supabase project, or make the test leaderboard public.

## Prerequisites

- Docker Desktop is installed and running.
- Node.js 20 or newer is installed.
- The sibling `snu-qff` checkout is present beside this repository.

The Supabase CLI is invoked through `npx`, so no global CLI installation is
required. The first start downloads the local Supabase container images.

## 1. Start localhost Supabase

From `qff2026-site`:

```sh
docker network create -o 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1' qff-local
npx --yes supabase@latest start --network-id qff-local
```

The network setting binds published container ports to `127.0.0.1`. If the
`qff-local` network already exists, skip the first command.

The local seed order first applies `supabase-schema.sql`, then creates the only
active local team from `supabase/seed.sql`:

| Team | Password |
|---|---|
| dev | `sqrtsqrt` |

After a reset, `dev` is the submission form's only dropdown option. This account
is for localhost testing only; do not reuse its password in a hosted project.

## 2. Generate ignored local configuration

```sh
python3 scripts/configure_local_supabase.py
```

This reads the local stack's generated keys and writes:

- `assets/supabase-config.local.js` for the browser's public local key.
- `../snu-qff/worker/.env.local` for the worker's local service-role key.

Both files are ignored by Git. The production configuration is untouched.

## 3. Start the private website preview

```sh
python3 -m http.server 8000
```

Open these local URLs:

- Submission: <http://127.0.0.1:8000/submit.html>
- Leaderboard: <http://127.0.0.1:8000/leaderboard.html>
- Local Supabase Studio: <http://127.0.0.1:54323>

## 4. Queue and score a demo submission

In a second terminal:

```sh
cd ../snu-qff
QFF_ENV_FILE=worker/.env.local uv run python worker/seed_demo.py --confirm-demo
QFF_ENV_FILE=worker/.env.local uv run python worker/qff_worker.py --max-jobs 1
```

Expected result:

- `dev` is scored at approximately `A = 242.2933` and appears on the leaderboard.

You can also submit manually through the local form with `dev` / `sqrtsqrt`.
An incorrect password is rejected by the database before anything is queued.
Keep the continuous worker running with:

```sh
QFF_ENV_FILE=worker/.env.local uv run python worker/qff_worker.py
```

## 5. Reset or stop

Reset all local database state and reseed the `dev` team. Recreate the stack
rather than using `db reset`, so the containers retain the loopback-only custom
network:

```sh
npx --yes supabase@latest stop --no-backup
npx --yes supabase@latest start --network-id qff-local
python3 scripts/configure_local_supabase.py
```

Stop the local Supabase containers:

```sh
npx --yes supabase@latest stop
```

Do not add `--linked` to database commands. The linked form targets a remote
project rather than this disposable local database.
