# 模块 / Modules

Yisi 负责快捷键、取词与截图、弹窗、权限和密钥；模块负责中间的处理。你的 Agent 只需在
`~/Library/Application Support/Yisi/modules/` 里写一个文件夹，Yisi 就会自动载入。不用改代码，
不用重新打包，升级不会覆盖，导出数据时会一起带走。

Yisi supplies the shortcut, the capture, the popup, permissions and key storage; a module
supplies the work in between. Your agent writes a folder under
`~/Library/Application Support/Yisi/modules/` and Yisi loads it. No rebuilding, nothing
overwritten by updates, and modules travel with your exported data.

## 三种模块

每种模块有自己的文件夹和清单文件，只写这一种需要的字段：

| 种类 | 位置 | 在哪里选用 | 收到 | 返回 |
| --- | --- | --- | --- | --- |
| AI 服务 | `providers/<id>/provider.json` | 设置 → AI 服务 | `system`、`text`、截图 | 模型的原始回答 |
| 预设 | `presets/<id>/preset.json` | 设置 → 模式，或它自己的快捷键 | `text`、截图 | 弹窗里显示的结果 |
| 翻译源 | `translators/<id>/translator.json` | 设置 → 翻译 → 其他翻译源 | `text`、`source`、`target`、截图 | 译文 |

每个模块用以下三种方式之一运行：

| 方式 | 适合 |
| --- | --- |
| `prompt` | 只需要提示词：可多步串联、引用本地文件（术语表、风格指南），由 Yisi 调用你配置的模型（AI 服务不可用） |
| `http` | 调用一个服务：远程 API，或你在本机运行的服务 |
| `command` | 运行本地程序或 Agent：Python 脚本、`claude -p`、你的 Agent 工程 |

输入永远是文字或图片，输出永远是文字。

在 **设置 → 模式** 里手写的「这是…，请…」预设不是模块，仍然在 Yisi 内直接编辑。

## 交给你的 Agent

在 **设置 → 模块** 选好种类，点「复制给 Agent 的说明」，发给你的 Agent 并描述需求。
说明指向这一种模块自己的 `AGENTS.md`（[AI 服务](providers/AGENTS.md)、[预设](presets/AGENTS.md)、
[翻译源](translators/AGENTS.md)，本目录是 Yisi 写入数据目录的副本）。Agent 读完后写好模块文件夹，
然后用命令行自检：

```sh
/Applications/Yisi.app/Contents/MacOS/Yisi modules validate
/Applications/Yisi.app/Contents/MacOS/Yisi modules run polish --text "Hello"
```

模块只在 **设置 → 模块** 里管理：查看它会做什么、允许、填写密钥、试运行、移到废纸篓。
其他页面只负责选用。

## 安全

- 会把文字发往新地址、运行程序、或读取模块文件夹以外文件的模块，必须由你在
  **设置 → 模块** 中查看并允许。允许与模块内容绑定：地址、命令或它运行的脚本一变，
  就需要重新允许。只读自己文件夹的提示词模块无需允许。
- 密钥写成 `{{secret:name}}`，在 Yisi 中填写，只保存在钥匙串，不写入文件，也不导出。
- 关闭弹窗即取消请求；本地程序超时或取消时，整个进程组都会被结束。

## 数据

```
~/Library/Application Support/Yisi/
  AGENTS.md     入口：选哪种模块（Yisi 每次启动时更新）
  schemas/      每种清单的 JSON Schema
  modules/      providers/、presets/、translators/，各带一份 AGENTS.md
  data/         历史、截图、学习规则
  state/        允许记录与临时文件（不导出）
```

**设置 → 通用 → 数据** 可以把模块、手写预设、历史、学习规则和偏好设置导出为一个 zip，
在另一台 Mac 上导入。1.3.13 的翻译源会在首次启动时自动转换为翻译源模块。

## 示例

[`examples/`](examples) 按种类放好，可以整个文件夹复制进模块目录：

- `providers/claude-code`：让 Yisi 的翻译跑在本机的 `claude -p` 上。
- `presets/polish`：两步提示词，先翻译再润色，并引用术语表。
- `presets/claude-reply`：用 Claude Code 为选中的消息起草回复。
- `translators/local-translator`：调用本机服务的翻译源，配合 `translation-bridge.py`。
