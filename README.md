# ReplyLikeMe

A Flutter app (Android + iOS) that suggests WhatsApp replies written in *your*
texting style, learned from your own chat exports.

Your chat history stays on the phone. The only things that ever leave it are the
API calls to OpenAI, made with your own key: the text being embedded during
training, the screenshot you pick, and the prompt used to write a reply.

---

## How it works

1. **Setup** — paste your OpenAI API key once. It goes into the platform
   keystore (Keychain on iOS, encrypted storage on Android) and is never logged,
   never written into the repo, and never put in an error message.
2. **Train** — import a WhatsApp chat export (`.txt`, or the `.zip` WhatsApp
   makes when the chat has media) with the file picker or the share sheet. Pick
   which name in the export is you.
3. **Generate** — pick a screenshot of the conversation you're in. The app reads
   it, shows you what it read so you can fix any mistakes, then offers three
   replies. Tap one to copy it.

### Training: two modes

**Mode A — style memory (default, instant).** The export is parsed into
messages, consecutive messages from one sender are merged into turns, and every
`their turn(s) → my reply` pair becomes an exchange. Each exchange's context is
embedded once and the vector is stored in a local sqflite database. At
generation time the current conversation is embedded and cosine similarity
search (a dot product over unit vectors, done in Dart) finds the closest past
exchanges. Cheap: embeddings only, a fraction of a cent for a long chat.

**Mode B — fine-tune (optional, costs money).** The same exchanges are written
as chat-format JSONL — a system message describing you texting them, the
previous turns as `user`/`assistant` messages, your real reply as the
`assistant` target — uploaded, and used to start an OpenAI fine-tuning job. The
app shows a cost estimate and requires an explicit confirmation naming the
amount before anything is uploaded, then polls the job and saves the resulting
model id. Generation still sends the retrieved real examples as context.

> **Fine-tuning is being retired by OpenAI.** Since 8 May 2026 organisations
> that had never fine-tuned before cannot create training jobs, and existing
> customers lose the ability during January 2027. If your account can't use it,
> starting a job fails with OpenAI's own message and nothing is charged. Mode A
> needs no training run and is usually just as convincing.

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
flutter test          # 121 tests, no network or device needed
flutter run           # on a connected device or emulator
```

The Android and iOS projects are committed, so a clone builds as-is. The bundle
id is `com.example.replylikeme` — change it before you publish anything:

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

### Optional: the iOS share sheet

Picking a file with the file picker works on both platforms out of the box, and
so does the Android share sheet. Sharing *into* the app on iOS needs a Share
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

Then either share it straight into ReplyLikeMe, or save it (Files, Drive,
Downloads) and pick it with the file picker in the Train screen.

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

**Model names age.** These defaults were checked against OpenAI's documentation
in September 2026. Every field is free text, and **Settings → Model list → Load**
pulls the ids your account can actually use from `GET /v1/models`, so you never
have to guess. Cheaper and pricier alternatives worth knowing: `gpt-5.6-luna`
(cost-efficient tier, also vision-capable) and `gpt-6-astra` (flagship).

There is also **Delete all my data**, which removes the style memory, the
settings and the saved fine-tuned model id, and optionally the API key. It does
not touch files or models on OpenAI's side — delete those in your OpenAI
dashboard.

---

## Privacy

- The API key lives only in the platform keystore. It is never logged, never
  committed, and never included in an exception message.
- Messages, embeddings and settings live only in app-private storage on the
  device.
- What is sent to OpenAI: the exchange text being embedded during training, the
  screenshot you pick, and the prompt (retrieved examples plus the current
  conversation) when generating. Nothing else, and nothing to anyone else.
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
    app_settings.dart        model choices, mode, names, window sizes
    chat_message.dart        one parsed export line
    chat_turn.dart           merged consecutive messages from one sender
    exchange.dart            their turns -> my reply
    extracted_message.dart   one message read off a screenshot
    finetune_job.dart        fine-tuning job state
    parsed_chat.dart         the result of parsing one export
    stored_exchange.dart     an exchange plus its embedding
  services/
    whatsapp_parser.dart     both export layouts -> messages, turns, exchanges
    chat_export_reader.dart  .txt / .zip -> export text
    openai_service.dart      chat, vision, embeddings, files, fine-tuning
    openai_exception.dart    failures, each with a message worth showing
    vector_math.dart         normalise, dot product, top-k, blob encoding
    exchange_store.dart      the style-memory interface
    embeddings_store.dart    sqflite implementation
    style_memory_service.dart  Mode A: build and query
    reply_generator.dart     prompt construction and the three variants
    finetune_service.dart    Mode B: JSONL, cost estimate, job polling
    secure_key_store.dart    the API key, and only the API key
    settings_store.dart      everything non-secret
    share_intake.dart        Android/iOS share sheet
    pricing.dart             token and cost estimates
  state/providers.dart       Riverpod providers and notifiers
  screens/                   root, setup, home, train, generate, finetune, settings
  widgets/failure_text.dart  turns any error into a readable sentence
test/                        121 tests (115 unit, 6 widget)
test/fixtures/               synthetic Android and iOS exports
```

## Errors you might hit

| What you see | What it means |
|---|---|
| "OpenAI rejected that API key" | Wrong or revoked key. Replace it in Settings. |
| "Your OpenAI account has no credit left" | Add billing at platform.openai.com. |
| "OpenAI is rate-limiting this key" | Handled automatically with backoff; if it persists, wait. |
| "Couldn't read that screenshot" | The vision model didn't return usable JSON. Try a clearer screenshot or another vision model. |
| "That file doesn't look like a WhatsApp export" | Wrong file, or an export from another app. |
| "There are no replies of yours to learn from" | The name picked as yours is probably the other person. |
| "cannot use that model or endpoint" | Your account has no access to that model id. Load the model list in Settings. |

## Tests

```bash
flutter test
```

121 tests, and no network or device is needed for any of them.

115 unit tests cover the parser against synthetic Android and iOS exports, the
`.txt`/`.zip` reader, the vector maths, the OpenAI client's error mapping and
retries against a scripted transport, prompt construction, JSONL generation and
cost estimation, and the style-memory build and retrieval loop.

6 widget tests boot the real app with an in-memory style memory and a stubbed
key: that setup appears when no key is saved, that a malformed key is rejected
before any request is made, that home reflects an empty and a trained memory
(including disabling reply suggestions until there is something to imitate),
that Settings shows the key masked and never in full, and that "delete all my
data" really empties the store.
