# Crisp iPhone Agent

这是一个可以从 iPhone 使用的私人 Agent。手机端是可添加到主屏幕的 Web App，
电脑端通过官方 GitHub Copilot SDK 运行常驻 Agent，并直接预加载本项目的：

```text
.agents/skills/crisp-voice/
```

产品形态参考了 [PhoneClaw](https://github.com/kellyvv/PhoneClaw)，但这里采用独立实现：
推理和 Skill 执行发生在你的电脑上，iPhone 只负责聊天、语音输入和展示结果。因此不需要
Xcode、Apple Developer 账号或安装 IPA。

## 已实现

- iPhone 全屏聊天界面，可从 Safari 添加到主屏幕
- 官方 Copilot SDK 常驻会话，支持多轮上下文和流式回复
- 通过 `skills: ["crisp-voice"]` 直接预加载 Skill，而不是复制一份提示词
- 自动加载 `SKILL.md` 引用的 `voice-profile.md`、`knowledge-profile.md` 和
  `examples.md`
- iPhone 语音输入、复制、系统分享、新对话和本地历史
- 配对 Token、同源校验、请求大小限制和会话限流
- Agent 为只读模式：Shell、文件读写、MCP、网络和子 Agent 工具全部不可用
- 可选 HTTPS，电脑与手机也可以通过安全组网访问

## 架构

```text
iPhone Safari / 主屏幕 Web App
              |
        HTTPS 或可信 LAN
              |
      Node.js Agent Gateway
              |
     GitHub Copilot SDK Runtime
              |
  .agents/skills/crisp-voice/SKILL.md
```

Skill 使用 SDK 的 `skillDirectories` 和自定义 Agent `skills` 字段加载。每个新对话
都会重新读取 Skill 及其引用文件，因此修改 Skill 后新建对话即可生效。

## 快速开始

要求：

- Node.js 22.12 或更高版本
- GitHub Copilot 账号
- 已安装并登录 GitHub Copilot CLI
- iPhone 与运行网关的电脑在同一个可信网络

首次安装：

```powershell
cd C:\Crisp_AISKill
npm install
copilot login
```

启动：

```powershell
.\scripts\start.ps1
```

终端会显示一条带随机配对 Token 的 iPhone URL。用 iPhone Safari 打开该 URL，
确认连接成功后选择 **分享 → 添加到主屏幕**。Token 会保存在这台 iPhone 的浏览器中，
不会放进 URL 查询参数或服务器日志。

如果 PowerShell 阻止脚本，可以直接运行：

```powershell
$env:CRISP_AGENT_HOST = "0.0.0.0"
npm start
```

## iPhone 使用

1. 在电脑保持网关运行。
2. iPhone 打开终端显示的配对 URL。
3. 状态变为“已连接”后即可聊天。
4. Safari 中选择 **分享 → 添加到主屏幕**。
5. 修改 `crisp-voice` 后，点右上角 `+` 新建对话来加载新版本。

语音按钮依赖 Safari 的 Web Speech 支持和麦克风权限。局域网 HTTP 下如果按钮不可用，
仍可使用 iPhone 键盘自带的听写；完整语音体验建议配置 HTTPS。

## 配置

环境变量都可以在启动前设置：

| 变量 | 默认值 | 用途 |
|---|---:|---|
| `CRISP_AGENT_HOST` | `0.0.0.0` | 监听地址；`127.0.0.1` 仅允许本机 |
| `CRISP_AGENT_PORT` | `8787` | 网关端口 |
| `CRISP_AGENT_MODEL` | `auto` | Copilot 模型 |
| `CRISP_AGENT_REASONING_EFFORT` | 未设置 | `low`、`medium`、`high`、`xhigh` 或 `max` |
| `CRISP_AGENT_TOKEN` | 自动生成 | 自定义配对 Token，至少 16 个字符 |
| `CRISP_AGENT_SKILL_DIR` | `.agents\skills\crisp-voice` | Skill 目录 |
| `CRISP_AGENT_MAX_SESSIONS` | `20` | 最大活动对话数 |
| `CRISP_AGENT_SESSION_TTL_MS` | `3600000` | 空闲会话回收时间 |
| `CRISP_AGENT_TIMEOUT_MS` | `180000` | 单次回复超时 |
| `CRISP_AGENT_HTTPS_CERT` | 未设置 | PEM 证书路径 |
| `CRISP_AGENT_HTTPS_KEY` | 未设置 | PEM 私钥路径 |

指定模型启动：

```powershell
.\scripts\start.ps1 -Model "gpt-5.4"
```

仅本机监听：

```powershell
.\scripts\start.ps1 -LocalOnly
```

启用 HTTPS 时，证书必须包含手机实际访问的主机名或 IP，并且 iPhone 必须信任其签发 CA：

```powershell
$env:CRISP_AGENT_HTTPS_CERT = "C:\certs\crisp-agent.pem"
$env:CRISP_AGENT_HTTPS_KEY = "C:\certs\crisp-agent-key.pem"
.\scripts\start.ps1
```

## 安全边界

- 默认 HTTP 只适合家庭或办公室可信局域网；不要直接做公网端口映射。
- API 必须携带随机配对 Token，并拒绝跨站 Origin。
- Token 首次生成后保存在 `.data\pairing-token`，该目录已加入 `.gitignore`。
- SDK 使用 `mode: "empty"`，显式工具 allowlist 为空。
- 自定义 Agent 的 `tools` 也为空，权限处理器对任何意外工具请求一律拒绝。
- 对话不会启用 Copilot Memory、MCP、远程控制、文件 Hook 或跨会话检索。
- 使用 GitHub Copilot 模型时，消息会发送到 GitHub Copilot 服务；这不是 PhoneClaw
  的完全离线端侧推理。

## 开发与验证

```powershell
npm run check
npm test
npm run smoke
```

`npm run smoke` 会实际启动 Copilot Runtime，确认 `crisp-voice` 已加载，并执行一次真实
回复；它会消耗正常的 Copilot 用量。

Skill 本身仍位于：

```text
.agents/skills/crisp-voice/
├── SKILL.md
├── references/
│   ├── voice-profile.md
│   ├── knowledge-profile.md
│   └── examples.md
└── evals/
    └── trigger-cases.json
```
