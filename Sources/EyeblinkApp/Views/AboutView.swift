import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "eye.circle.fill").font(.system(size: 56, weight: .light)).foregroundStyle(.teal)
                        .accessibilityHidden(true)
                    Text("Eyeblink").font(.largeTitle.weight(.semibold))
                    Text(model.text("眨眨眼，歇一会儿。", "Blink. Breathe. Take a little break.")).font(.title3).foregroundStyle(.secondary)
                    Text(model.text("版本 \(version) · Apple Silicon 原生", "Version \(version) · Native Apple Silicon")).font(.callout).foregroundStyle(.secondary)
                }.padding(.vertical, 15).frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Text(model.text("这是独立重现的 macOS 应用，以 eyeblink 3.7.4.0 的本机功能为参考。原作者、原软件与本项目分别归属各自权利人。", "An independent macOS reconstruction informed by the local behavior of eyeblink 3.7.4.0. The original software and this project belong to their respective owners."))
                    .foregroundStyle(.secondary)
                LabeledContent(model.text("界面", "Interface"), value: model.text("SwiftUI 与 AppKit", "SwiftUI & AppKit"))
                LabeledContent(model.text("检测", "Detection"), value: model.text("本机眨眼运动分析", "On-device blink motion analysis"))
            } header: { Text(model.text("关于这个项目", "About this project")) }
            Section {
                Link(destination: URL(string: "https://www.blinkingmatters.com/features#faq")!) {
                    Label(model.text("原软件常见问题", "Original app FAQ"), systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.blinkingmatters.com/dry-eye-syndrome#mgd")!) {
                    Label(model.text("原作者的 MGD 说明", "Original author’s MGD information"), systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.blinkingmatters.com/terms-and-conditions")!) {
                    Label(model.text("原软件条款与隐私说明", "Original app terms & privacy"), systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "mailto:support@blinkingmatters.com")!) {
                    Label(model.text("联系原作者", "Contact the original author"), systemImage: "envelope")
                }
                Link(destination: URL(string: "https://www.facebook.com/blinkingmatters/")!) {
                    Label(model.text("原作 Facebook", "Original app on Facebook"), systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.dryeyefoundation.org")!) {
                    Label(model.text("Dry Eye Foundation", "Dry Eye Foundation"), systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://www.paypal.com/donate?hosted_button_id=V9CBXV3LS3L5N")!) {
                    Label(model.text("支持原作者", "Support the original author"), systemImage: "heart")
                }
            } header: { Text(model.text("原作参考", "Original app references")) } footer: {
                Text(model.text("以上链接前往原作者网站，适用于原软件。新版相机与数据处理规则见“设置”。", "These links open the original author’s website and describe the original software. This app’s camera and data practices are described in Settings."))
            }
            Section {
                Button(model.text("第三方软件许可", "Third-party licenses")) {
                    if let root = Bundle.main.resourceURL { NSWorkspace.shared.open(root.appendingPathComponent("Licenses")) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
