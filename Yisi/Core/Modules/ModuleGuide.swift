import Foundation

/// Files Yisi writes into its home folder on every launch, so they always match the running version.
///
///     AGENTS.md                      which kind to write, and where its guide is
///     modules/<kind>/AGENTS.md       everything an agent needs for that one kind
///     schemas/<kind>.schema.json     the manifest, as JSON Schema
enum ModuleGuide {
    /// `AGENTS.md` at the root: just enough to pick a kind.
    static let index = #"""
# Yisi modules — start here

Yisi is a macOS popup: the user selects text or takes a screenshot, presses a shortcut, and
Yisi shows a result. You extend it by writing a module folder. You never modify or rebuild
Yisi, and updates never touch what you write.

Pick the kind, then read the guide in its folder. Each guide is complete on its own.

| The user wants… | Kind | Guide |
| --- | --- | --- |
| Yisi's translation to run on another model, API or local agent | AI service | `modules/providers/AGENTS.md` |
| a new thing to do with selected text or a screenshot | Preset | `modules/presets/AGENTS.md` |
| another translation service | Translation source | `modules/translators/AGENTS.md` |

```
~/Library/Application Support/Yisi/
  AGENTS.md                   this file        (Yisi rewrites the AGENTS.md files and schemas/ on launch)
  schemas/                    JSON Schema for each manifest
  modules/providers/          AI services
  modules/presets/            presets
  modules/translators/        translation sources
  data/  state/               the user's history and approvals — do not touch
```
"""#

    /// `modules/<kind>/AGENTS.md`.
    static func guide(for role: ModuleRole) -> String {
        [intro(role), manifest(role), ways(role), request(role), shared, check(role), tips(role)]
            .joined(separator: "\n\n") + "\n"
    }

    // MARK: Parts

    private static func intro(_ role: ModuleRole) -> String {
        let purpose: String
        switch role {
        case .provider:
            purpose = #"""
# Yisi AI service modules — guide for agents

An AI service is the model behind Yisi. Once the user chooses it in **Settings → AI Service**,
Yisi's translation, Smart Improve, learned rules and the user's hand-written presets all run
on it. Yisi writes the prompts; the module only has to reach a model.

Yisi sends `system` (the full instructions Yisi built) and `text` (the user's content), plus
`image` when `vision` is on. **Return the model's answer unchanged** — Yisi parses it, so do
not add, trim or reformat anything.
"""#
        case .preset:
            purpose = #"""
# Yisi preset modules — guide for agents

A preset is something to do with the user's selection: rewrite it, reply to it, explain it,
extract from it. It appears in **Settings → Modes** beside the user's hand-written presets,
runs from the popup, and can have its own global shortcut.

Yisi sends `text` (the selection), plus `image` when the preset accepts screenshots. What
you return is exactly what the popup shows.
"""#
        case .translator:
            purpose = #"""
# Yisi translation source modules — guide for agents

A translation source replaces Yisi's translation engine. The user chooses it in
**Settings → Translation → Other Sources**. Text goes straight to it: Yisi's prompts,
presets, learned rules and Smart Improve do not apply.

Yisi sends `text`, `source` and `target`, plus `image` when the source accepts screenshots.
Return the translation only.
"""#
        }
        return purpose + "\n\n" + #"""
You never modify or rebuild Yisi, and updates never touch what you write.

```
\#(column("modules/\(role.folder)/"))this folder
  <id>/
    \#(role.manifestFile)
\#(column("    …"))any prompts, scripts or files the module uses
```

- `<id>` is the folder name: lowercase letters, digits and dashes, unique across all modules.
- Schema: `~/Library/Application Support/Yisi/schemas/\#(role.rawValue).schema.json`.
- Text (and optionally an image) in, text out. Modules cannot draw their own UI.
"""#
    }

    private static func column(_ text: String) -> String {
        text.padding(toLength: 28, withPad: " ", startingAt: 0)
    }

    private static func manifest(_ role: ModuleRole) -> String {
        switch role {
        case .provider:
            return #"""
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
"""#
        case .preset:
            return #"""
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
"""#
        case .translator:
            return #"""
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
"""#
        }
    }

    private static func ways(_ role: ModuleRole) -> String {
        var parts = ["## How it runs\n\nExactly one of " + (role == .provider ? "`http` or `command`." : "`prompt`, `http` or `command`.")]
        if role != .provider {
            parts.append(#"""
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
"""#)
        }
        let placeholders: String
        let api: String
        switch role {
        case .provider:
            placeholders = "`{{system}}`, `{{text}}`, `{{image}}`"
            api = #"""
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
"""#
        case .preset:
            placeholders = "`{{text}}`, `{{image}}`"
            api = ""
        case .translator:
            placeholders = "`{{text}}`, `{{source}}`, `{{target}}`, `{{image}}`"
            api = "The DeepL manifest above is an example."
        }
        parts.append(#"""
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
- `body`: the fields to send, using \#(placeholders) (base64 PNG) and `{{secret:name}}`.
- `response`: the path to the text, as keys, indexes or `*`; several matches are joined by newlines.

\#(api)

Values are substituted once and never re-interpreted. Redirects are refused; responses
over 2 MB fail. For signing, OAuth or SDKs, run a small local server on 127.0.0.1 in front
of the service and point the module at it.
"""#.replacingOccurrences(of: "\n\n\n\n", with: "\n\n"))
        let stdinText = role == .provider
            ? "`system`, a blank line, then `text`"
            : "just `text`"
        parts.append(#"""
### command — run a local program or agent

```json
"command": {
  "program": "python3",            // absolute path, a file in the module folder, or a name on the login PATH
  "args": ["main.py"],
  "stdin": "json",                 // json: the request JSON | text: \#(stdinText.replacingOccurrences(of: "`", with: ""))
  "timeout": 120,                  // seconds, 1–600
  "env": { "API_TOKEN": "{{secret:token}}" }
}
```

- Runs in the module folder with the user's login-shell PATH, plus `YISI_MODULE_DIR` and `YISI_ROLE=\#(role.rawValue)`.
- Write the result to **stdout**; it streams into the popup as it arrives. Exit 0 on success.
  On failure exit non-zero and explain on stderr (the last lines are shown to the user).
- With `"stdin": "text"` the program receives \#(stdinText).
- With JSON stdin, a screenshot arrives as `"image": "/path/to/file.png"`, deleted after the run.
- Closing the popup or timing out stops the whole process group.
"""#)
        return parts.joined(separator: "\n\n")
    }

    private static func request(_ role: ModuleRole) -> String {
        let json: String
        switch role {
        case .provider: json = #"{ "schemaVersion": 1, "role": "provider", "system": "…", "text": "…", "image": "…" }"#
        case .preset: json = #"{ "schemaVersion": 1, "role": "preset", "text": "…", "image": "…" }"#
        case .translator: json = #"{ "schemaVersion": 1, "role": "translator", "text": "…", "source": "auto", "target": "zh-Hans", "image": "…" }"#
        }
        let note = role == .translator ? " `source` and `target` are already mapped through `languages`." : ""
        return #"""
## Request JSON

What `http` without a `body` and `command` with JSON stdin receive:

```json
\#(json)
```

`image` is present only when there is one: a base64 PNG for `http`, a file path for `command`.\#(note)
Respond with text only.
"""#
    }

    private static let shared = #"""
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
"""#

    private static func check(_ role: ModuleRole) -> String {
        let run: String
        switch role {
        case .provider: run = #""$YISI" modules run <id> --system "Reply in one word." --text "Hello""#
        case .preset: run = #""$YISI" modules run <id> --text "Hello"           # add --image shot.png if it accepts images"#
        case .translator: run = #""$YISI" modules run <id> --text "Hello" --source en --target zh-Hans"#
        }
        return #"""
## Check your work

Yisi reloads modules as soon as files change. From Terminal:

```sh
YISI=/Applications/Yisi.app/Contents/MacOS/Yisi
"$YISI" modules validate           # every module, with the reason for any failure
\#(run)
```

Unapproved modules also run from Terminal, but without secrets, so you can test the
plumbing without touching keys.
"""#
    }

    private static func tips(_ role: ModuleRole) -> String {
        let specific: String
        switch role {
        case .provider:
            specific = #"""
- Pass Yisi's `system` through as the system prompt; do not write your own.
- Never post-process the answer. If the model wraps it in commentary, fix the call, not the output.
- Set `vision` only if the model really accepts images.
"""#
        case .preset:
            specific = #"""
- One purpose per preset, with a name the user will recognize in a menu.
- Ask the model for the result only; the popup shows exactly what you return.
- Prefer `prompt` when prompts are enough; use `command` when you need tools, files or an agent.
- Pick a shortcut that does not clash with common app shortcuts, or leave it out.
"""#
        case .translator:
            specific = #"""
- Return the translation only — no notes, quotes or language labels.
- Handle `source: "auto"`: omit it if the service detects the language itself.
- Fill `languages` for every code the service names differently.
"""#
        }
        return "## Good modules\n\n" + specific + "\n- Fail loudly with a short stderr message; never print secrets."
    }

    // MARK: - JSON Schema

    /// `schemas/<role>.schema.json`, one per kind, built from the same parts the decoder checks.
    static var schemas: [String: String] {
        Dictionary(uniqueKeysWithValues: ModuleRole.allCases.map { ("\($0.rawValue).schema.json", schema(for: $0)) })
    }

    static func schema(for role: ModuleRole) -> String {
        var properties: [String: Any] = [
            "$schema": ["type": "string"],
            "schemaVersion": ["const": 1],
            "name": ["type": "string", "minLength": 1, "maxLength": 80],
            "description": ["type": "string", "maxLength": 400],
        ]
        let inputs: [String: Any] = ["type": "array", "minItems": 1, "uniqueItems": true, "items": ["enum": ["text", "image"]]]
        var ways = ["http", "command"]
        switch role {
        case .provider:
            properties["vision"] = ["type": "boolean"]
        case .preset:
            properties["accepts"] = inputs
            properties["shortcut"] = ["type": "string", "examples": ["ctrl+option+r"]]
            ways.insert("prompt", at: 0)
        case .translator:
            properties["accepts"] = inputs
            properties["languages"] = ["type": "object", "additionalProperties": ["type": "string"]]
            ways.insert("prompt", at: 0)
        }
        for way in ways { properties[way] = handlers[way] }
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "yisi-\(role.rawValue).schema.json",
            "title": "Yisi \(role.rawValue) (modules/\(role.folder)/<id>/\(role.manifestFile))",
            "type": "object",
            "required": ["schemaVersion", "name"],
            "additionalProperties": false,
            "oneOf": ways.map { ["required": [$0]] },
            "properties": properties,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static let handlers: [String: Any] = [
        "prompt": [
            "type": "object", "required": ["steps"], "additionalProperties": false,
            "properties": [
                "provider": ["type": "string", "description": "default, or the id of a provider module"],
                "temperature": ["type": "number", "minimum": 0, "maximum": 2],
                "steps": [
                    "type": "array", "minItems": 1, "maxItems": 8,
                    "items": ["type": "object", "additionalProperties": false,
                              "properties": ["system": ["type": "string"], "user": ["type": "string"]]],
                ],
            ],
        ],
        "http": [
            "type": "object", "required": ["url"], "additionalProperties": false,
            "properties": [
                "url": ["type": "string", "format": "uri"],
                "method": ["enum": ["GET", "POST"]],
                "encoding": ["enum": ["json", "form", "query"]],
                "headers": ["type": "object", "additionalProperties": ["type": "string"]],
                "body": ["type": "object"],
                "response": ["type": "array", "minItems": 1, "maxItems": 16, "items": ["type": "string"]],
                "timeout": ["type": "number", "minimum": 1, "maximum": 300],
            ],
        ],
        "command": [
            "type": "object", "required": ["program"], "additionalProperties": false,
            "properties": [
                "program": ["type": "string", "minLength": 1],
                "args": ["type": "array", "items": ["type": "string"]],
                "stdin": ["enum": ["json", "text"]],
                "timeout": ["type": "number", "minimum": 1, "maximum": 600],
                "env": ["type": "object", "additionalProperties": ["type": "string"]],
            ],
        ],
    ]
}
