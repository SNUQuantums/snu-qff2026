/**
 * Qiskit Fall Fest 2026 @ SNU — Ideathon registration notifier.
 *
 * Runs under snuquantums@gmail.com as a Google Apps Script time trigger.
 * Every few minutes it asks Supabase for registrations that have not been
 * emailed yet, sends each participant the KakaoTalk open-chat link and
 * password (cc listed teammates), emails the organizers a digest, and marks
 * the rows as notified. See README.md next to this file for setup.
 *
 * Script properties (File > Project settings > Script properties):
 *   SUPABASE_URL       https://<ref>.supabase.co
 *   SUPABASE_ANON_KEY  the public anon key from assets/supabase-config.js
 *   NOTIFIER_TOKEN     the secret stored in qff_notifier.token
 *   FUNCTION_SUFFIX    "_test" while the site is in test mode, "" for launch
 *   ORGANIZER_EMAIL    where the digest goes (default: this account)
 */

var PROPS = PropertiesService.getScriptProperties();

function run() {
  var token = PROPS.getProperty("NOTIFIER_TOKEN");
  var suffix = PROPS.getProperty("FUNCTION_SUFFIX") || "";
  if (!token) throw new Error("NOTIFIER_TOKEN is not set");

  var rows = rpc("ideathon_pending_notifications" + suffix, { p_token: token });
  if (!rows || !rows.length) return;

  var sent = [];
  rows.forEach(function (r) {
    try {
      sendParticipantMail(r);
      sent.push(r.participant_id);
    } catch (e) {
      console.error("Failed for " + r.email + ": " + e);
    }
  });

  if (sent.length) {
    rpc("ideathon_mark_notified" + suffix, { p_token: token, p_ids: sent });
    sendOrganizerDigest(rows.filter(function (r) { return sent.indexOf(r.participant_id) !== -1; }), suffix);
  }
}

function rpc(name, body) {
  var url = PROPS.getProperty("SUPABASE_URL");
  var key = PROPS.getProperty("SUPABASE_ANON_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_ANON_KEY are not set");
  var res = UrlFetchApp.fetch(url + "/rest/v1/rpc/" + name, {
    method: "post",
    contentType: "application/json",
    headers: { apikey: key, Authorization: "Bearer " + key },
    payload: JSON.stringify(body),
    muteHttpExceptions: true,
  });
  if (res.getResponseCode() >= 300) throw new Error(name + " -> " + res.getResponseCode() + " " + res.getContentText());
  var text = res.getContentText();
  return text ? JSON.parse(text) : null;
}

function kst(iso) {
  return Utilities.formatDate(new Date(iso), "Asia/Seoul", "M월 d일 (E) HH:mm");
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}

function sendParticipantMail(r) {
  var subject = "[Qiskit Fall Fest 2026] 아이디어톤 참가 신청 완료 · 단체 채팅방 안내";
  var deadline = r.ideathon_deadline_at ? kst(r.ideathon_deadline_at) : "10월 29일 (목) 17:00";
  var submit = r.ideathon_submission_url || "https://snuquantums.github.io/snu-qff2026/ideathon.html";
  var teamLine = r.has_team
    ? "팀 <b>" + esc(r.team_name) + "</b>으로 신청하셨습니다. 이 메일은 적어주신 팀원에게도 함께 보냈습니다."
    : "아직 팀을 구하는 중으로 신청하셨습니다. 아이디어톤 페이지의 참가자 카드와 단체 채팅방에서 팀원을 찾아보세요.";

  var html =
    '<div style="font-family:-apple-system,system-ui,\'Apple SD Gothic Neo\',\'Malgun Gothic\',sans-serif;max-width:600px;line-height:1.7;color:#0b1c40">' +
    "<p>" + esc(r.name) + "님, 안녕하세요.<br>Qiskit Fall Fest 2026 아이디어톤 참가 신청이 완료되었습니다.</p>" +
    '<div style="padding:16px 18px;border-left:4px solid #67478e;background:#eae2f7;border-radius:8px">' +
    "<b>단체 채팅방 (카카오톡 오픈채팅)</b><br>" +
    '링크: <a href="' + esc(r.chat_url) + '">' + esc(r.chat_url) + "</a><br>" +
    "입장 비밀번호: <b>" + esc(r.chat_password) + "</b></div>" +
    "<p>" + teamLine + "</p>" +
    "<p><b>일정</b><br>" +
    "제출 마감: " + esc(deadline) + " KST<br>" +
    "본선 팀 발표: 10월 30일 (금) 13:00<br>" +
    "피칭: 10월 31일 (토) 14:10–16:40, 서울대 28동 103호</p>" +
    "<p><b>준비물</b><br>" +
    'IR 피칭 덱과 포스터 린 캔버스 템플릿은 <a href="https://snuquantums.github.io/snu-qff2026/ideathon.html">아이디어톤 페이지</a>에서 내려받을 수 있고, ' +
    '제출은 <a href="' + esc(submit) + '">제출 양식</a>으로 합니다.</p>' +
    '<p style="color:#505c73;font-size:13px">문의: snuquantums@gmail.com · 주관 SQRT (SNU Quantum Research Team)</p>' +
    "</div>";

  var plain =
    r.name + "님, Qiskit Fall Fest 2026 아이디어톤 참가 신청이 완료되었습니다.\n\n" +
    "단체 채팅방 (카카오톡 오픈채팅)\n링크: " + r.chat_url + "\n입장 비밀번호: " + r.chat_password + "\n\n" +
    "제출 마감: " + deadline + " KST\n본선 팀 발표: 10월 30일 (금) 13:00\n피칭: 10월 31일 (토) 14:10–16:40, 서울대 28동 103호\n\n" +
    "템플릿: https://snuquantums.github.io/snu-qff2026/ideathon.html\n제출 양식: " + submit + "\n\n문의: snuquantums@gmail.com";

  var options = { name: "SQRT · Qiskit Fall Fest 2026", htmlBody: html, replyTo: "snuquantums@gmail.com" };
  var cc = (r.teammate_emails || []).filter(function (e) { return e && e.toLowerCase() !== String(r.email).toLowerCase(); });
  if (cc.length) options.cc = cc.join(",");
  GmailApp.sendEmail(r.email, subject, plain, options);
}

function sendOrganizerDigest(rows, suffix) {
  var to = PROPS.getProperty("ORGANIZER_EMAIL") || Session.getEffectiveUser().getEmail();
  var lines = rows.map(function (r) {
    return "- " + r.name + " (" + r.affiliation + ") · " + (r.has_team ? "팀: " + r.team_name : "팀원 찾는 중") + " · " + r.email;
  });
  var subject = (suffix ? "[TEST] " : "") + "[QFF 아이디어톤] 새 참가 신청 " + rows.length + "건";
  GmailApp.sendEmail(to, subject, lines.join("\n") + "\n\n참가자 페이지: https://snuquantums.github.io/snu-qff2026/ideathon.html", { name: "QFF 알림" });
}

/** Run once by hand to confirm the properties and token work. Sends nothing. */
function checkSetup() {
  var token = PROPS.getProperty("NOTIFIER_TOKEN");
  var suffix = PROPS.getProperty("FUNCTION_SUFFIX") || "";
  var rows = rpc("ideathon_pending_notifications" + suffix, { p_token: token });
  console.log("OK. Pending registrations: " + rows.length + (suffix ? " (test tables)" : ""));
}
