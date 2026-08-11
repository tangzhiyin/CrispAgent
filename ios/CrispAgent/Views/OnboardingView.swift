import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.15, blue: 0.30),
                    Color(red: 0.20, green: 0.12, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 36)

                    Image(systemName: "sparkles")
                        .font(.system(size: 62, weight: .medium))
                        .foregroundStyle(.white)

                    VStack(spacing: 8) {
                        Text("Crisp Agent")
                            .font(.largeTitle.bold())
                        Text("真正运行在 iPhone 上的私人 Agent")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .foregroundStyle(.white)

                    VStack(spacing: 14) {
                        OnboardingCard(
                            icon: "cpu",
                            title: "端侧 Gemma 4",
                            detail: "下载约 2.6 GB 的 E2B 模型后，聊天无需云端 API。Gemma 是开放模型系列，不是 Gemini。"
                        )
                        OnboardingCard(
                            icon: "wand.and.stars",
                            title: "直接添加 Skill",
                            detail: "内置 crisp-voice，也可以从“文件”导入 Skill 文件夹或在 App 内新建 SKILL.md。"
                        )
                        OnboardingCard(
                            icon: "lock.shield",
                            title: "Prompt-only 安全边界",
                            detail: "Skill 只能提供文本指令，不能执行脚本、下载代码或获得新的系统权限。"
                        )
                    }

                    Button {
                        onContinue()
                    } label: {
                        Text("开始设置")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.31))

                    Text("模型不会包含在 App 安装包中。下载前会再次显示大小、存储和许可信息。")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 22)
            }
        }
    }
}

private struct OnboardingCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

