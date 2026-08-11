# Crisp iPhone Agent

Crisp Agent 现在以**原生 SwiftUI iOS App**为主：Gemma 4 模型下载到
iPhone 后由 [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)
在本机运行，并直接加载、导入和管理 `SKILL.md`。

> 正确的开放模型名称是 **Google Gemma 4**，不是 Gemini 4。Gemini 是另一条
> 产品线。

## 当前能力

- 原生 iOS 17+ SwiftUI App，可签名并发布到 TestFlight
- App 内下载 Gemma 4 E2B 或 E4B `.litertlm` 模型
- 后台下载、暂停、继续、取消、镜像回退和磁盘空间预检
- 使用固定模型 revision、精确文件大小和流式 SHA-256 校验
- LiteRT-LM 流式生成、取消生成、4K KV cache 和 GPU→CPU 自动回退
- 内置 `.agents/skills/crisp-voice`
- 从 Files 导入 Skill 文件夹或单独的 `SKILL.md`
- 在 App 内新建、编辑、启用、关闭和删除本机 Skill
- Skill 路径、UTF-8、扩展名、文件数量、单文件大小和总大小验证
- Prompt-only 安全边界：导入的 Skill 不能执行代码或增加系统权限
- 本地聊天历史和离线使用

LiteRT-LM `0.15.0` 的运行时可用于产品，但 Swift API 当前仍标记为
**Early Preview**。升级依赖前应先在真机重新验证 API、性能和内存。

## 项目位置

```text
C:\Crisp_AISKill
├── ios\
│   ├── project.yml                 # XcodeGen 工程定义
│   ├── CrispAgent\                 # 原生 App 源码
│   ├── CrispAgentTests\            # Skill 与模型完整性测试
│   └── THIRD_PARTY_NOTICES.md
├── .agents\skills\crisp-voice\     # App 内置的默认 Skill
├── src\                            # 可选的旧 Copilot 网关
├── public\                         # 可选的旧 PWA
└── scripts\
```

XcodeGen 会把 `.agents\skills\` 作为名为 `skills` 的文件夹资源放进 App
Bundle，因此 `crisp-voice` 保持单一源码，不需要复制两份。

## 原生架构

```text
iPhone SwiftUI
    ├── ModelStore
    │   ├── Background URLSession
    │   ├── exact size + SHA-256
    │   └── Application Support/Models
    ├── LocalInferenceEngine
    │   └── LiteRT-LM 0.15.0 / Metal GPU / CPU fallback
    └── SkillStore
        ├── Bundle/.agents/skills/crisp-voice
        ├── Files import + in-app editor
        └── bounded prompt-only context
```

模型、推理 cache 和用户 Skill 的落盘位置：

```text
Library/Application Support/CrispAgent/Models/
Library/Application Support/CrispAgent/Skills/
Library/Caches/CrispAgent/LiteRTLM/
```

模型是可重新下载的数据，因此已排除 iCloud Backup；用户导入或编辑的 Skill
默认保留在 App 数据备份中。

## 模型

| 模型 | 下载大小 | SHA-256 | 建议 |
|---|---:|---|---|
| Gemma 4 E2B | 2,588,147,712 bytes | `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c` | 默认，建议 6 GB+ 内存 |
| Gemma 4 E4B | 3,659,530,240 bytes | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | 高内存 Pro 机型，建议 8 GB |

主下载 URL 固定到 Hugging Face 的不可变 commit；镜像只有在最终文件满足相同
大小和 SHA-256 时才会安装。

E2B 是首发推荐模型。E4B 的 GPU 峰值内存较高，部分设备可能触发 iOS jetsam；
自动后端会在低内存设备优先选择 CPU，但仍必须逐个设备验证。

## 在 Mac 上生成和运行

要求：

- Apple Silicon Mac
- Xcode 26 或符合 Apple 当前上传要求的更新版本
- XcodeGen
- Apple Developer Program 账号（真机调试可先用免费账号，TestFlight 必须付费）

安装 XcodeGen：

```bash
brew install xcodegen
```

生成 Xcode 工程：

```bash
cd Crisp_AISKill/ios
xcodegen generate
open CrispAgent.xcodeproj
```

然后在 Xcode 中：

1. 选择 `CrispAgent` target 的 **Signing & Capabilities**。
2. 选择你的 Apple Developer Team。
3. 将 Bundle Identifier 从 `com.crisp.CrispAgent` 改成你自己的唯一 ID。
4. 选择真实 iPhone 并运行。
5. 在 App 的“模型”页先下载 E2B，完成哈希校验后测试聊天。
6. 在“Skills”页确认 `crisp-voice` 已启用，再测试改写和回复场景。

如果要永久修改 Bundle ID，请改 `ios/project.yml` 中的
`PRODUCT_BUNDLE_IDENTIFIER`，然后重新运行 `xcodegen generate`。

模拟器可以验证 UI、Skill 导入和文件状态，但模型性能、Metal、内存、后台下载和
jetsam 必须在真实 iPhone 上验证。

## 添加 Skill

### 内置 Skill

默认 Skill 位于：

```text
.agents\skills\crisp-voice\
├── SKILL.md
├── references\
│   ├── voice-profile.md
│   ├── knowledge-profile.md
│   └── examples.md
└── evals\
    └── trigger-cases.json
```

修改这些文件后重新构建 App，新版本就会包含更新后的 Skill。

### 从 iPhone 导入

在 **Skills → +** 中可以：

1. 导入包含根级 `SKILL.md` 的完整文件夹。
2. 导入不引用其他本地文件的单独 `SKILL.md`。
3. 直接新建一个 Skill。

限制：

- `name` 必须匹配 `^[a-z0-9][a-z0-9._-]{0,63}$`
- 只允许 `.md`、`.txt` 和 `.json`
- 最多 24 个文件
- 单文件最多 64 KiB
- 总大小最多 256 KiB
- 拒绝符号链接、目录逃逸、控制字符和归一化后重复路径

第一版只支持 **prompt-only Skill**。即使 frontmatter 声明了工具，App 也不会
执行它们。没有 Shell、MCP、任意文件访问、动态库、JavaScript、WASM 或下载代码
执行路径。

端侧会话使用 4K KV cache。App 会优先保留每个启用 Skill 的根指令，再按剩余预算
加入 references；本机导入 Skill 优先于内置 Skill。单条消息上限为 2,000 字符，
最近历史也会按本次输入动态缩减，避免上下文溢出。聊天记录会继续保存在 UI 中。

## 从 GitHub 发布到 TestFlight

GitHub 仓库本身不能直接进入 TestFlight。TestFlight 接收的是由 Xcode 签名并上传
到 App Store Connect 的 iOS archive。

### 1. 准备 Apple 账号

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/)。
2. 在 Certificates, Identifiers & Profiles 中注册唯一 Bundle ID。
3. 在 [App Store Connect](https://appstoreconnect.apple.com/) 的 **My Apps**
   新建 App，并选择同一个 Bundle ID。
4. 准备 App 名称、分类、支持网址和隐私政策网址。

如果 App 确实不收集数据，App Privacy 中可以按实际情况填写“不收集数据”；模型
下载仍会连接 Hugging Face 或 ModelScope，隐私政策应明确这一网络请求。

### 2. 真机验收

上传前至少覆盖：

- E2B 完整下载、暂停/继续、空间不足和 SHA-256 失败
- Wi-Fi、蜂窝网络、锁屏、切后台、系统终止和用户强制退出
- GPU 初始化失败后的 CPU 回退
- 连续多轮对话、取消生成、发热和内存压力
- Skill 文件夹导入、恶意路径/符号链接拒绝和本机覆盖恢复
- 所有支持的 iPhone 内存档位

### 3. Archive 并上传

在 Xcode 中：

1. Scheme 选择 `CrispAgent`。
2. Destination 选择 **Any iOS Device (arm64)**。
3. 运行 **Product → Archive**。
4. Organizer 打开后选择 **Distribute App**。
5. 选择 **App Store Connect → Upload**。
6. 保持自动签名，完成校验并上传。

`Info.plist` 已设置 `ITSAppUsesNonExemptEncryption = false`，因为 App 没有自定义
非豁免加密；如以后加入其他加密能力，必须重新判断。

`PrivacyInfo.xcprivacy` 已声明 App 自有 UserDefaults、下载前磁盘空间检查，以及
App 容器/用户选择文件元数据验证所使用的 Required Reason API。加入新 SDK 或系统
API 后，应在 Archive 的 Privacy Report 中重新审计。

### 4. 配置 TestFlight

1. 等待 App Store Connect 处理 build。
2. 填写 Test Information、测试说明、反馈邮箱和 Beta App Review 联系信息。
3. 先加入 Internal Testing；内部测试员通常不需要 Beta Review。
4. External Testing 首个 build 需要提交 Beta App Review。
5. 审核通过后创建公开链接或通过邮箱邀请外部用户。

建议在 Beta Review Notes 中写明：

```text
The app downloads a 2.6 GB Gemma 4 E2B model as non-executable data after
explicit user consent. Inference runs locally with the LiteRT-LM runtime already
included in the reviewed binary. Imported Skills are Markdown/text configuration
only and cannot introduce executable code, native tools, or new permissions.
For review: open Models, download Gemma 4 E2B, select it, then return to Chat.
The built-in crisp-voice Skill is enabled by default.
```

大型首次资源下载和本地 Skill 导入仍由 Apple 最终审核判断。不要加入远程 Skill
市场、可执行脚本或动态插件，否则会显著改变 App Review 风险。

### 5. GitHub 自动化（可选）

可以以后使用 GitHub Actions + Fastlane 上传，但签名证书、provisioning profile 和
App Store Connect API Key 必须放在 GitHub Environments/Secrets，绝不能提交到
仓库。第一次发布建议先使用 Xcode Organizer，确认签名和 App Store Connect 配置
全部正确后再自动化。

## Windows 能做与不能做的事

当前仓库是在 Windows 上生成的。Windows 可以编辑 Swift、维护 XcodeGen 配置、
运行 Node 测试和生成 App 图标，但不能：

- 编译 SwiftUI/UIKit iOS target
- 链接 LiteRT-LM iOS XCFramework
- 运行 iOS Simulator
- 签名、Archive 或上传 TestFlight
- 验证 Metal、jetsam、发热和后台系统唤醒

最终必须在 Mac/Xcode 和真实 iPhone 上运行：

```bash
cd ios
xcodegen generate
xcodebuild -resolvePackageDependencies -project CrispAgent.xcodeproj
xcodebuild test \
  -project CrispAgent.xcodeproj \
  -scheme CrispAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 本地源码检查

生成 App 图标：

```powershell
npm run ios:icon
```

旧 Node/PWA 网关的检查仍可运行：

```powershell
npm run check
npm test
npm run smoke
```

`npm run smoke` 会调用 GitHub Copilot 并消耗正常用量；原生 iOS App 不依赖它。

## 可选：继续使用旧 PWA 网关

原有 Copilot SDK 网关仍保留在 `src\` 和 `public\`，适合不具备 Mac/Xcode 环境时
从 iPhone Safari 使用：

```powershell
cd C:\Crisp_AISKill
npm install
.\scripts\start.ps1
```

这个旧模式需要电脑持续运行，并会把消息发送到 GitHub Copilot；它不是端侧离线
推理，也不能上传到 TestFlight。
