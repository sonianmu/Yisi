# 可扩展翻译源 / Translation source adapters

Yisi 不内置 Google、百度、腾讯等服务的 SDK，也不执行导入文件中的脚本。
它提供版本化的 HTTP 配置协议：普通接口直接声明请求与结果映射；复杂签名、
OAuth 刷新或特殊返回格式由用户自己的 Agent 编写本地 HTTP bridge 处理。
翻译引擎选择“其他翻译源”后，文字直接发送到所选源；图片先在本机 OCR，
只发送识别文字。不发送图片，不使用 AI、自定义提示词、预设模式或智能改进。
AI 与系统翻译的配置不会被覆盖，随时可以切回。

Yisi exposes a versioned HTTP configuration contract, not vendor SDKs or executable
plugins. Declarative adapters handle ordinary HTTP APIs. User-owned local bridges
handle signing, OAuth, SDKs, or special response formats. External sources support
plain translation and local OCR only, not AI prompts, custom modes or learning.

## 给用户的 Agent / Agent handoff

1. 确认用户选择的服务、官方 API 文档、凭据要求及隐私要求，不使用抓取网页的非公开接口。
2. 从 `translation-source.example.json` 起步，按下述 schema 生成独立的 JSON。
3. 对需要动态签名的服务，生成只监听 loopback 的本地 bridge，参照
   `examples/translation-bridge.py`。用户自行安装所需运行时并启动 bridge。
   不要让 Yisi 执行 shell，不要修改应用二进制，也不要自动注册 LaunchAgent。
4. 在本地做请求与错误处理测试，确认语言码映射、分段合并、超时及 Unicode。
5. 用户在“设置 → 翻译 → 其他翻译源”导入 JSON，核对目标地址并批准，
   在应用中填写 API key（Keychain），用“测试翻译源”发送固定的 `Hello` 测试。
6. 也可直接将 JSON 写入下列目录，再点重新加载；Agent 不能代替用户批准源。

Ask the user's Agent to inspect the vendor's official API docs, generate a JSON
adapter, test it, and hand it to the user for import and explicit destination approval.
Signing/OAuth bridges run separately on loopback; Yisi never starts scripts or daemons.

配置目录 / Configuration directory:

```
~/Library/Application Support/com.sonianmu.yisi/TranslationSources/
```

配置目录中的文件名必须为 `<id>.json`（界面导入会自动命名）；仅加载普通文件，不跟随符号链接；单文件上限 256 KB。
同一目录不允许重复 id。直接编辑后点击重新加载，下一次请求也会重新读取配置。
更改任意配置会使已有授权失效；需要在应用里再次审核。配置中的文字会在审核后
发往指定地址，请谨慎导入他人配置。删除 JSON 后点重新加载即可移除源；可先撤销
授权和删除 Keychain 密钥。应用不会因源失败而偷偷切到 AI 或其他服务。

## Schema v1

所有字段都必填，暂不支持其他版本。未知字段不产生行为。

| 字段 | 说明 |
| --- | --- |
| `schemaVersion` | `1` |
| `id` | 唯一、稳定的小写标识；`[a-z0-9][a-z0-9-]{0,63}` |
| `name` | 下拉框名称，最多 80 字符 |
| `endpoint` | 固定 HTTPS URL；只允许 loopback 的 HTTP（localhost / 127.0.0.1 / ::1）。不允许 URL 用户密码、片段或模板 |
| `method` | `POST` 或 `GET` |
| `encoding` | POST 用 `json` / `form`；GET 用 `query` |
| `headers` | 字符串字典；禁止 Host、Cookie、Content-Length、Connection、Transfer-Encoding 和换行注入；Content-Type 由 encoding 决定 |
| `parameters` | 请求参数；JSON 可嵌套，form/query 只能用字符串、数值、布尔值 |
| `responsePath` | JSON 路径数组，键名、数组下标字符串或 `*`；叶子必须是非空译文字符串，多条用换行连接 |
| `languageMap` | 标准语言码到服务语言码的映射；未配置的码原样传递 |
| `requiresSecret` | 需要 Keychain 中的单个密钥时为 true |

参数值与 header 值支持四种模板：`{{text}}`、`{{source}}`、`{{target}}`、
`{{secret}}`。替换以字符串值为单位，随后正确进行 JSON / URL 编码；不会执行
代码，也不会再次解释替换结果中的模板。未知模板报错。不要在 JSON 或 URL 中
硬编码密钥；远程简单 API 将 `requiresSecret` 设为 true 并在应用里输入密钥。
多密钥/动态签名由本地 bridge 自行安全存储和管理，不经 Yisi 配置文件传递。

语言码：`auto`, `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `fr`, `de`, `es`, `ru`,
`ar`, `th`, `vi`。目标语言不会为 auto。服务不支持 auto 时，由 bridge 做检测，
或由用户选择源语言，不默认猜成英语。

例如响应 `{"translations":[{"text":"你好"},{"text":"世界"}]}` 使用
`["translations", "*", "text"]`；响应 `[[["你好", "Hello"]]]` 使用
`["0", "*", "0"]`。HTTP 非 2xx、空结果、缺失路径或无效 JSON 均显示错误。
默认请求超时 30 秒、整个资源超时 35 秒，不自动重试；输入上限 1 MB、响应上限
2 MB。禁止所有 HTTP 重定向，不接受跨地址转发密钥。使用无缓存、无 Cookie、
无共享登录凭据的独立会话，不记录原文、密钥或响应正文。

## 本地 bridge 协议

推荐 `POST http://127.0.0.1:PORT/translate`：

```json
{"text":"Hello","source":"en","target":"zh-Hans"}
```

返回：

```json
{"translation":"你好"}
```

示例 bridge 只返回固定验收译文，不实现任何厂商服务，避免误以为已有免费 API。
它拒绝非 JSON、错误路径、过大请求、无效语言码、浏览器 Origin 请求和非 loopback
Host。正式适配时建议加本地随机 token（Yisi 的 Keychain → Authorization header），
不要绑定 0.0.0.0，不绕过 TLS 校验，不在错误响应中暴露密钥。不要将完整用户原文
写入日志，网络错误不要返回成功状态。第三方服务的可用性和计费由用户自行承担。

## 验收 / Acceptance

```sh
python3 docs/examples/translation-bridge.py
```

导入示例 JSON，批准 `127.0.0.1:19387`，选中该源后点测试，预期 `你好`。
截图文字也走同一源；切回 AI 后才恢复提示词/智能改进。停止 bridge 后应显示连接
错误，而不是启用其他引擎。修改配置后应提示重新批准。所有示例均无真实 API key。
