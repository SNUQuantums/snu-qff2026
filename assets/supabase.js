// Qiskit Fall Fest 2026 @ SNU - thin Supabase wrapper
//
// Used by submit.html (insert a QASM entry) and leaderboard.html (read
// scored/pending entries). Loaded after:
//   1. the Supabase UMD script (CDN)
//   2. assets/supabase-config.js
//
// Exposes window.QFF_SUPABASE = { isConfigured, submitEntry, fetchLeaderboard }

(function () {
  var cfg = window.QFF_SUPABASE_CONFIG || {};
  var isConfigured =
    !!(cfg.url && cfg.anonKey) &&
    cfg.url.indexOf("YOUR-PROJECT-REF") === -1 &&
    cfg.anonKey.indexOf("YOUR-ANON-PUBLIC-KEY") === -1;

  var client = null;
  if (isConfigured && window.supabase && typeof window.supabase.createClient === "function") {
    client = window.supabase.createClient(cfg.url, cfg.anonKey);
  } else {
    isConfigured = false;
  }

  function submitEntry(entry) {
    if (!client) {
      return Promise.resolve({ error: "not_configured" });
    }
    var payload = {
      team_name: entry.teamName,
      contact_email: entry.email || null,
      qasm: entry.qasm,
      status: "pending",
    };
    return client
      .from(cfg.table)
      .insert(payload)
      .select()
      .single()
      .then(function (res) {
        if (res.error) return { error: res.error.message };
        return { data: res.data };
      })
      .catch(function (err) {
        return { error: (err && err.message) || "unknown_error" };
      });
  }

  function fetchLeaderboard() {
    if (!client) {
      return Promise.resolve({ error: "not_configured" });
    }
    return client
      .from(cfg.table)
      .select("team_name, score, status, submitted_at")
      .order("score", { ascending: false, nullsFirst: false })
      .order("submitted_at", { ascending: true })
      .then(function (res) {
        if (res.error) return { error: res.error.message };
        return { data: res.data || [] };
      })
      .catch(function (err) {
        return { error: (err && err.message) || "unknown_error" };
      });
  }

  window.QFF_SUPABASE = {
    isConfigured: isConfigured,
    submitEntry: submitEntry,
    fetchLeaderboard: fetchLeaderboard,
  };
})();
