-- Accept any single emoji as the card avatar (previously a fixed list of 24).
-- Run once in the SQL editor (or `supabase db query --linked -f`). Safe to
-- rerun. Regenerate the _test mirror afterwards.
--
-- The check allows emoji code points (Unicode blocks 1F000-1FAFF, 2600-27BF,
-- 2B00-2BFF), regional-indicator flags, skin-tone modifiers, the zero-width
-- joiner, variation selector 16, and the keycap mark, up to 8 code points so
-- joined sequences such as 🧑‍🚀 still fit. Letters, digits, and spaces are
-- rejected. The browser additionally requires exactly one grapheme.

alter table public.qff_ideathon_participants
  drop constraint if exists qff_ideathon_participants_emoji_check;
alter table public.qff_ideathon_participants
  add constraint qff_ideathon_participants_emoji_check check (
    emoji is null or (
      char_length(emoji) between 1 and 8
      and emoji ~ '^[\U0001F000-\U0001FAFF☀-➿⬀-⯿‍️⃣©®™〰〽㊗㊙]+$'
    )
  );
