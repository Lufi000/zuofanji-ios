import Foundation

enum StickerEffectStyle: String, CaseIterable, Identifiable {
    static let storageKey = "stickerEffectStyle"
    static let defaultStyle: StickerEffectStyle = .whiteOutline
    static let defaultRawValue = defaultStyle.rawValue

    static let displayOrder: [StickerEffectStyle] = [
        .plainCutout,
        .whiteOutline,
        .childhood
    ]

    case plainCutout
    case whiteOutline
    case childhood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainCutout:
            AppLocalization.text("原始抠图")
        case .whiteOutline:
            AppLocalization.text("经典白边")
        case .childhood:
            AppLocalization.text("童年彩边")
        }
    }

    var description: String {
        switch self {
        case .plainCutout:
            AppLocalization.text("只显示透明抠图，保留照片本身的边缘。")
        case .whiteOutline:
            AppLocalization.text("给抠图加一圈干净白边，像基础贴纸。")
        case .childhood:
            AppLocalization.text("叠加红黄蓝手绘描边和彩纸装饰，接近复古贴纸机效果。")
        }
    }
}
