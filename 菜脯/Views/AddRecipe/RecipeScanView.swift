import SwiftUI

/// 拍照/选图后的全屏扫描过渡页。
/// 并行执行：AI 内容整理 + Vision 抠图（cutout + outline）。
/// AI 识别失败会弹错误提示；抠图失败静默降级（cutoutImage 为 nil，不影响主流程）。
struct RecipeScanView: View {

    let imageData: Data
    /// 结果写入 class 容器，规避 SwiftUI binding 在 fullScreenCover onDismiss 时丢失的问题
    let resultContainer: ScanResultContainer
    var onOpenSubscription: () -> Void = {}

    @State private var analysisTask: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?
    @State private var contourPreviewTask: Task<Void, Never>?
    @State private var scanStep: ScanStep = .preparingImage
    @State private var progressPercent = 0
    @State private var tracingContourImage: UIImage?

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    private var image: UIImage? { UIImage(data: imageData) }

    private nonisolated static func makeCutoutService() -> ImageCutoutService {
        let service = ImageCutoutService()
        service.featherRadius = 1.5
        service.edgeErosionRadius = 1.0
        return service
    }

    var body: some View {
        ZStack {
            if let image {
                ScanningOverlayView(
                    image: image,
                    statusText: scanStep.statusText,
                    currentStep: scanStep.rawValue,
                    totalSteps: ScanStep.allCases.count,
                    progressPercent: progressPercent,
                    tracingContourImage: tracingContourImage
                )
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        analysisTask?.cancel()
                        contourPreviewTask?.cancel()
                        resultContainer.cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .onAppear {
            startAnalysis()
        }
        .onDisappear {
            analysisTask?.cancel()
            progressTask?.cancel()
            contourPreviewTask?.cancel()
        }
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        progressTask?.cancel()
        contourPreviewTask?.cancel()
        tracingContourImage = nil
        resultContainer.cancelled = false
        resultContainer.beginAI()
        scanStep = .preparingImage
        progressPercent = 4
        progressTask = Task { @MainActor in
            await advanceProgressPercent()
        }
        analysisTask = Task { @MainActor in
            guard let image else {
                resultContainer.suggestion = RecipeAISuggestion()
                dismiss()
                return
            }

            // 抠图在后台并行启动（不 await，结果稍后写入）
            scanStep = .uploadingImage
            progressPercent = max(progressPercent, scanStep.progressFloor)
            let cutoutTask = Task.detached(priority: .userInitiated) {
                let service = Self.makeCutoutService()
                return await service.extractForeground(from: image)
            }
            let outlineTask = Task.detached(priority: .userInitiated) {
                let service = Self.makeCutoutService()
                let outline = await service.generateStickerOutline(from: image, outlineWidth: 28)
                let contour = outline.flatMap {
                    service.generateTracingContour(from: $0, width: 10)
                }
                return (outline: outline, contour: contour)
            }
            contourPreviewTask = Task { @MainActor in
                let outlineResult = await outlineTask.value
                guard !Task.isCancelled else { return }
                tracingContourImage = outlineResult.contour
            }

            startAIAnalysis(for: image)

            // 抠图是进入详情页的门槛，AI 会在详情页继续更新。
            let recognitionProgressTask = Task { @MainActor in
                await advanceRecognitionSteps()
            }
            scanStep = .makingSticker
            progressPercent = max(progressPercent, scanStep.progressFloor)
            let cutout = await cutoutTask.value
            let outlineResult = await outlineTask.value
            guard !Task.isCancelled else {
                recognitionProgressTask.cancel()
                return
            }
            recognitionProgressTask.cancel()
            scanStep = .organizingRecipe
            progressPercent = 100
            resultContainer.setCutout(cutout, outlineImage: outlineResult.outline)
            tracingContourImage = outlineResult.contour
            dismiss()
        }
    }

    private func startAIAnalysis(for image: UIImage) {
        resultContainer.aiTask?.cancel()
        resultContainer.aiTask = Task { @MainActor in
            do {
                try subscriptionStore.validateAIRequestAccess()
                let suggestion = try await RecipeAIService().analyze(image: image)
                subscriptionStore.recordSuccessfulAIRequest()
                guard !Task.isCancelled else { return }
                resultContainer.finishAI(with: suggestion)
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? RecipeAIError)?.errorDescription ?? error.localizedDescription
                resultContainer.failAI(
                    message: message,
                    shouldShowSubscriptionPrompt: error is AISubscriptionAccessError
                )
            }
        }
    }

    @MainActor
    private func advanceProgressPercent() async {
        while !Task.isCancelled {
            let cap = scanStep.progressCap
            if progressPercent < cap {
                withAnimation(.linear(duration: 0.25)) {
                    progressPercent += 1
                }
            }

            do {
                try await Task.sleep(nanoseconds: 550_000_000)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func advanceRecognitionSteps() async {
        let updates: [(seconds: UInt64, step: ScanStep)] = [
            (2, .understandingPhoto),
            (5, .collectingDetails),
            (6, .draftingSteps)
        ]

        for update in updates {
            do {
                try await Task.sleep(nanoseconds: update.seconds * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, scanStep.rawValue < ScanStep.makingSticker.rawValue else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                scanStep = update.step
                progressPercent = max(progressPercent, update.step.progressFloor)
            }
        }
    }
}

private enum ScanStep: Int, CaseIterable {
    case preparingImage = 1
    case uploadingImage
    case understandingPhoto
    case collectingDetails
    case draftingSteps
    case makingSticker
    case organizingRecipe

    var statusText: String {
        switch self {
        case .preparingImage:
            return AppLocalization.text("我先把照片里的重点找出来")
        case .uploadingImage:
            return AppLocalization.text("这张图有点意思，正在慢慢看")
        case .understandingPhoto:
            return AppLocalization.text("先把主角贴出来，文字马上补上")
        case .collectingDetails:
            return AppLocalization.text("我在帮你整理成一页记录")
        case .draftingSteps:
            return AppLocalization.text("正在把可用的信息写下来")
        case .makingSticker:
            return AppLocalization.text("贴纸准备好了，文字继续整理")
        case .organizingRecipe:
            return AppLocalization.text("马上整理好这一页")
        }
    }

    var progressFloor: Int {
        switch self {
        case .preparingImage:
            return 4
        case .uploadingImage:
            return 12
        case .understandingPhoto:
            return 28
        case .collectingDetails:
            return 52
        case .draftingSteps:
            return 72
        case .makingSticker:
            return 90
        case .organizingRecipe:
            return 98
        }
    }

    var progressCap: Int {
        switch self {
        case .preparingImage:
            return 10
        case .uploadingImage:
            return 24
        case .understandingPhoto:
            return 48
        case .collectingDetails:
            return 68
        case .draftingSteps:
            return 88
        case .makingSticker:
            return 96
        case .organizingRecipe:
            return 99
        }
    }
}
