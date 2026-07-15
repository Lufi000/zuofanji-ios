import UIKit
import Observation

/// 用 class 传递扫描结果，规避 SwiftUI @Binding 在 fullScreenCover onDismiss 时写入丢失的问题。
/// class 是引用类型，RecipeScanView 和 ContentView 持有同一个实例，写入立即可见。
@Observable
@MainActor
final class ScanResultContainer {
    var suggestion: RecipeAISuggestion?
    var aiUnavailableMessage: String?
    var isAIAnalyzing = false
    var shouldShowSubscriptionPrompt = false
    var cancelled = false
    /// 抠图结果（透明背景，与 AI 识别并行生成）
    var cutoutImage: UIImage?
    /// 白色描边轮廓图（用于贴纸效果）
    var outlineImage: UIImage?
    /// 递增版本号，用于详情页只处理一次异步到达的结果。
    var suggestionVersion = 0
    var aiUnavailableVersion = 0
    var imageVersion = 0
    var aiTask: Task<Void, Never>?

    func reset() {
        aiTask?.cancel()
        aiTask = nil
        suggestion = nil
        aiUnavailableMessage = nil
        isAIAnalyzing = false
        shouldShowSubscriptionPrompt = false
        cancelled = false
        cutoutImage = nil
        outlineImage = nil
        suggestionVersion = 0
        aiUnavailableVersion = 0
        imageVersion = 0
    }

    func cancel() {
        aiTask?.cancel()
        aiTask = nil
        cancelled = true
        isAIAnalyzing = false
    }

    func setCutout(_ cutoutImage: UIImage?, outlineImage: UIImage?) {
        self.cutoutImage = cutoutImage
        self.outlineImage = outlineImage
        imageVersion += 1
    }

    func beginAI() {
        suggestion = nil
        aiUnavailableMessage = nil
        shouldShowSubscriptionPrompt = false
        isAIAnalyzing = true
    }

    func finishAI(with suggestion: RecipeAISuggestion) {
        self.suggestion = suggestion
        aiUnavailableMessage = nil
        shouldShowSubscriptionPrompt = false
        isAIAnalyzing = false
        aiTask = nil
        suggestionVersion += 1
    }

    func failAI(message: String, shouldShowSubscriptionPrompt: Bool) {
        aiUnavailableMessage = message
        self.shouldShowSubscriptionPrompt = shouldShowSubscriptionPrompt
        isAIAnalyzing = false
        aiTask = nil
        aiUnavailableVersion += 1
    }
}
