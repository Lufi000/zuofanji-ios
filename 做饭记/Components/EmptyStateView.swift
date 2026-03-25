import SwiftUI

// MARK: - Empty State View

/// 空状态占位视图：无记录或筛选无结果时展示。
struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(AppTheme.bodyText)
        } description: {
            Text(message)
                .foregroundStyle(AppTheme.bodyText.opacity(0.8))
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .accessibilityLabel(actionTitle)
                    .accessibilityHint("执行主要操作")
            }
        }
    }
}

// MARK: - Presets

extension EmptyStateView {

    /// 首页无记录
    static func noRecipes(onAdd: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "book.closed",
            title: "还没有菜谱",
            message: "记下第一道菜，开始你的菜谱之旅",
            actionTitle: "记一笔",
            action: onAdd
        )
    }

    /// 筛选无结果
    static func noFilterResults(onClear: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "没有符合条件的菜谱",
            message: "试试清除筛选条件",
            actionTitle: "清除筛选",
            action: onClear
        )
    }
}
