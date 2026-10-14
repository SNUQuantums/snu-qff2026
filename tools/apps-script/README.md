# Ideathon registration emails (Google Apps Script)

New Ideathon registrations are emailed from **snuquantums@gmail.com** by a
Google Apps Script. Each participant receives the KakaoTalk open-chat link and
password (listed teammates are cc'd), and the organizers receive a digest. The
script polls Supabase; nothing runs inside Supabase itself.

Consumer Gmail allows about 100 messages per day from Apps Script, which is
plenty for registrations. If the limit is ever hit, the script simply retries
unsent rows on the next run.

## One-time setup (about 10 minutes)

1. Sign in to Google as **snuquantums@gmail.com** and open
   <https://script.google.com>. Click **New project**. Name it
   `QFF Ideathon notifier`.
2. Replace the contents of `Code.gs` with the file next to this README. Save.
3. Open **Project settings** (gear icon) → **Script properties** → add:

   | Property | Value |
   |---|---|
   | `SUPABASE_URL` | `https://ezebbyoxohgouodwvbfv.supabase.co` |
   | `SUPABASE_ANON_KEY` | the `anonKey` value from `assets/supabase-config.js` |
   | `NOTIFIER_TOKEN` | the secret from `select token from public.qff_notifier;` in the Supabase SQL editor |
   | `FUNCTION_SUFFIX` | `_test` while the site runs in test mode; change to an empty value at launch |
   | `ORGANIZER_EMAIL` | optional; where the digest goes. Defaults to this account |

4. In the editor, choose the function **`checkSetup`** and press **Run**.
   Approve the permissions prompt (the script needs Gmail and external
   requests). The log should say `OK. Pending registrations: N`.
5. Open **Triggers** (clock icon) → **Add trigger**: function `run`, event
   source *Time-driven*, type *Minutes timer*, every **5 minutes**. Save.

From then on every new registration is emailed within five minutes.

## At launch

Set `FUNCTION_SUFFIX` to an empty value so the script reads the real tables,
and make sure `ideathon_chat_url` and `ideathon_chat_password` are set in the
real `qff_settings` row (they are set separately from the migration files and
never committed).

## Changing the message

Edit `sendParticipantMail` in `Code.gs` and save; the next trigger run uses
the new text. The chat link and password come from `qff_settings`, so changing
them is a database update, not a code change:

```sql
update public.qff_settings set ideathon_chat_url = '...', ideathon_chat_password = '...';
```

## Resending

To resend to someone, clear their `notified_at` in `qff_ideathon_participants`;
the next run picks them up again.
