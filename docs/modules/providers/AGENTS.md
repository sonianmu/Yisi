# Yisi AI service modules — guide for agents

An AI service is the model behind Yisi. Once the user chooses it in **Settings → AI Service**,
Yisi's translation, Smart Improve, learned rules and the user's hand-written presets all run
on it. Yisi writes the prompts; the module only has to reach a model.

Yisi sends `system` (the full instructions Yisi built) and `text` (the user's content), plus
`image` when `vision` is on. **Return the model's answer unchanged** — Yisi parses it, so do
not add, trim or reformat anything.

You never modify or rebuild Yisi, and updates never touch what you write.

```
modules/providers/          this folder
  <id>/
    provider.json
    …                       any prompts, scripts or files the module uses
```

- `<id>` is the folder name: lowercase letters, digits and dashes, unique across all modules.
- Schema: `~/Library/Application Support/Yisi/schemas/provider.schema.json`.
- Text (and optionally an image) in, text out. Modules cannot draw their own UI.

## provider.json

```json
{
  "schemaVersion": 1,
  "name": "Claude Code",
  "description": "Runs Yisi's translation on claude -p",
  "vision": false,
  "command": { "program": "claude", "args": ["-p"], "stdin": "text", "timeout": 180 }
}
```

| Field | |
| --- | --- |
| `schemaVersion` | `1` |
| `name` | shown in the AI Service menu |
| `description` | optional, one line |
| `vision` | `true` if the model can see images; otherwise screenshots arrive as OCR text in `text` |
| `http` or `command` | exactly one. AI services cannot use `prompt` — they are what prompts run on |

No other fields are accepted.

## How it runs

Exactly one of `http` or `command`.

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
- `body`: the fields to send, using `{{system}}`, `{{text}}`, `{{image}}` (base64 PNG) and `{{secret:name}}`.
- `response`: the path to the text, as keys, indexes or `*`; several matches are joined by newlines.

For example, an OpenAI-compatible API:

```json
"http": {
  "url": "https://api.example.com/v1/chat/completions",
  "headers": { "Authorization": "Bearer {{secret:key}}" },
  "body": {
    "model": "example-model",
    "messages": [
      { "role": "system", "content": "{{system}}" },
      { "role": "user", "content": "{{text}}" }
    ]
  },
  "response": ["choices", "0", "message", "content"]
}
```

Values are substituted once and never re-interpreted. Redirects are refused; responses
over 2 MB fail. For signing, OAuth or SDKs, run a small local server on 127.0.0.1 in front
of the service and point the module at it.

### command — run a local program or agent

```json
"command": {
  "program": "python3",            // absolute path, a file in the module folder, or a name on the login PATH
  "args": ["main.py"],
  "stdin": "json",                 // json: the request JSON | text: system, a blank line, then text
  "timeout": 120,                  // seconds, 1–600
  "env": { "API_TOKEN": "{{secret:token}}" }
}
```

- Runs in the module folder with the user's login-shell PATH, plus `YISI_MODULE_DIR` and `YISI_ROLE=provider`.
- Write the result to **stdout**; it streams into the popup as it arrives. Exit 0 on success.
  On failure exit non-zero and explain on stderr (the last lines are shown to the user).
- With `"stdin": "text"` the program receives `system`, a blank line, then `text`.
- With JSON stdin, a screenshot arrives as `"image": "/path/to/file.png"`, deleted after the run.
- Closing the popup or timing out stops the whole process group.

## Request JSON

What `http` without a `body` and `command` with JSON stdin receive:

```json
{ "schemaVersion": 1, "role": "provider", "system": "…", "text": "…", "image": "…" }
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
"$YISI" modules run <id> --system "Reply in one word." --text "Hello"
```

Unapproved modules also run from Terminal, but without secrets, so you can test the
plumbing without touching keys.

## Good modules

- Pass Yisi's `system` through as the system prompt; do not write your own.
- Never post-process the answer. If the model wraps it in commentary, fix the call, not the output.
- Set `vision` only if the model really accepts images.
- Fail loudly with a short stderr message; never print secrets.
