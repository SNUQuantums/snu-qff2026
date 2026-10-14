// Qiskit Fall Fest 2026 @ SNU — browser-facing Supabase wrapper.
// Everything here goes through guarded RPCs or the sanitized leaderboard table.
// Team passwords, circuit text, contact details, and judge diagnostics never
// reach the browser.

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

  // Runs an RPC and normalises the result to { data } or { error }.
  function rpc(name, args, pickFirst) {
    if (!client) return Promise.resolve({ error: "not_configured" });
    return client
      .rpc(name, args || {})
      .then(function (res) {
        if (res.error) return { error: messageOf(res.error) };
        var data = res.data;
        if (pickFirst) data = Array.isArray(data) ? data[0] || null : data;
        return { data: data == null ? (pickFirst ? null : []) : data };
      })
      .catch(function (error) {
        return { error: messageOf(error) };
      });
  }

  // ---- event timing and gated content ------------------------------------
  function fetchEventStatus() {
    return rpc(cfg.eventStatusFunction || "event_status", {}, true);
  }

  // ---- hackathon ---------------------------------------------------------
  function fetchTeams() {
    return rpc(cfg.listTeamsFunction || "list_active_teams").then(function (res) {
      if (res.error) return res;
      return { data: res.data.map(function (row) { return row.team_name; }) };
    });
  }

  function registerHackathonTeam(entry) {
    return rpc(cfg.registerTeamFunction || "register_hackathon_team", {
      p_team_name: entry.teamName,
      p_password: entry.password,
      p_leader_name: entry.leaderName,
      p_phone: entry.phone,
      p_email: entry.email,
    });
  }

  function submitEntry(entry) {
    return rpc(cfg.submitFunction || "submit_solution", {
      p_team_name: entry.teamName,
      p_password: entry.password,
      p_qasm: entry.qasm,
      p_data_qubits: entry.dataQubits,
    }, true);
  }

  function fetchLeaderboard() {
    if (!client) return Promise.resolve({ error: "not_configured" });
    return client
      .from(cfg.leaderboardTable || "qff_leaderboard")
      .select("team_name, score_a, score_key, n_2q, p_acc, submitted_at")
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
    return rpc(cfg.teamSubmissionsFunction || "team_submissions", {
      p_team_name: teamName,
      p_password: password,
    });
  }

  function fetchNextSubmission(teamName, password) {
    return rpc(cfg.nextSubmissionFunction || "team_next_submission", {
      p_team_name: teamName,
      p_password: password,
    }, true);
  }

  // ---- ideathon ----------------------------------------------------------
  function fetchIdeathonParticipants() {
    return rpc(cfg.listParticipantsFunction || "list_ideathon_participants");
  }

  function registerIdeathon(entry) {
    return rpc(cfg.registerIdeathonFunction || "register_ideathon", {
      p_name: entry.name,
      p_affiliation: entry.affiliation,
      p_self_pr: entry.selfPr,
      p_tags: entry.tags || [],
      p_has_team: !!entry.hasTeam,
      p_team_name: entry.teamName || null,
      p_phone: entry.phone,
      p_email: entry.email,
      p_teammates: entry.teammates || [],
    });
  }

  window.QFF_SUPABASE = {
    isConfigured: isConfigured,
    fetchEventStatus: fetchEventStatus,
    fetchTeams: fetchTeams,
    registerHackathonTeam: registerHackathonTeam,
    submitEntry: submitEntry,
    fetchLeaderboard: fetchLeaderboard,
    fetchMySubmissions: fetchMySubmissions,
    fetchNextSubmission: fetchNextSubmission,
    fetchIdeathonParticipants: fetchIdeathonParticipants,
    registerIdeathon: registerIdeathon,
  };
})();
