# Yisi preset modules — guide for agents

A preset is something to do with the user's selection: rewrite it, reply to it, explain it,
extract from it. It appears in **Settings → Modes** beside the user's hand-written presets,
runs from the popup, and can have its own global shortcut.

Yisi sends `text` (the selection), plus `image` when the preset accepts screenshots. What
you return is exactly what the popup shows.

You never modify or rebuild Yisi, and updates never touch what you write.

```
modules/presets/            this folder
  <id>/
    preset.json
    …                       any prompts, scripts or files the module uses
```

- `<id>` is the folder name: lowercase letters, digits and dashes, unique across all modules.
- Schema: `~/Library/Application Support/Yisi/schemas/preset.schema.json`.
- Text (and optionally an image) in, text out. Modules cannot draw their own UI.

## preset.json

```json
{
  "schemaVersion": 1,
  "name": "Reply in my tone",
  "description": "Drafts a reply to the selected email",
  "accepts": ["text"],
  "shortcut": "ctrl+option+r",
  "prompt": {
    "steps": [
      { "system": "@reply.md" },
      { "system": "Shorten the draft to five sentences. Output the reply only." }
    ]
  }
}
```

| Field | |
| --- | --- |
| `schemaVersion` | `1` |
| `name` | shown in Modes and in the popup |
| `description` | optional, one line |
| `accepts` | `["text"]` (default), `["image"]` or both. A screenshot reaching a text-only preset arrives as OCR text. A preset that accepts only images starts a screen capture when its shortcut is pressed |
| `shortcut` | optional. `cmd`, `ctrl`, `option`, `shift` joined with `+` and one key (`a`–`z`, `0`–`9`, `f1`–`f12`, `space`, punctuation); at least one of cmd/ctrl/option. Conflicts are shown in Settings |
| `prompt`, `http` or `command` | exactly one |

No other fields are accepted. Placeholders: `{{text}}`; `{{previous}}` in later prompt steps;
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
- `body`: the fields to send, using `{{text}}`, `{{image}}` (base64 PNG) and `{{secret:name}}`.
- `response`: the path to the text, as keys, indexes or `*`; several matches are joined by newlines.

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

- Runs in the module folder with the user's login-shell PATH, plus `YISI_MODULE_DIR` and `YISI_ROLE=preset`.
- Write the result to **stdout**; it streams into the popup as it arrives. Exit 0 on success.
  On failure exit non-zero and explain on stderr (the last lines are shown to the user).
- With `"stdin": "text"` the program receives just `text`.
- With JSON stdin, a screenshot arrives as `"image": "/path/to/file.png"`, deleted after the run.
- Closing the popup or timing out stops the whole process group.

## Request JSON

What `http` without a `body` and `command` with JSON stdin receive:

```json
{ "schemaVersion": 1, "role": "preset", "text": "…", "image": "…" }
```

`image` is present only when there is one: a base64 PNG for `http`, a file path for `command`.
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
"$YISI" modules run <id> --text "Hello"           # add --image shot.png if it accepts images
```

Unapproved modules also run from Terminal, but without secrets, so you can test the
plumbing without touching keys.

## Good modules

- One purpose per preset, with a name the user will recognize in a menu.
- Ask the model for the result only; the popup shows exactly what you return.
- Prefer `prompt` when prompts are enough; use `command` when you need tools, files or an agent.
- Pick a shortcut that does not clash with common app shortcuts, or leave it out.
- Fail loudly with a short stderr message; never print secrets.
