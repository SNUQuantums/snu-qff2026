// Qiskit Fall Fest 2026 @ SNU - Supabase connection config
//
// Fill these in with YOUR OWN Supabase project's values before the
// submission form / leaderboard will actually work:
//   1. Create a free project at https://supabase.com
//   2. Run supabase-schema.sql (site root) in the Supabase SQL editor to
//      create the `submissions` table and its Row Level Security policies.
//   3. Go to Project Settings -> API and copy the "Project URL" and the
//      "anon public" key (NOT the service_role key) into the values below.
//
// The anon key is safe to ship in frontend code - Supabase is designed for
// this. Row Level Security policies (defined in supabase-schema.sql) are
// what actually control what the anon key is allowed to do: insert new
// submissions, and read rows for the public leaderboard. Never put the
// service_role key in frontend code.
//
// A backend process (not part of this frontend) is expected to poll the
// `submissions` table, run each pending QASM circuit, and write back
// `status` ("scored" / "error") and `score`.

window.QFF_SUPABASE_CONFIG = {
  url: "https://YOUR-PROJECT-REF.supabase.co",
  anonKey: "YOUR-ANON-PUBLIC-KEY",
  table: "submissions",
};
