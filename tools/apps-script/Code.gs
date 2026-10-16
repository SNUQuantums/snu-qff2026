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
  var SITE = "https://snuquantums.github.io/snu-qff2026/";
  var QR_URL = SITE + "assets/ideathon/openchat-qr.png";
  var subject = "[Qiskit Fall Fest 2026] 아이디어톤 참가 신청 완료 · 오픈채팅 안내 / Ideathon registration confirmed";
  var deadline = r.ideathon_deadline_at ? kst(r.ideathon_deadline_at) : "10월 29일 (목) 17:00";
  var deadlineEn = r.ideathon_deadline_at
    ? Utilities.formatDate(new Date(r.ideathon_deadline_at), "Asia/Seoul", "EEE, MMM d, HH:mm")
    : "Thu, Oct 29, 17:00";
  var submit = r.ideathon_submission_url || SITE + "ideathon.html";

  var teamKr = r.has_team
    ? "팀 <b>" + esc(r.team_name) + "</b>으로 신청하셨습니다. 이 메일은 적어 주신 팀원에게도 함께 보냈습니다."
    : "팀을 구하는 중으로 신청하셨습니다. 아이디어톤 페이지의 참가자 카드와 오픈채팅에서 팀원을 찾아보세요.";
  var teamEn = r.has_team
    ? "You registered as team <b>" + esc(r.team_name) + "</b>. This email was also sent to the teammates you listed."
    : "You registered as looking for a team. Find teammates through the participant cards on the Ideathon page and in the open chat.";

  // Inline QR (fetched from the site). Falls back to a plain link if the fetch fails.
  var inline = {};
  var qrHtml = "";
  try {
    var blob = UrlFetchApp.fetch(QR_URL).getBlob().setName("openchat-qr.png");
    inline.qr = blob;
    qrHtml = '<img src="cid:qr" width="120" height="120" alt="오픈채팅 QR" style="display:block;width:120px;height:120px;border:1px solid #dcdde5;border-radius:8px;background:#fff">';
  } catch (e) {
    qrHtml = '<img src="' + QR_URL + '" width="120" height="120" alt="오픈채팅 QR" style="display:block;width:120px;height:120px">';
  }

  var chatBlock =
    '<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;border-left:4px solid #67478e;background:#eae2f7;border-radius:8px">' +
    '<tr><td style="padding:16px;width:120px;vertical-align:top">' + qrHtml + "</td>" +
    '<td style="padding:16px 16px 16px 4px;vertical-align:top">' +
    '<div style="font-weight:700;margin-bottom:6px">카카오톡 오픈채팅 / KakaoTalk open chat</div>' +
    '<div>링크 / Link: <a href="' + esc(r.chat_url) + '">' + esc(r.chat_url) + "</a></div>" +
    '<div>입장 비밀번호 / Password: <b style="font-family:ui-monospace,monospace;font-size:16px;letter-spacing:.06em">' + esc(r.chat_password) + "</b></div>" +
    "</td></tr></table>";

  var noticeKr =
    '<div style="margin-top:14px;padding:12px 16px;border-left:4px solid #ffc18e;background:#fff6ec;border-radius:0 8px 8px 0">' +
    "<b>꼭 확인해 주세요</b>" +
    '<ul style="margin:6px 0 0;padding-left:18px">' +
    "<li>모든 공지는 이 오픈채팅에서만 이루어집니다. 꼭 들어와서 확인해 주세요.</li>" +
    "<li>카카오톡 <b>이모지 익명 프로필</b>로 입장해 주세요. 그래야 운영진이 개인 연락을 드릴 수 있습니다.</li>" +
    "<li>입장 후 공지사항을 확인하고, 공지에 적힌 <b>이름 양식</b>에 맞춰 프로필 이름을 바꿔 주세요.</li>" +
    "</ul></div>";

  var noticeEn =
    '<div style="margin-top:14px;padding:12px 16px;border-left:4px solid #ffc18e;background:#fff6ec;border-radius:0 8px 8px 0">' +
    "<b>Please read</b>" +
    '<ul style="margin:6px 0 0;padding-left:18px">' +
    "<li>All announcements are made only in this open chat, so please join and check it.</li>" +
    "<li>Join with a KakaoTalk <b>anonymous emoji profile</b>; that is how the organizers can message you directly.</li>" +
    "<li>After joining, read the pinned notices and rename your profile to the <b>name format</b> given there.</li>" +
    "</ul></div>";

  var html =
    '<div style="font-family:-apple-system,system-ui,\'Apple SD Gothic Neo\',\'Malgun Gothic\',sans-serif;max-width:620px;line-height:1.7;color:#0b1c40">' +
    "<p>" + esc(r.name) + "님, 안녕하세요.<br>Qiskit Fall Fest 2026 아이디어톤 참가 신청이 완료되었습니다.</p>" +
    chatBlock + noticeKr +
    "<p>" + teamKr + "</p>" +
    "<p><b>일정</b><br>제출 마감: " + esc(deadline) + " KST<br>본선 팀 발표: 10월 30일 (금) 13:00<br>피칭: 10월 31일 (토) 14:10–16:40, 서울대 28동 103호</p>" +
    "<p><b>준비물</b><br>IR 피칭 덱과 포스터 린 캔버스 템플릿, 학습 자료, 예시 자료는 <a href=\"" + SITE + "ideathon.html\">아이디어톤 페이지</a>에 있고, " +
    '제출은 <a href="' + esc(submit) + '">제출 양식</a>으로 합니다.</p>' +
    '<hr style="border:0;border-top:1px solid #dcdde5;margin:22px 0">' +
    "<p>Hello " + esc(r.name) + ",<br>your registration for the Qiskit Fall Fest 2026 Ideathon is complete. The KakaoTalk open-chat link and password are in the box above.</p>" +
    noticeEn +
    "<p>" + teamEn + "</p>" +
    "<p><b>Schedule</b><br>Submission deadline: " + esc(deadlineEn) + " KST<br>Finalists announced: Fri, Oct 30, 13:00<br>Pitching: Sat, Oct 31, 14:10–16:40, SNU Building 28, Room 103</p>" +
    "<p><b>Materials</b><br>The pitch deck and lean canvas templates, study material, and example material are on the <a href=\"" + SITE + "ideathon.html\">Ideathon page</a>; " +
    'submit through the <a href="' + esc(submit) + '">submission form</a>.</p>' +
    '<p style="color:#505c73;font-size:13px">문의 / Contact: snuquantums@gmail.com · 주관 SQRT (SNU Quantum Research Team)</p>' +
    "</div>";

  var plain =
    r.name + "님, Qiskit Fall Fest 2026 아이디어톤 참가 신청이 완료되었습니다.\n\n" +
    "[카카오톡 오픈채팅]\n링크: " + r.chat_url + "\n입장 비밀번호: " + r.chat_password + "\n\n" +
    "꼭 확인해 주세요\n" +
    "- 모든 공지는 이 오픈채팅에서만 이루어집니다. 꼭 들어와서 확인해 주세요.\n" +
    "- 카카오톡 이모지 익명 프로필로 입장해 주세요. 그래야 운영진이 개인 연락을 드릴 수 있습니다.\n" +
    "- 입장 후 공지사항을 확인하고, 공지에 적힌 이름 양식에 맞춰 프로필 이름을 바꿔 주세요.\n\n" +
    (r.has_team ? "팀 " + r.team_name + "으로 신청하셨습니다. 이 메일은 적어 주신 팀원에게도 함께 보냈습니다.\n\n"
                : "팀을 구하는 중으로 신청하셨습니다. 아이디어톤 페이지의 참가자 카드와 오픈채팅에서 팀원을 찾아보세요.\n\n") +
    "제출 마감: " + deadline + " KST\n본선 팀 발표: 10월 30일 (금) 13:00\n피칭: 10월 31일 (토) 14:10–16:40, 서울대 28동 103호\n\n" +
    "템플릿·학습 자료·예시 자료: " + SITE + "ideathon.html\n제출 양식: " + submit + "\n\n" +
    "----------------------------------------\n\n" +
    "Hello " + r.name + ", your registration for the Qiskit Fall Fest 2026 Ideathon is complete.\n\n" +
    "[KakaoTalk open chat]\nLink: " + r.chat_url + "\nPassword: " + r.chat_password + "\n\n" +
    "Please read\n" +
    "- All announcements are made only in this open chat, so please join and check it.\n" +
    "- Join with a KakaoTalk anonymous emoji profile; that is how the organizers can message you directly.\n" +
    "- After joining, read the pinned notices and rename your profile to the name format given there.\n\n" +
    (r.has_team ? "You registered as team " + r.team_name + ". This email was also sent to the teammates you listed.\n\n"
                : "You registered as looking for a team. Find teammates through the participant cards on the Ideathon page and in the open chat.\n\n") +
    "Submission deadline: " + deadlineEn + " KST\nFinalists announced: Fri, Oct 30, 13:00\nPitching: Sat, Oct 31, 14:10–16:40, SNU Building 28, Room 103\n\n" +
    "Templates, study and example material: " + SITE + "ideathon.html\nSubmission form: " + submit + "\n\n" +
    "Contact: snuquantums@gmail.com · SQRT (SNU Quantum Research Team)";

  var options = { name: "SQRT · Qiskit Fall Fest 2026", htmlBody: html, replyTo: "snuquantums@gmail.com" };
  if (inline.qr) options.inlineImages = inline;
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
