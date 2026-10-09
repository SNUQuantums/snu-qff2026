// Qiskit Fall Fest 2026 @ SNU — browser-facing Supabase wrapper.
// The browser can submit and read its own team's results through guarded RPCs
// and read the sanitized leaderboard table. Team credentials, circuit text, and
// internal judge diagnostics stay private.

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

  function messageOf(error) {
    return (error && (error.message || error.details || error.hint)) || "unknown_error";
  }

  function submitEntry(entry) {
    if (!client) return Promise.resolve({ error: "not_configured" });

    return client
      .rpc(cfg.submitFunction || "submit_solution", {
        p_team_name: entry.teamName,
        p_password: entry.password,
        p_qasm: entry.qasm,
        p_data_qubits: entry.dataQubits,
      })
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        var row = Array.isArray(res.data) ? res.data[0] : res.data;
        return { data: row || null };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  function fetchTeams() {
    if (!client) return Promise.resolve({ error: "not_configured" });

    return client
      .rpc(cfg.listTeamsFunction || "list_active_teams")
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        return { data: (res.data || []).map(function (row) { return row.team_name; }) };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  function fetchLeaderboard() {
    if (!client) return Promise.resolve({ error: "not_configured" });

    return client
      .from(cfg.leaderboardTable || "qff_leaderboard")
      .select("team_name, score_a, score_key, n_2q, submitted_at")
      .order("score_key", { ascending: true })   // 1-F at two significant figures
      .order("n_2q", { ascending: true })
      .order("submitted_at", { ascending: true })
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        return { data: res.data || [] };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  function fetchMySubmissions(teamName, password) {
    if (!client) return Promise.resolve({ error: "not_configured" });

    return client
      .rpc(cfg.teamSubmissionsFunction || "team_submissions", {
        p_team_name: teamName,
        p_password: password,
      })
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        return { data: res.data || [] };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  function fetchNextSubmission(teamName, password) {
    if (!client) return Promise.resolve({ error: "not_configured" });

    return client
      .rpc(cfg.nextSubmissionFunction || "team_next_submission", {
        p_team_name: teamName,
        p_password: password,
      })
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        var row = Array.isArray(res.data) ? res.data[0] : res.data;
        return { data: row || null };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  window.QFF_SUPABASE = {
    isConfigured: isConfigured,
    fetchTeams: fetchTeams,
    submitEntry: submitEntry,
    fetchLeaderboard: fetchLeaderboard,
    fetchMySubmissions: fetchMySubmissions,
    fetchNextSubmission: fetchNextSubmission,
  };
})();
