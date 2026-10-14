# Tester checklist (reorg branch)

The `reorg` branch is the Oct 16 release candidate. It runs against the real
Supabase project but, while `testMode: true` is set in
`assets/supabase-config.js`, every call goes to separate `*_test` tables and
functions. A red **TEST MODE** ribbon at the bottom of each page confirms this.
Nothing you do here touches the real teams, participants, or leaderboard.

## Run it locally

Needs Git and Python 3.

```sh
git clone -b reorg https://github.com/SNUQuantums/snu-qff2026.git
cd snu-qff2026
python -m http.server 8000
```

Open <http://localhost:8000/>. Use a real browser (Chrome, Safari, Firefox) and
also your phone if you can: on the same Wi-Fi, replace `localhost` with your
computer's IP address.

Report problems in the group chat with: page, what you did, what you expected,
what happened, browser, and a screenshot. Try both KR and EN (toggle in the
header) for every page you visit.

## 1. Register page (`register.html`)

- [ ] Four tiles show. Ideathon and Hackathon say "접수 중 / Open".
- [ ] On a phone, all four tiles fit on one screen without scrolling.
- [ ] Tap **Ideathon**: an overlay covers about 90% of the screen. Close with ×,
      with Esc, and by clicking the dark backdrop.
- [ ] Ideathon form, no team: fill name, affiliation, self-PR, pick an emoji
      and two tags, phone, email. Press 신청하기. A summary appears. Press 수정하기, change a
      field, press 신청하기 again: the summary reflects the change.
- [ ] Press 확인하고 신청. A green success box appears with a link to the Ideathon
      page.
- [ ] Register again with the **same email**: the error says the address is
      already registered.
- [ ] Ideathon form, with team: choose "네, 팀이 있어요". Team name and three
      teammate rows appear. Leave teammate 2 and 3 empty, fill teammate 1
      completely. Submit succeeds.
- [ ] With team, fill a teammate's name but not the email: the error names the
      teammate row.
- [ ] Tap **Hackathon**: register a team with an 8+ character password. Success.
      Register the same team name again: error says the name is taken.
- [ ] Password shorter than 8 characters is rejected before sending.
- [ ] Tap **Speaker sessions** and **Poster**: the Google Form loads inside the
      overlay and "새 창에서 열기" opens it in a new tab.
- [ ] Open `register.html#hackathon` directly: the Hackathon overlay opens by
      itself. Same for `#ideathon`, `#speakers`, `#poster`.

## 2. Ideathon page (`ideathon.html`)

- [ ] The Korean topic sentence is the same in KR and EN mode, with the English
      translation below it in smaller text.
- [ ] Both `.pptx` template buttons download a file.
- [ ] "양자기술 활용 사례 보기" opens the cases page; its header links back here.
- [ ] 참가 신청 opens the Register page with the Ideathon overlay already open.
- [ ] 제출하기 opens the Google Form in a new tab.
- [ ] Your registration from step 1 appears as a card. Cards of people without
      a team come first and carry a green "팀원 찾는 중" badge.
- [ ] The emoji you picked is the card's avatar. A card registered without
      one shows 🙂.
- [ ] The card never shows phone, email, team name, or teammates.
- [ ] Select one tag: cards with that tag come first. Select two tags: cards
      with both come first, cards with only one appear under "일부 태그만 일치".
      전체 clears the filter.

## 3. Hackathon page (`hackathon.html`)

- [ ] The problem callout shows the "[테스트]" placeholder brief and a repository
      button. (In production this stays locked until Oct 22, 22:00.)
- [ ] 팀 등록하기 opens the Register page with the Hackathon overlay open.
- [ ] Submission block: your test team is in the dropdown. Enter the password,
      seven data qubits such as `1, 2, 3, 6, 10, 9, 11`, and choose any small
      `.qasm` or `.txt` file. Submit. A green banner shows an 8-character ID.
- [ ] Submit again right away: the banner shows a countdown (test cooldown is
      60 seconds) and the count reaches zero on its own.
- [ ] Wrong password: a clear error, nothing submitted.
- [ ] Six data qubits, or a duplicate qubit: rejected before sending.
- [ ] A file over 200 KB is rejected.
- [ ] **내 제출 기록**: team + password shows your submission as 대기 중 /
      queued. (Grading does not run in test mode, so it stays queued. That is
      expected.)
- [ ] Wrong password in the history lookup: an error, no rows.
- [ ] Leaderboard shows "아직 채점된 제출작이 없습니다" (no scored entries) and the
      refresh button updates the time stamp.

## 4. Everything else

- [ ] Nav on every page: 홈, 일정, 아이디어톤, 해커톤, 신청, FAQ, plus the red
      신청하기 button. No link to Speakers, Posters, Leaderboard, or Submit.
- [ ] Home: the pill under the title shows the two deadlines. The three
      "Start here" blocks open the Notion Qiskit page (new tab), Register, and
      Schedule. The four "ways to take part" cards link to Schedule, Hackathon,
      Ideathon, and the poster form.
- [ ] Schedule: Oct 22 and 23 online sessions, three days, four talk titles with
      speakers, rooms 28-101 and 28-103.
- [ ] Footer on every page lists SQRT · SNAAC · NextQuantum · IBM Quantum ·
      Jane Street · QISCA. On Home the six logos show.
- [ ] Mobile menu (☰) opens, closes on Esc, and closes after tapping a link.
- [ ] No page shows "not connected yet" or a blank section.

## For organizers

Test data lives only in `qff_test_*` tables. To wipe it:

```sql
delete from public.qff_test_submissions;
delete from public.qff_test_leaderboard;
delete from public.qff_test_ideathon_participants;
delete from public.qff_test_teams;
```

To switch the site to production, set `testMode: false` in
`assets/supabase-config.js`. The real tables keep their Oct 16 / Oct 22 gates.
