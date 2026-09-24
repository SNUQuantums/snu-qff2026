// Qiskit Fall Fest 2026 @ SNU - Supabase connection config
//
// Fill these in with YOUR OWN Supabase project's values before the
// submission form / leaderboard will actually work:
//   1. Create a free project at https://supabase.com
//   2. Run supabase-schema.sql (site root) in the Supabase SQL editor.
//   3. Go to Project Settings -> API and copy the "Project URL" and the
//      "anon public" key (NOT the service_role key) into the values below.
//
// The anon key is safe to ship in frontend code - Supabase is designed for
// this. Row Level Security policies (defined in supabase-schema.sql) are
// what actually control what the public key is allowed to do: call the secure
// submission function and read the public leaderboard. Never put the
// service_role key in frontend code.
//
// The local worker in the snu-qff repository polls the private queue, runs the
// public judge, and updates the public leaderboard.

// A generated localhost-only config may already have set this value.
window.QFF_SUPABASE_CONFIG = window.QFF_SUPABASE_CONFIG || {
  url: "https://YOUR-PROJECT-REF.supabase.co",
  anonKey: "YOUR-ANON-PUBLIC-KEY",
  listTeamsFunction: "list_active_teams",
  submitFunction: "submit_solution",
  leaderboardTable: "qff_leaderboard",
};
