import SwiftUI

/// 拍照/选图后的全屏扫描过渡页。
/// 并行执行：AI 菜谱识别 + Vision 抠图（cutout + outline）。
/// AI 识别失败会弹错误提示；抠图失败静默降级（cutoutImage 为 nil，不影响主流程）。
struct RecipeScanView: View {

    let imageData: Data
    /// 结果写入 class 容器，规避 SwiftUI binding 在 fullScreenCover onDismiss 时丢失的问题
    let resultContainer: ScanResultContainer
    var onOpenSubscription: () -> Void = {}

    @State private var errorMessage: String?
    @State private var isSubscriptionError = false
    @State private var showError = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?
    @State private var scanStep: ScanStep = .preparingImage
    @State private var progressPercent = 0

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    private var image: UIImage? { UIImage(data: imageData) }

    private let cutoutService: ImageCutoutService = {
        let service = ImageCutoutService()
        service.featherRadius = 1.5
        service.edgeErosionRadius = 1.0
        return service
    }()

    var body: some View {
        ZStack {
            if let image {
                ScanningOverlayView(
                    image: image,
                    statusText: scanStep.statusText,
                    currentStep: scanStep.rawValue,
                    totalSteps: ScanStep.allCases.count,
                    progressPercent: progressPercent
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
                        resultContainer.cancelled = true
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
        .alert(isSubscriptionError ? "需要 Snap Recipe Plus" : "AI 识别暂不可用", isPresented: $showError) {
            if isSubscriptionError {
                Button("去订阅") {
                    resultContainer.cancelled = true
                    onOpenSubscription()
                    dismiss()
                }
            } else {
                Button("重试") {
                    startAnalysis()
                }
            }
            Button("手动填写", role: .cancel) {
                resultContainer.suggestion = RecipeAISuggestion()
                resultContainer.aiUnavailableMessage = errorMessage
                dismiss()
            }
        } message: {
            if isSubscriptionError {
                Text(errorMessage ?? "开通后即可使用 AI 识别。")
            } else {
                Text("你仍然可以继续添加照片，并手动填写菜名、原材料和做法。\n\n\(errorMessage ?? "")")
            }
        }
        .onAppear {
            startAnalysis()
        }
        .onDisappear {
            analysisTask?.cancel()
            progressTask?.cancel()
        }
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        progressTask?.cancel()
        isSubscriptionError = false
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
                await self.cutoutService.extractForeground(from: image)
            }
            let outlineTask = Task.detached(priority: .userInitiated) {
                await self.cutoutService.generateStickerOutline(from: image, outlineWidth: 28)
            }

            // AI 识别（主流程，失败需提示）
            let recognitionProgressTask = Task { @MainActor in
                await advanceRecognitionSteps()
            }
            do {
                try subscriptionStore.validateAIRequestAccess()
                let suggestion = try await RecipeAIService().analyze(image: image)
                subscriptionStore.recordSuccessfulAIRequest()
                guard !Task.isCancelled else { return }
                recognitionProgressTask.cancel()

                // 等待抠图完成（AI 通常更慢，大概率已完成）
                scanStep = .makingSticker
                progressPercent = max(progressPercent, scanStep.progressFloor)
                let cutout = await cutoutTask.value
                let outline = await outlineTask.value

                scanStep = .organizingRecipe
                progressPercent = 100
                resultContainer.suggestion = suggestion
                resultContainer.aiUnavailableMessage = nil
                resultContainer.cutoutImage = cutout
                resultContainer.outlineImage = outline
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                recognitionProgressTask.cancel()
                progressTask?.cancel()
                // 即使 AI 失败，也保存已完成的抠图结果
                resultContainer.cutoutImage = await cutoutTask.value
                resultContainer.outlineImage = await outlineTask.value
                isSubscriptionError = error is AISubscriptionAccessError
                errorMessage = (error as? RecipeAIError)?.errorDescription ?? error.localizedDescription
                showError = true
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
            (2, .identifyingDish),
            (5, .extractingIngredients),
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
    case identifyingDish
    case extractingIngredients
    case draftingSteps
    case makingSticker
    case organizingRecipe

    var statusText: String {
        switch self {
        case .preparingImage:
            return "正在处理照片…"
        case .uploadingImage:
            return "正在上传图片…"
        case .identifyingDish:
            return "正在识别菜品和菜系…"
        case .extractingIngredients:
            return "正在提取食材和用量…"
        case .draftingSteps:
            return "正在生成做法步骤…"
        case .makingSticker:
            return "正在生成菜品贴纸…"
        case .organizingRecipe:
            return "正在整理菜谱信息…"
        }
    }

    var progressFloor: Int {
        switch self {
        case .preparingImage:
            return 4
        case .uploadingImage:
            return 12
        case .identifyingDish:
            return 28
        case .extractingIngredients:
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
        case .identifyingDish:
            return 48
        case .extractingIngredients:
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
