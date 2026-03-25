import SwiftUI

/// 拍照/选图后的全屏扫描过渡页。
/// 并行执行：AI 菜谱识别 + Vision 抠图（cutout + outline）。
/// AI 识别失败会弹错误提示；抠图失败静默降级（cutoutImage 为 nil，不影响主流程）。
struct RecipeScanView: View {

    let imageData: Data
    /// 结果写入 class 容器，规避 SwiftUI binding 在 fullScreenCover onDismiss 时丢失的问题
    let resultContainer: ScanResultContainer

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var analysisTask: Task<Void, Never>?

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
                ScanningOverlayView(image: image)
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
        .alert("识别失败", isPresented: $showError) {
            Button("重试") {
                startAnalysis()
            }
            Button("跳过", role: .cancel) {
                resultContainer.suggestion = RecipeAISuggestion()
                dismiss()
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            startAnalysis()
        }
        .onDisappear {
            analysisTask?.cancel()
        }
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task { @MainActor in
            guard let image else {
                resultContainer.suggestion = RecipeAISuggestion()
                dismiss()
                return
            }

            // 抠图在后台并行启动（不 await，结果稍后写入）
            let cutoutTask = Task.detached(priority: .userInitiated) {
                await self.cutoutService.extractForeground(from: image)
            }
            let outlineTask = Task.detached(priority: .userInitiated) {
                await self.cutoutService.generateStickerOutline(from: image, outlineWidth: 28)
            }

            // AI 识别（主流程，失败需提示）
            do {
                let suggestion = try await RecipeAIService().analyze(image: image)
                guard !Task.isCancelled else { return }

                // 等待抠图完成（AI 通常更慢，大概率已完成）
                let cutout = await cutoutTask.value
                let outline = await outlineTask.value

                resultContainer.suggestion = suggestion
                resultContainer.cutoutImage = cutout
                resultContainer.outlineImage = outline
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                // 即使 AI 失败，也保存已完成的抠图结果
                resultContainer.cutoutImage = await cutoutTask.value
                resultContainer.outlineImage = await outlineTask.value
                errorMessage = (error as? RecipeAIError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
