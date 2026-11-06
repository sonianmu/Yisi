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