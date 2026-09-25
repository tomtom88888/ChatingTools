# Ditto

A Flutter app (Android + iOS) that suggests WhatsApp replies written in *your*
texting style, learned from your own chat exports.

Your chat history stays on the phone. The only things that ever leave it are the
API calls to OpenAI, made with your own key: the text being embedded during
training, the screenshot you pick (or the chat you paste), and the prompt used
to write a reply.

---

## How it works

1. **Setup** — paste your OpenAI API key once. It goes into the platform
   keystore (Keychain on iOS, encrypted storage on Android) and is never logged,
   never written into the repo, and never put in an error message.
2. **Train** — import a WhatsApp chat export (`.txt`, or the `.zip` WhatsApp
   makes when the chat has media) with the file picker or the share sheet. Pick
   which name in the export is you. Each person you import becomes its own
   chat; importing a newer export of the same chat only sends the replies it
   hasn't seen before.
3. **Choose your voices** — the home screen lists every learned chat with a
   tick box. Replies are written only from the ticked chats, because how you
   text a partner is not how you text your boss.
4. **Generate** — pick a screenshot of the conversation you're in, share one
   straight into the app from your gallery, or paste the messages as text. The
   app shows you what it read so you can fix any mistakes, then offers three
   messages. Tap one to copy it.

   You can add a note first ("say I'll be late", "ask about the weekend"). The
   note decides what the message says; your retrieved replies still decide how
   it sounds. Two of the three answer what was just said; the third doesn't — it
   moves the chat on to a different subject, and each card is tagged `reply` or
   `new topic` so you can tell them apart. The tag reflects what the model
   actually produced: if it returns no topic change, none is invented.

   Each suggestion can then be:
   - **tweaked** — *Shorter*, *Warmer* or *More like me* rewrites just that one;
   - **copied a bubble at a time** — if you usually send several short
     messages in a row, suggestions come split the same way, and the copy
     button walks through them ("Copy 1 of 3");
   - **starred** — marks it as something you actually sent, and adds it to
     that chat's memory as a new example, so the app keeps learning between
     exports.

### Training: two modes

**Mode A — style memory (default, instant).** The export is parsed into
messages, consecutive messages from one sender are merged into turns, and every
`their turn(s) → my reply` pair becomes an exchange. Each exchange's context is
embedded once and the vector is stored in a local sqflite database, under the
chat it came from, with a content hash so a re-import skips what is already
there. Cheap: embeddings only, a fraction of a cent for a long chat, and next
to nothing for a refresh.

At generation time the current conversation is embedded and searched against
the ticked chats only. Retrieval runs in two stages: a heap-based top-k over
the similarity scores (a dot product over unit vectors, done in Dart) builds a
shortlist, then maximal marginal relevance picks from it so the examples are
varied rather than eight copies of "ok see you then", with a small boost for
recent exchanges so the model leans towards how you text now.

The import also measures your habits — how long your replies usually are, how
often you start lowercase, end with a full stop, use emoji, ask questions or
split a message into several bubbles, and the short phrases you repeat. Those
numbers go into the prompt, which stops the model drifting towards longer,
tidier messages than you would ever send.

**How a reply is written.** The model is not asked to imitate you; it is put
in your place. Each retrieved exchange goes into the request as a real turn
of the conversation — their lines, then your actual reply as the model's own
previous message — with the closest match last, right before the live chat.
The instructions say it *is* you, texting that person, and carry your
measured habits, about 25 of your recent short messages as a sample of your
voice, your note, and (for one option) the request to change the subject.

The model then writes several plain drafts in one request. Each is tidied and
held to your habits where the numbers are clear-cut — a capital you almost
never use is lowered, a full stop you almost never type is dropped, emoji are
removed if you never send any — and the drafts most typical of your length,
bubbles and emoji are kept. With fewer than 20 replies measured, drafts are
left as written.

**Chat data** on the home screen shows the numbers behind each chat, counted
from the export on the phone with no API calls: messages and words each, your
typical reply times and how often each of you answers within five minutes,
who starts conversations and who double-texts, questions, laughs, emoji and
late nights, the busiest day and longest daily streak, when in the day and
week you talk, and your favourite words and emoji. It also shows how the
suggestions have fared. A chat imported before this existed shows its numbers
after its export is imported again, which sends nothing new to OpenAI.

**Mode B — fine-tune (optional, costs money).** The same exchanges are written
as chat-format JSONL — a system message describing you texting them, the
previous turns as `user`/`assistant` messages, your real reply as the
`assistant` target — uploaded, and used to start an OpenAI fine-tuning job. The
app shows a cost estimate and requires an explicit confirmation naming the
amount before anything is uploaded, then polls the job and saves the resulting
model id. The dataset is built from the ticked chats, each exchange carrying
the names from its own chat. Generation still sends the retrieved real
examples as context.

> **Fine-tuning is being retired by OpenAI.** Since 8 May 2026 organisations
> that had never fine-tuned before cannot create training jobs, and existing
> customers lose the ability during January 2027. If your account can't use it,
> starting a job fails with OpenAI's own message and nothing is charged. Mode A
> needs no training run and is usually just as convincing.

---

## Look and feel

The app is styled like a messaging app, because everything it makes is a
message: a teal accent, green "sent" bubbles for your side of a
conversation and white ones for theirs, rounded Nunito type, and soft cards.
Suggestions appear as the green bubbles they would be once sent, with a
double tick once copied. It follows the phone between light and dark mode,
switching live without losing your place.

Nunito is bundled (Latin subset, SIL Open Font License, see
`assets/fonts/Nunito-OFL.txt`); Hebrew, Arabic and other scripts fall back to
the phone's own font.

---

## Setup

### Requirements

- Flutter SDK with Dart `^3.12.0` (run `flutter --version` to check)
- Android SDK 21+ / iOS 13+
- An OpenAI API key with credit on it

### Getting it running

```bash
git clone https://github.com/tomtom88888/ChatingTools.git
cd ChatingTools
flutter pub get
flutter test          # 235 tests, no network or device needed
flutter run           # on a connected device or emulator
```

The Android and iOS projects are committed, so a clone builds as-is. The bundle
id is `com.example.replylikeme` — the app's working title, kept so updates install
over earlier builds without losing your learned chats. Change it before you
publish anything:

- `android/app/build.gradle.kts` → `namespace` and `applicationId`
- `ios/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER`
  (or set it in Xcode under Runner → Signing & Capabilities)

Then rename `android/app/src/main/kotlin/com/example/replylikeme/` to match.

### Building a release

```bash
flutter analyze                  # lints
flutter build apk --release      # Android
flutter build appbundle --release
flutter build ios --release      # iOS (needs Xcode and a signing identity)
```

Release builds are signed with `android/app/sideload.keystore`, a fixed key
committed next to the app with the password `sideload`. That is deliberate and
it is **not** a release key: it exists so every build — yours, a colleague's, a
CI run — signs identically, which is what lets one sideloaded APK install over
another. Gradle's auto-generated debug keystore is created fresh per machine, so
two CI builds would get different keys and Android would refuse the upgrade with
"App not installed".

Before publishing anywhere, replace it: generate your own keystore, keep it out
of the repository, and inject it from CI secrets.

If you would rather not install the Android SDK, the
[Build APK workflow](.github/workflows/build-apk.yml) runs `analyze`, `test` and
`build apk` on every push; the APK is attached to the run under **Actions → the
run → Artifacts → replylikeme-apk**.

Run that workflow by hand (**Actions → Build APK → Run workflow**) and it also
publishes the APK as a GitHub release tagged `v<version>-<commit>`, which gives
a plain download link instead of an artifact zip that needs a logged-in
browser. It is a prerelease unless you untick **prerelease** when starting the
run. Ordinary pushes never create releases.

### Optional: the iOS share sheet

Picking a file with the file picker works on both platforms out of the box, and
so does the Android share sheet — for exports and for screenshots. Sharing *into* the app on iOS needs a Share
Extension, which has to be created as an Xcode target and cannot be committed as
plain files:

1. In Xcode: **File → New → Target → Share Extension**, deployment target the
   same as Runner.
2. Add an App Group to both Runner and the extension, and set `CUSTOM_GROUP_ID`
   to it in your build settings. `Info.plist` already references
   `$(CUSTOM_GROUP_ID)`.
3. Follow the remaining steps in the
   [receive_sharing_intent](https://pub.dev/packages/receive_sharing_intent)
   README for the extension's own `Info.plist` and entitlements.

---

## How to export a WhatsApp chat

**On Android:** open the chat → tap the contact or group name at the top →
scroll to the bottom → **Export chat** → **Without media**.

**On iOS:** open the chat → tap the contact or group name at the top → scroll to
the bottom → **Export Chat** → **Without Media**.

Then either share it straight into Ditto, or save it (Files, Drive,
Downloads) and pick it with the file picker in the Train screen.

To add another person, export their chat the same way: it becomes a second
chat on the home screen. To refresh one, export it again — only the new
replies are sent to be embedded.

**Choose "Without media".** It produces a single `.txt` and is all the app
needs — media placeholders carry no style information. "Include media" produces
a `.zip`, which the app also reads, but it is far larger for no benefit.

A one-to-one chat works best. Group exports are parsed fine, but the app models
one person replying to one other person.

### What the parser handles

| | |
|---|---|
| Layouts | Android (`12/03/2023, 19:45 - Alice: hi`) and iOS (`[12/03/2023, 19:45:12] Alice: hi`) |
| Clocks | 24-hour, and 12-hour with AM/PM including the narrow no-break space |
| Dates | day-first, month-first and ISO; 2- and 4-digit years; `/`, `.` and `-` |
| Messages | multi-line messages, CRLF line endings, embedded bidi marks |
| Placeholders | `<Media omitted>`, `image omitted`, `<attached: ...>`, `(file attached)` |
| Other | deleted messages, `<This message was edited>`, WhatsApp's own system lines |

Media, deleted and system messages are recorded but excluded from training —
they carry no style. Consecutive messages from one sender merge into a single
turn, split again after a gap of more than an hour, so a burst of three bubbles
is learned as one thing you said rather than three.

---

## Settings

| Setting | Default | Notes |
|---|---|---|
| Vision model | `gpt-5.6-terra` | Reads the screenshot. Must accept image input. |
| Generation model | `gpt-5.6-terra` | Writes the replies. |
| Embedding model | `text-embedding-3-small` | Changing it invalidates the style memory — retrain. |
| Embedding dimensions | 512 | Uses the API's shortening parameter. Smaller means a smaller, faster memory. |
| Fine-tune base model | `gpt-4o-mini-2024-07-18` | The last base model OpenAI documents for supervised fine-tuning. |
| Mode | Style memory | A or B. |
| Context turns | 10 | How much conversation is used, both when training and generating. |
| Retrieved examples | 8 | How many past exchanges the model is shown. |
| Reply options | 3 | |
| Chat input / output price | unset | Dollars per million tokens for your chat model, for the spending tally. |

**Model names age.** These defaults were checked against OpenAI's documentation
in September 2026. Every field is free text, and **Settings → Model list → Load**
pulls the ids your account can actually use from `GET /v1/models`, so you never
have to guess. Cheaper and pricier alternatives worth knowing: `gpt-5.6-luna`
(cost-efficient tier, also vision-capable) and `gpt-6-astra` (flagship).

**Spending** shows what the app has used this month and the months before,
split into fingerprinting, reading screenshots and writing replies. The counts
come from the token figures OpenAI returns with every response. Embedding is
priced from a built-in table; chat model prices change too often to ship, so
enter yours and the tally includes them — until then it is labelled as a
floor (`≥`), never passed off as the whole bill.

There is also **Delete all my data**, which removes every learned chat, the
settings, the spending tally, the record of which suggestions you took and the
saved fine-tuned model id, and optionally the API key. It does
not touch files or models on OpenAI's side — delete those in your OpenAI
dashboard.

---

## Privacy

- The API key lives only in the platform keystore. It is never logged, never
  committed, and never included in an exception message.
- Messages, embeddings and settings live only in app-private storage on the
  device. So do the spending tally (token counts only, never text) and the
  record of which suggestion you copied from each set, which feeds the style
  report.
- What is sent to OpenAI: the exchange text being embedded during training (and
  the conversation behind a reply you star), the screenshot you pick, and the
  prompt (retrieved examples, your measured habits and the current
  conversation) when generating or tweaking. Nothing else, and nothing to
  anyone else.
- Mode B additionally uploads your messages to OpenAI as a training file. The
  confirmation dialog says so before it happens.
- `.gitignore` blocks `*.txt`, `*.zip` and `*.jsonl` everywhere except
  `test/fixtures/`, so a real export cannot be committed by accident. The two
  fixtures that *are* committed are invented — see `test/fixtures/README.md`.

---

## Project layout

```
lib/
  main.dart
  models/
    api_usage.dart           tokens per call, per month
    app_settings.dart        model choices, mode, names, window sizes, prices
    chat_message.dart        one parsed export line
    chat_turn.dart           merged consecutive messages from one sender
    exchange.dart            their turns -> my reply
    extracted_message.dart   one message read off a screenshot
    finetune_job.dart        fine-tuning job state
    parsed_chat.dart         the result of parsing one export
    reply_suggestion.dart    a suggestion and what it is for
    stored_exchange.dart     an exchange plus its embedding; a learned chat
    style_profile.dart       your measured habits, mergeable across chats
    chat_stats.dart          a chat's numbers: reply times, words, when
    suggestion_feedback.dart which suggestion you took, and the totals
  services/
    whatsapp_parser.dart     both export layouts -> messages, turns, exchanges
    chat_export_reader.dart  .txt / .zip -> export text
    pasted_conversation.dart pasted text -> messages
    quoted_replies.dart      splits a reply from the message it quotes
    openai_service.dart      chat, vision, embeddings, files, fine-tuning
    openai_exception.dart    failures, each with a message worth showing
    vector_math.dart         normalise, dot product, heap top-k, blob encoding
    retrieval.dart           shortlist, then varied and recency-aware picks
    exchange_store.dart      the style-memory interface
    embeddings_store.dart    sqflite implementation, with the v1 upgrade
    memory_exchange_store.dart  in-memory implementation for tests
    style_memory_service.dart   Mode A: plan, build, query, save a reply
    reply_generator.dart     prompt construction, variants and tweaks
    finetune_service.dart    Mode B: JSONL, cost estimate, job polling
    secure_key_store.dart    the API key, and only the API key
    settings_store.dart      everything non-secret
    usage_store.dart         the monthly spending tally
    share_intake.dart        Android/iOS share sheet: exports and screenshots
    pricing.dart             token and cost estimates
  state/providers.dart       Riverpod providers and notifiers
  screens/                   root, setup, home, train, generate, finetune,
                             settings, chat data
    generate/                the transcript, reply cards and other parts
    settings/                settings widgets and the spending section
  theme/tokens.dart          the light and dark palettes, type and corners
  widgets/                   the shared widget kit, dialogs, formatting
test/                        235 tests (209 unit, 26 widget)
test/fixtures/               synthetic Android and iOS exports
```

## Errors you might hit

| What you see | What it means |
|---|---|
| "OpenAI rejected that API key" | Wrong or revoked key. Replace it in Settings. |
| "Your OpenAI account has no credit left" | Add billing at platform.openai.com. |
| "OpenAI is rate-limiting this key" | Handled automatically with backoff; if it persists, wait. |
| A reply shows the message it answered at its start | Fixed: a reply's quote box is read separately, shown as a small quote above the bubble, and kept out of the text. If one slips through, tap *Fix the reading*. |
| "Couldn't read that screenshot" | The vision model didn't return usable JSON. Try a clearer screenshot or another vision model. |
| "That file doesn't look like a WhatsApp export" | Wrong file, or an export from another app. |
| "There are no replies of yours to learn from" | The name picked as yours is probably the other person. |
| "cannot use that model or endpoint" | Your account has no access to that model id. Load the model list in Settings. |

### "App not installed" when sideloading

Android refuses an APK signed by a different key to the copy already on the
phone. If you installed a build made before the committed keystore existed,
uninstall the app once and install again — later builds all share one key and
upgrade cleanly. The other cause is the wrong ABI: `app-arm64-v8a-release.apk`
suits essentially every phone since 2017, and `app-release.apk` works on all of
them.

## Tests

```bash
flutter test
```

235 tests, and no network or device is needed for any of them.

The unit tests cover the parser against synthetic Android and iOS exports, the
`.txt`/`.zip` reader and pasted text, the vector maths and retrieval (a heap
top-k checked against a full sort, variety, recency), the style profile and
its merging, the OpenAI client's error mapping, retries and usage reporting
against a scripted transport, prompt construction and tweaks, JSONL generation
and cost estimation, spending and feedback totals, the share sheet, and the
style-memory build, incremental re-import and retrieval across chats. The
sqflite store is tested against a real SQLite database through
`sqflite_common_ffi`, including the upgrade of a single-chat memory from
before chats existed.

The widget tests boot the real app with an in-memory style memory and a
stubbed key: setup, key validation, home with no chats, one chat and two
(ticking and unticking), Settings with the key masked and the spending
section, "delete all my data", chat data, the layout on a narrow phone
with system bars and right-to-left names, and the whole Generate flow from a
paste — bubbles copied one at a time, a tweak, a star, and the feedback log.
