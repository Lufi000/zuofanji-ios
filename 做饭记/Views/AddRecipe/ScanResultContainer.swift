import UIKit

/// 用 class 传递扫描结果，规避 SwiftUI @Binding 在 fullScreenCover onDismiss 时写入丢失的问题。
/// class 是引用类型，RecipeScanView 和 ContentView 持有同一个实例，写入立即可见。
final class ScanResultContainer {
    var suggestion: RecipeAISuggestion?
    var cancelled = false
    /// 抠图结果（透明背景，与 AI 识别并行生成）
    var cutoutImage: UIImage?
    /// 白色描边轮廓图（用于贴纸效果）
    var outlineImage: UIImage?
}
