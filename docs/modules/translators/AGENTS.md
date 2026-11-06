# Yisi translation source modules — guide for agents

A translation source replaces Yisi's translation engine. The user chooses it in
**Settings → Translation → Other Sources**. Text goes straight to it: Yisi's prompts,
presets, learned rules and Smart Improve do not apply.

Yisi sends `text`, `source` and `target`, plus `image` when the source accepts screenshots.
Return the translation only.

You never modify or rebuild Yisi, and updates never touch what you write.

```
modules/translators/        this folder
  <id>/
    translator.json
    …                       any prompts, scripts or files the module uses
```

- `<id>` is the folder name: lowercase letters, digits and dashes, unique across all modules.
- Schema: `~/Library/Application Support/Yisi/schemas/translator.schema.json`.
- Text (and optionally an image) in, text out. Modules cannot draw their own UI.

## translator.json

```json
{
  "schemaVersion": 1,
  "name": "DeepL",
  "languages": { "zh-Hans": "ZH", "en": "EN", "ja": "JA" },
  "http": {
    "url": "https://api-free.deepl.com/v2/translate",
    "encoding": "form",
    "headers": { "Authorization": "DeepL-Auth-Key {{secret:key}}" },
    "body": { "text": "{{text}}", "target_lang": "{{target}}" },
    "response": ["translations", "*", "text"]
  }
}
```

| Field | |
| --- | --- |
| `schemaVersion` | `1` |
| `name` | shown in the Other Sources menu |
| `description` | optional, one line |
| `accepts` | `["text"]` (default), or with `"image"` to receive screenshots instead of their OCR text |
| `languages` | optional. Maps Yisi's codes to the service's own before anything is sent; unmapped codes pass through |
| `prompt`, `http` or `command` | exactly one |

No other fields are accepted.

Yisi's language codes: `auto` (source only), `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `fr`,
`de`, `es`, `ru`, `ar`, `th`, `vi`.

Placeholders: `{{text}}`, `{{source}}`, `{{target}}`; `{{previous}}` in later prompt steps;
`{{image}}` in an `http` body.

## How it runs

Exactly one of `prompt`, `http` or `command`.

### prompt — prompts only, no code

Yisi sends each step to an AI service and feeds the answer to the next step. Nothing to
approve unless a prompt reads files outside the module folder.

```json
"prompt": {
  "provider": "default",           // the AI service in Settings, or the id of an AI service module
  "temperature": 0.3,              // optional, 0–2
  "steps": [
    { "system": "@system.md", "user": "{{text}}" },
    { "system": "Polish the draft. Output the result only.", "user": "{{previous}}" }
  ]
}
```

- A value starting with `@` is a file: in the module folder (`@prompts/system.md`), `~/…`, or absolute.
- `{{file:glossary.md}}` inlines a file. Included files may use placeholders but not include further files.
- `user` defaults to `{{text}}` for the first step and `{{previous}}` after it.
- A screenshot (when accepted) is attached to the first step.
- 1–8 steps. The last answer is shown as is, so ask for the result only.

### http — call a service

```json
"http": {
  "url": "https://api.example.com/v1/run",   // HTTPS, or HTTP on localhost / 127.0.0.1 / ::1
  "headers": { "Authorization": "Bearer {{secret:token}}" },
  "timeout": 30                              // seconds, 1–300
}
```

Without `body`, Yisi POSTs the request JSON (below) and reads `{"text": "..."}` or a
plain-text body. To call an existing API as it is, describe the request instead:

- `method`: `POST` (with `encoding` `json` or `form`) or `GET` (with `query`).
- `body`: the fields to send, using `{{text}}`, `{{source}}`, `{{target}}`, `{{image}}` (base64 PNG) and `{{secret:name}}`.
- `response`: the path to the text, as keys, indexes or `*`; several matches are joined by newlines.

The DeepL manifest above is an example.

Values are substituted once and never re-interpreted. Redirects are refused; responses
over 2 MB fail. For signing, OAuth or SDKs, run a small local server on 127.0.0.1 in front
of the service and point the module at it.

### command — run a local program or agent

```json
"command": {
  "program": "python3",            // absolute path, a file in the module folder, or a name on the login PATH
  "args": ["main.py"],
  "stdin": "json",                 // json: the request JSON | text: just text
  "timeout": 120,                  // seconds, 1–600
  "env": { "API_TOKEN": "{{secret:token}}" }
}
```

- Runs in the module folder with the user's login-shell PATH, plus `YISI_MODULE_DIR` and `YISI_ROLE=translator`.
- Write the result to **stdout**; it streams into the popup as it arrives. Exit 0 on success.
  On failure exit non-zero and explain on stderr (the last lines are shown to the user).
- With `"stdin": "text"` the program receives just `text`.
- With JSON stdin, a screenshot arrives as `"image": "/path/to/file.png"`, deleted after the run.
- Closing the popup or timing out stops the whole process group.

## Request JSON

What `http` without a `body` and `command` with JSON stdin receive:

```json
{ "schemaVersion": 1, "role": "translator", "text": "…", "source": "auto", "target": "zh-Hans", "image": "…" }
```

`image` is present only when there is one: a base64 PNG for `http`, a file path for `command`. `source` and `target` are already mapped through `languages`.
Respond with text only.

## Secrets

Never write keys into files. Reference them as `{{secret:name}}` in http headers or body
and command env. The user enters the value in Settings → Modules; it is kept in the macOS
Keychain and never exported.

## Approval

Before a module can send text somewhere new or run code, the user allows it in
Settings → Modules, which shows exactly what it will send or run. The approval is bound to:

- `http`: the whole `http` block.
- `command`: the `command` block plus the files it runs (editing `main.py` asks again).
- `prompt`: only files outside the module folder.

You cannot approve on the user's behalf. Ask them to open Settings → Modules.

## Check your work

Yisi reloads modules as soon as files change. From Terminal:

```sh
YISI=/Applications/Yisi.app/Contents/MacOS/Yisi
"$YISI" modules validate           # every module, with the reason for any failure
"$YISI" modules run <id> --text "Hello" --source en --target zh-Hans
```

Unapproved modules also run from Terminal, but without secrets, so you can test the
plumbing without touching keys.

## Good modules

- Return the translation only — no notes, quotes or language labels.
- Handle `source: "auto"`: omit it if the service detects the language itself.
- Fill `languages` for every code the service names differently.
- Fail loudly with a short stderr message; never print secrets.
