<div align="center">
  <img src="./assets/icon.png" width="120" height="120" alt="Yisi Icon">
  <h1>Yisi</h1>
  <p><b>macOS 上的智能语义转换工具</b> -- 选中、触发、呈现。不打开对话框，不切换窗口，AI 在你的操作流中无声完成转换。</p>
  <p><a href="./README_en.md">English</a> | 简体中文</p>
</div>

[![GitHub release](https://img.shields.io/github/v/release/MUTRO888/Yisi)](https://github.com/MUTRO888/Yisi/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/MUTRO888/Yisi/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

---

## 截图

![Yisi](promo-desktop-final.png)

---

## 功能特性

- **即时翻译** -- 选中文字，按下快捷键，译文原地浮现。内置精调 Prompt，输出自然地道的译文，而非逐字机械转换
- **Learned Rules（学习规则）** -- 纠正一个术语或调整一种表达，Yisi 自动记住偏好并在后续翻译中持续应用
- **离线翻译** -- 集成 macOS 原生 System Translation，断网环境下数据完全本地处理，不经过任何服务器
- **Preset Mode（预设模式）** -- 预定义输入感知和输出指令，配置一次永久生效。选中即触发，触发即完成，零额外操作
- **Custom Mode（即时模式）** -- 一次性需求无需提前配置。触发时填写"这是什么"和"请做什么"，当场处理
- **截图识别** -- 快捷键框选屏幕区域，图片直接送入 AI 分析。设计稿、报错截图、数据图表均可处理
- **多 AI 提供商** -- 支持 Gemini、OpenAI、智谱 AI、DeepSeek、MiniMax，文本和视觉模型可分别配置
- **翻译历史** -- 所有转换结果本地持久化，随时回溯查阅
- **菜单栏常驻** -- 不占 Dock 位，常驻 macOS 菜单栏，随时可用
- **深色/浅色主题** -- 跟随系统或手动切换
- **自动更新** -- 应用内检查并下载新版本
- **开机自启** -- 首次启动后自动注册为登录项

---

## 设计哲学

> Yisi 没有对话框。

不是"选中内容 -> 打开对话 -> 描述需求 -> 等待回复"，而是"选中 -> 呈现"。

没有来回问答，没有对话历史，没有 AI 的名字和头像。左边是你选中的内容，右边是它的新形态。窗口关掉，一切如常，只是那件事已经完成了。

AI 不是你去拜访的对话伙伴，而是安静藏在你操作流里的一环。

---

## 环境要求

| 要求 | 最低版本 |
|------|---------|
| **macOS** | 14.0+（Sonoma） |
| **芯片** | Apple Silicon / Intel |

> **注意**：Yisi 需要辅助功能权限（Accessibility）来捕获选中文字。首次使用时系统会弹出授权提示，请在 **系统设置 > 隐私与安全性 > 辅助功能** 中授权。

---

## 快速开始

### 安装

从 [Releases](https://github.com/MUTRO888/Yisi/releases) 页面下载最新的 `.dmg` 文件，拖入应用程序文件夹即可。

### 三步完成一次转换

1. **选中** -- 在任何应用中选中文字，或按截图快捷键框选屏幕区域
2. **触发** -- `Cmd + C + C`（文本）/ `Cmd + Shift + X`（截图）
3. **呈现** -- 结果在弹窗中直接显示，关闭即返回

快捷键可在 Settings > 通用 中自定义。

### 五分钟完成配置

Yisi 支持五家 AI 提供商。推荐从智谱 AI 开始 -- 新用户注册即送 Token，足够长期使用。

1. 前往 [智谱 AI 开放平台](https://open.bigmodel.cn) 注册并获取 API Key
2. 打开 Yisi > Settings > AI 服务
3. 提供商选择 Zhipu AI，粘贴 API Key
4. 模型已预设，开箱即用
5. 完成，开始使用

---

## 安装问题排查

Yisi 尚未进行代码签名，macOS 首次打开时会显示安全警告。

**方案一 -- 右键打开**

1. 在访达中右键（或 Control-点击）`Yisi.app`
2. 从右键菜单中选择 **打开**
3. 在确认对话框中点击 **打开**

**方案二 -- 系统设置**

1. 打开 **系统设置** > **隐私与安全性**
2. 向下滚动到 **安全性** 部分，点击 **仍要打开**

**方案三 -- 终端命令**

```bash
xattr -cr /Applications/Yisi.app
```

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI |
| 最低系统 | macOS 14（Sonoma） |
| 文字捕获 | Accessibility API + 剪贴板回退 |
| 截图 | ScreenCaptureKit |
| 离线翻译 | macOS System Translation |
| AI 集成 | Gemini / OpenAI / 智谱 / DeepSeek / MiniMax REST API |
| 学习引擎 | 本地规则存储 + 自动 Prompt 注入 |
| 分发 | DMG（手动构建） |

---

## 项目结构

```
Yisi/
├── .github/workflows/       # CI/CD
├── docs/                    # 设计文档
├── assets/                   # 应用图标等静态资源
├── scripts/                  # 构建和辅助脚本
├── web/                      # 官网（yisi.pages.dev）
├── Yisi/
│   ├── YisiApp.swift         # 应用入口、菜单栏、快捷键注册
│   ├── Core/
│   │   ├── AI/               # AI 服务层
│   │   │   ├── AIService.swift       # 统一 AI 调用接口
│   │   │   ├── Models.swift          # 模型定义
│   │   │   ├── Prompts/             # 翻译和转换 Prompt
│   │   │   └── Providers/           # Gemini / OpenAI / Zhipu / DeepSeek / MiniMax
│   │   ├── Capture/          # 文字捕获（Accessibility + 剪贴板）
│   │   ├── Design/           # 设计系统（主题、颜色、视觉效果）
│   │   ├── History/          # 翻译历史持久化
│   │   ├── Learning/         # Learned Rules 学习引擎
│   │   ├── Localization/     # 多语言支持
│   │   ├── Shared/           # 共享常量和配置
│   │   ├── Shortcut/         # 全局快捷键管理
│   │   ├── SystemTranslation/# macOS 原生离线翻译
│   │   └── Utils/            # 工具函数
│   └── UI/
│       ├── Components/       # 可复用 UI 组件
│       ├── Layout/           # 布局容器
│       ├── ScreenCapture/    # 截图覆盖层
│       ├── Settings/         # 设置面板 + 欢迎引导
│       ├── Translation/      # 翻译结果弹窗
│       └── Window/           # 窗口管理
├── Package.swift
└── LICENSE                   # GPL-3.0
```

---

## 从源码构建

```bash
# 克隆仓库
git clone https://github.com/MUTRO888/Yisi.git
cd Yisi

# 在 Xcode 中打开 Swift Package
xed .
# 或使用命令行
swift build -c release
```

---

## 支持的 AI 提供商

| 提供商 | 文本模型 | 视觉模型 | 说明 |
|--------|---------|---------|------|
| **Gemini** | Gemini Pro 等 | Gemini Pro Vision | Google AI |
| **OpenAI** | GPT-4o 等 | GPT-4o | 兼容 OpenAI 格式的任意服务 |
| **智谱 AI** | GLM-4 等 | GLM-4V | 推荐国内用户，新用户有免费额度 |
| **DeepSeek** | DeepSeek Chat | -- | 高性价比 |
| **MiniMax** | MiniMax Chat | -- | 国产大模型 |

文本模型和视觉模型可分别独立配置，按需选择最适合的组合。

---

## 贡献

欢迎贡献代码。开始之前：

1. Fork 本仓库并创建功能分支
2. 使用 Xcode 打开项目并在本地测试
3. 确保代码风格一致
4. 向 `main` 分支提交 PR，并附上清晰的变更说明

每个 PR 只包含一个功能或修复。

---

## 许可证

[GPL-3.0](LICENSE) -- Copyright (C) 2026 Sonian Mu
