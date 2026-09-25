# Test fixtures

These files are **synthetic**. "Sam", "Robin", "Priya" and "Alex" are invented, and every
message was written for the parser tests. No real conversation is committed to
this repository, and `.gitignore` blocks `*.txt` everywhere except this folder
so a real export can't be added by accident.

* `android_export.txt` — Android layout, 24-hour clock, day-first dates,
  `<Media omitted>`, a deleted message, an edit marker, a multi-line message,
  and two WhatsApp system lines.
* `ios_export.txt` — iOS layout, 12-hour clock, month-first two-digit-year
  dates, `<attached: ...>` and `image omitted`, embedded bidi marks, and a
  multi-line message.
* `group_export.txt` — an Android-layout group chat of four people, with the
  group's creation line, a run of bubbles from one member, media and emoji.
