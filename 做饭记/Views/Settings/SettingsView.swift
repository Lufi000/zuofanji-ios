import SwiftUI

// MARK: - Settings View

/// 设置页：导出菜谱（v0.2）、关于等。
/// v0.1 仅展示基本信息，预留导出入口。
struct SettingsView: View {

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                dataSection
            }
            .navigationTitle("设置")
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(AppTheme.bodyText)
            }

            HStack {
                Text("What's Cooking")
                Spacer()
                Text("记录每天做的菜")
                    .foregroundStyle(AppTheme.bodyText)
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            // v0.2: 导出菜谱功能入口
            Label("导出我的菜谱", systemImage: "square.and.arrow.up")
                .foregroundStyle(AppTheme.bodyText.opacity(0.5))
                // TODO: v0.2 实现导出功能
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
