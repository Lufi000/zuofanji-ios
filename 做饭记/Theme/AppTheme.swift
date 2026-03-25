import SwiftUI

// MARK: - App Theme

/// 配色方案：美式复古橄榄球 · 暖色调 · 浅色系 · 低饱和
/// 仅浅色模式，详见《设计说明》§3.1
enum AppTheme {

    // MARK: Accent

    /// 主色 / 强调 — 复古橙 #D48848
    static let accent = Color(hex: 0xD48848)

    /// 次要强调 — 复古红 #C06868
    static let accentRed = Color(hex: 0xC06868)

    // MARK: Backgrounds

    /// 主背景 — 奶油白
    static let background = Color(hex: 0xFBF9F6)

    /// 卡片背景 — 略深于主背景
    static let cardBackground = Color(hex: 0xFFFEFC)

    // MARK: Text

    /// 标题文字 — 软棕灰
    static let titleText = Color(hex: 0x5C564C)

    /// 正文 / 次要文字 — 浅棕灰
    static let bodyText = Color(hex: 0x8A8378)

    // MARK: Tag Colors

    /// 标签 · 难度 — 浅芥黄
    static let tagDifficulty = Color(hex: 0xE4DCC4)

    /// 标签 · 菜式 — 复古橙（浅）
    static let tagCuisine = Color(hex: 0xF0D8C0)

    /// 标签 · 耗时 — 浅橄榄灰
    static let tagCookingTime = Color(hex: 0xC4C4B0)

    // MARK: Misc

    /// 分隔线
    static let separator = Color(hex: 0xE8E4DC)

    /// 占位图背景
    static let placeholder = Color(hex: 0xF0EDE8)
}

// MARK: - Color Helpers

extension Color {

    /// 用 0xRRGGBB 十六进制值创建颜色
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
