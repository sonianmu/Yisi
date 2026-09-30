# 通用模型服务配置

Yisi 的 AI 服务按连接、协议、模型能力配置。现有五家厂商保留为快捷模板；模型名称不再决定业务层的推理策略。

## 使用自定义服务

1. 打开设置 → AI 服务，提供商选择「自定义服务」。
2. 选择服务支持的接口协议：OpenAI 兼容、Gemini 原生或 Anthropic Messages。
3. 填写 API 基础地址和模型 ID。地址包含服务要求的版本路径，例如 `https://example.com/v1`。本地 OpenAI 兼容服务可填写 `http://localhost:11434/v1`。
4. 填写密钥并点击「保存密钥」。新密钥保存在系统钥匙串；本地无认证服务可留空。已有厂商密钥继续读取原有配置。
5. 在「高级适配」中按该服务的文档填写模型能力，然后点击「测试连接」。测试会产生少量 API 用量，不发送用户的翻译内容。

地址示例：

| 协议 | 基础地址示例 | 自动追加的路径 |
|---|---|---|
| OpenAI 兼容 | `https://example.com/v1` | `/chat/completions` |
| Gemini 原生 | `https://generativelanguage.googleapis.com/v1beta` | `/models/{model}:generateContent` |
| Anthropic Messages | `https://api.anthropic.com/v1` | `/messages` |

OpenAI 和 Anthropic 也接受包含完整请求路径的地址，不会重复追加。Gemini 模型可填写 `gemini-…` 或 `models/gemini-…`。服务地址不接受 URL 中的密钥、账号、查询参数或锚点；认证通过 HTTP 请求头发送。

## 模型能力

未知模型默认不发送温度、原生 JSON 或推理控制参数，不假定支持图片。用户明确配置后才启用相应参数。翻译、预设、自定义和学习分析的 Prompt 仍然要求结果 JSON，因此关闭「原生 JSON 模式」不影响结果字段约定。

| 推理控制方式 | 实际发送的参数 |
|---|---|
| 跟随服务默认 | 不发送推理参数，开关不改变服务固有行为 |
| 无原生推理 | 不发送推理参数；开启深度思考时仅加强默认翻译的语义和格式检查 |
| 始终推理 | 不发送推理参数，并说明无法关闭推理 |
| 推理强度 | `reasoning_effort`，分别填写开启和关闭时的值 |
| 思考类型开关 | `thinking.type = enabled / disabled` |
| 思考布尔开关 | `enable_thinking = true / false` |
| Gemini 思考预算 | `generationConfig.thinkingConfig.thinkingBudget` |
| Gemini 思考等级 | `generationConfig.thinkingConfig.thinkingLevel` |
| Anthropic 思考预算 | `thinking.type` 和 `budget_tokens`，关闭时明确发送 `disabled` |
| Anthropic 自适应思考 | `thinking.type = adaptive` 和 `output_config.effort`；关闭值填 `disabled` 时显式关闭 |

推理强度的关闭值为 `low` 时，表示优先速度，仍然会推理。只有服务明确支持时才能填写 `none` 或 `disabled`。Gemini 预算的最低值为 `0` 才表示关闭；例如内置 Gemini 2.5 Pro 模板的最低预算为 `128`。

Anthropic 手动思考预算须至少为 1024 且小于输出 Token 上限；启用时自动省略温度参数，并为最终答案预留输出空间。支持自适应思考的新模型应选择自适应方式，而不是手动预算。

温度参数分别配置常规模式和推理模式的支持情况；模型仅在非推理状态支持温度时，保持「推理时发送温度」关闭。

OpenAI 兼容服务可独立选择 `max_tokens` 或 `max_completion_tokens`。不要仅因模型使用兼容接口就开启所有参数，应以该端点的实际支持情况为准。

能力覆盖按模型保存。内置服务按厂商、模型和文本／图片配置区分；自定义服务额外区分服务地址和协议。切换到新模型时使用该模型自己的能力配置，未配置的新模型回到服务默认。

## 截图与学习规则

截图可复用文本设置，也可单独选择服务。直接发送图片前会检查图片支持；无法发送图片时，可以选择「系统 OCR」，先在本机提取文字，再交给文本模型处理。学习规则分析与文本处理共用端点、模型和能力配置，不再调用写死的分析模型。

测试连接会验证实际返回的结果 JSON。独立图片配置的测试还会发送一张测试图片。测试只验证当前思考偏好；需要确认两种状态时，应分别切换开关测试。HTTP 400、认证失败、结果截断或空结果不会自动重复调用；限流和服务端错误按重试策略处理。

## 开发验证

运行 `swift test`。测试使用本地请求构建和模拟 HTTP 响应，不需要 API Key，不调用外部模型。

第一版不包含模型列表自动获取、远程能力目录、Responses 协议或多个自定义连接的管理。新模型仍可通过手动填写 ID 和能力接入；新协议需要增加协议适配。

参考：[OpenAI 推理参数](https://developers.openai.com/api/docs/guides/reasoning)、[Gemini 思考参数](https://ai.google.dev/gemini-api/docs/thinking)、[Anthropic 思考预算](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)、[DeepSeek 推理开关](https://api-docs.deepseek.com/guides/thinking_mode/)。
