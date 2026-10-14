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

  // Test mode routes every call to the *_test mirror objects (see
  // supabase-test-schema.sql) and shows a ribbon so testers know.
  var T = cfg.testMode ? "_test" : "";
  function fn(name) { return name + T; }
  if (cfg.testMode) {
    document.addEventListener("DOMContentLoaded", function () {
      var r = document.createElement("div");
      r.textContent = "TEST MODE · 테스트 모드 · data goes to the _test tables";
      r.style.cssText = "position:fixed;left:0;right:0;bottom:0;z-index:9999;padding:.45rem 1rem;background:#a3341c;color:#fff;font:600 .78rem/1.3 ui-monospace,monospace;text-align:center;letter-spacing:.04em";
      document.body.appendChild(r);
    });
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
    return rpc(fn(cfg.eventStatusFunction || "event_status"), {}, true);
  }

  // ---- hackathon ---------------------------------------------------------
  function fetchTeams() {
    return rpc(fn(cfg.listTeamsFunction || "list_active_teams")).then(function (res) {
      if (res.error) return res;
      return { data: res.data.map(function (row) { return row.team_name; }) };
    });
  }

  function registerHackathonTeam(entry) {
    return rpc(fn(cfg.registerTeamFunction || "register_hackathon_team"), {
      p_team_name: entry.teamName,
      p_password: entry.password,
      p_leader_name: entry.leaderName,
      p_phone: entry.phone,
      p_email: entry.email,
    });
  }

  function submitEntry(entry) {
    return rpc(fn(cfg.submitFunction || "submit_solution"), {
      p_team_name: entry.teamName,
      p_password: entry.password,
      p_qasm: entry.qasm,
      p_data_qubits: entry.dataQubits,
    }, true);
  }

  function fetchLeaderboard() {
    if (!client) return Promise.resolve({ error: "not_configured" });
    return client
      .from(cfg.leaderboardTable || (cfg.testMode ? "qff_test_leaderboard" : "qff_leaderboard"))
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
    return rpc(fn(cfg.teamSubmissionsFunction || "team_submissions"), {
      p_team_name: teamName,
      p_password: password,
    });
  }

  function fetchNextSubmission(teamName, password) {
    return rpc(fn(cfg.nextSubmissionFunction || "team_next_submission"), {
      p_team_name: teamName,
      p_password: password,
    }, true);
  }

  // ---- ideathon ----------------------------------------------------------
  function fetchIdeathonParticipants() {
    return rpc(fn(cfg.listParticipantsFunction || "list_ideathon_participants"));
  }

  function registerIdeathon(entry) {
    return rpc(fn(cfg.registerIdeathonFunction || "register_ideathon"), {
      p_name: entry.name,
      p_affiliation: entry.affiliation,
      p_self_pr: entry.selfPr,
      p_tags: entry.tags || [],
      p_has_team: !!entry.hasTeam,
      p_team_name: entry.teamName || null,
      p_phone: entry.phone,
      p_email: entry.email,
      p_teammates: entry.teammates || [],
      p_emoji: entry.emoji || null,
    });
  }

  function fetchIdeathonWelcome(participantId) {
    return rpc(fn(cfg.welcomeFunction || "ideathon_welcome"), { p_participant_id: participantId }, true);
  }

  window.QFF_SUPABASE = {
    isConfigured: isConfigured,
    testMode: !!cfg.testMode,
    fetchEventStatus: fetchEventStatus,
    fetchTeams: fetchTeams,
    registerHackathonTeam: registerHackathonTeam,
    submitEntry: submitEntry,
    fetchLeaderboard: fetchLeaderboard,
    fetchMySubmissions: fetchMySubmissions,
    fetchNextSubmission: fetchNextSubmission,
    fetchIdeathonParticipants: fetchIdeathonParticipants,
    registerIdeathon: registerIdeathon,
    fetchIdeathonWelcome: fetchIdeathonWelcome,
  };
})();
