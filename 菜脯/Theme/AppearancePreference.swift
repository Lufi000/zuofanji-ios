import Foundation

enum AppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "appearancePreference"

    case classic
    case scrapbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            AppLocalization.text("当前 UI 风格")
        case .scrapbook:
            AppLocalization.text("手帐贴纸风格")
        }
    }

    var description: String {
        switch self {
        case .classic:
            AppLocalization.text("保留现在的首页照片卡片效果。")
        case .scrapbook:
            AppLocalization.text("首页使用笔记本背景，并优先展示透明抠图。")
        }
    }
}
