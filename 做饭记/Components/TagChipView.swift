import SwiftUI

// MARK: - Tag Chip View

/// 标签胶囊：用于列表卡片和筛选器中展示标签。
/// 支持两种模式：
/// - 展示（默认）：只读，显示标签文本
/// - 可选（isSelected + onTap）：可点选，用于筛选器
struct TagChipView: View {

    let text: String
    let color: Color
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .white : AppTheme.titleText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? AppTheme.accent : color.opacity(0.5))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.6), lineWidth: isSelected ? 0 : 0.5)
            )
            .contentShape(Capsule())
            .onTapGesture {
                onTap?()
            }
    }
}

// MARK: - Convenience Initializers

extension TagChipView {

    /// 难度标签
    static func difficulty(_ value: Difficulty, isSelected: Bool = false, onTap: (() -> Void)? = nil) -> TagChipView {
        TagChipView(text: value.rawValue, color: AppTheme.tagDifficulty, isSelected: isSelected, onTap: onTap)
    }

    /// 菜式标签
    static func cuisine(_ value: Cuisine, isSelected: Bool = false, onTap: (() -> Void)? = nil) -> TagChipView {
        TagChipView(text: value.rawValue, color: AppTheme.tagCuisine, isSelected: isSelected, onTap: onTap)
    }

    /// 耗时标签
    static func cookingTime(_ value: CookingTime, isSelected: Bool = false, onTap: (() -> Void)? = nil) -> TagChipView {
        TagChipView(text: value.rawValue, color: AppTheme.tagCookingTime, isSelected: isSelected, onTap: onTap)
    }
}

#Preview("Tags") {
    HStack {
        TagChipView.difficulty(.easy)
        TagChipView.cuisine(.hunan)
        TagChipView.cookingTime(.fifteen)
        TagChipView.difficulty(.medium, isSelected: true)
    }
    .padding()
}
