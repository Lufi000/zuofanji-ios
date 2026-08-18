import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Image Data Transferable (PhotosPicker 选图回传用)

/// 从 PhotosPicker 可靠加载图片为 Data（系统对 Data.self 可能返回 nil）
private struct AddRecipeImageTransfer: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            AddRecipeImageTransfer(data: data)
        }
    }
}

private enum RecipeListEditor: String, Identifiable {
    case ingredients
    case steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ingredients:
            return "食材"
        case .steps:
            return "步骤"
        }
    }
}

private struct DescriptionVariantOptionCard: View {
    let variant: DescriptionVariant
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.caption.weight(.semibold))
                    Text(variant.title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(titleColor)

                Text(variant.text)
                    .font(.caption2)
                    .foregroundStyle(bodyColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: 156, alignment: .topLeading)
            .frame(minHeight: 92, alignment: .topLeading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(variant.title)
        .accessibilityHint("选择这一版文案")
    }

    private var titleColor: Color {
        isSelected ? .white : AppTheme.titleText
    }

    private var bodyColor: Color {
        isSelected ? .white.opacity(0.82) : AppTheme.bodyText
    }

    private var backgroundColor: Color {
        isSelected ? AppTheme.accent : AppTheme.cardBackground
    }

    private var borderColor: Color {
        isSelected ? AppTheme.accent.opacity(0.85) : AppTheme.bodyText.opacity(0.14)
    }

    private var iconName: String {
        switch variant.style {
        case .journal:
            return "text.book.closed"
        case .story:
            return "text.quote"
        case .poem:
            return "sparkles"
        }
    }
}

// MARK: - Add Recipe View

/// 新增菜谱表单（拍照优先流程）。
/// 通过 initialImageData 接收相机/相册传入的照片，照片作为 Hero 展示。
/// 也可传入 recipeToEdit 进入编辑模式。
struct AddRecipeView: View {

    /// 从相机/相册传入的初始照片
    var initialImageData: Data?
    /// 编辑模式：传入已有菜谱
    var recipeToEdit: Recipe?
    /// AI 预识别结果（从 RecipeScanView 传入）
    var initialSuggestion: RecipeAISuggestion?
    /// AI 不可用时的非阻断提示（用户仍可手动填写）
    var initialAIUnavailableMessage: String?
    /// 抠图结果（透明背景）
    var initialCutoutImage: UIImage?
    /// 贴纸描边轮廓图
    var initialOutlineImage: UIImage?
    /// 扫描页共享状态：抠图完成后先进入详情页，AI 结果稍后写入这里。
    var scanResultContainer: ScanResultContainer?

    @State private var viewModel = AddRecipeViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var didCompleteSave = false
    @State private var didInitializeForm = false
    @State private var appliedSuggestionVersion = 0
    @State private var appliedImageVersion = 0
    @State private var isShowingRecipeUpdateDialog = false
    @State private var showSubscription = false
    @State private var listEditor: RecipeListEditor?
    @State private var listEditorDraft = ""
    @AppStorage(StickerEffectStyle.storageKey) private var stickerEffectStyleRawValue = StickerEffectStyle.defaultRawValue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    private var isEditing: Bool { recipeToEdit != nil }
    private var isRecognizing: Bool {
        viewModel.isAILoading || (scanResultContainer?.isAIAnalyzing ?? false)
    }
    private var currentAIUnavailableMessage: String? {
        scanResultContainer?.aiUnavailableMessage ?? initialAIUnavailableMessage
    }
    private var currentOutlineImage: UIImage? {
        scanResultContainer?.outlineImage ?? initialOutlineImage
    }
    private var stickerEffectStyle: StickerEffectStyle {
        StickerEffectStyle(rawValue: stickerEffectStyleRawValue) ?? .defaultStyle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    photoHeroSection
                    stickerEffectPicker
                    aiUnavailableNotice
                    formContent
                }
            }
            .background(AppTheme.background)
            .navigationTitle(AppLocalization.text(isEditing ? "编辑" : "新建"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveButtonTapped()
                    } label: {
                        Text("保存")
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid || viewModel.isSaving || isRecognizing)
                    .accessibilityHint("保存这张照片和记录，需先添加照片")
                }
            }
            .alert(AppLocalization.text(viewModel.shouldShowSubscriptionPrompt ? "需要 菜脯 Plus" : "识别失败"), isPresented: Binding(
                get: { viewModel.aiError != nil },
                set: { if !$0 { viewModel.aiError = nil } }
            )) {
                if viewModel.shouldShowSubscriptionPrompt {
                    Button("去订阅") {
                        viewModel.aiError = nil
                        showSubscription = true
                    }
                }
                Button("好") { viewModel.aiError = nil }
            } message: {
                Text(viewModel.aiError ?? "")
            }
            .confirmationDialog(
                "替换当前文字？",
                isPresented: Binding(
                    get: { viewModel.shouldConfirmDescriptionReplacement },
                    set: { if !$0 { viewModel.cancelPendingDescriptionVariantReplacement() } }
                ),
                titleVisibility: .visible
            ) {
                Button("替换当前文字") {
                    viewModel.confirmPendingDescriptionVariantReplacement()
                }
                Button("取消", role: .cancel) {
                    viewModel.cancelPendingDescriptionVariantReplacement()
                }
            } message: {
                Text("你已经修改过这段描述，切换版本会用新文案覆盖当前文字。")
            }
            .sheet(isPresented: $showSubscription) {
                NavigationStack {
                    SubscriptionView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { showSubscription = false }
                            }
                        }
                }
            }
            .sheet(item: $listEditor) { editor in
                listEditorSheet(for: editor)
            }
            .overlay {
                if isShowingRecipeUpdateDialog {
                    recipeUpdateDialog
                }
            }
            .onAppear {
                initializeFormIfNeeded()
            }
            .onChange(of: scanResultContainer?.imageVersion ?? 0) { _, _ in
                applyScanImagesIfNeeded()
            }
            .onChange(of: scanResultContainer?.suggestionVersion ?? 0) { _, _ in
                applyScanSuggestionIfNeeded()
            }
        }
    }

    // MARK: - Photo Hero

    /// 顶部大图展示，附带更换/选择照片入口及 AI 识别按钮
    private var photoHeroSection: some View {
        ZStack(alignment: .bottomTrailing) {
            heroImageContent

            // 右下角：更换照片按钮
            let hasPhoto = viewModel.imageData != nil
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    AppLocalization.text(hasPhoto ? "更换" : "选择照片"),
                    systemImage: "photo.on.rectangle"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
            }
            .accessibilityLabel(AppLocalization.text(hasPhoto ? "更换照片" : "选择照片"))
            .accessibilityHint("从相册选择一张图片作为菜品照片")
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            // 左下角：AI 识别按钮，仅有图片时显示
            if viewModel.imageData != nil {
                Button {
                    Task { await viewModel.analyzeImage(subscriptionStore: subscriptionStore) }
                } label: {
                    HStack(spacing: 6) {
                        if isRecognizing {
                            Image(systemName: "sparkles")
                            Text("整理中…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("AI 整理文字")
                        }
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                }
                .disabled(isRecognizing)
                .padding(12)
                .accessibilityLabel("AI 整理文字")
                .accessibilityHint("根据照片整理标题、记录内容和可用信息")
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            loadPhoto(from: newItem)
        }
    }

    @ViewBuilder
    private var stickerEffectPicker: some View {
        if viewModel.cutoutImageData != nil {
            HStack(spacing: 12) {
                Label("贴纸效果", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.bodyText)

                Picker("贴纸效果", selection: $stickerEffectStyleRawValue) {
                    ForEach(StickerEffectStyle.displayOrder) { style in
                        Text(style.title)
                            .tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// Hero 图片内容：有抠图时展示贴纸效果，否则展示普通满屏图片
    @ViewBuilder
    private var heroImageContent: some View {
        if let cutoutData = viewModel.cutoutImageData,
           let cutoutUI = UIImage(data: cutoutData) {
            // 有抠图：贴纸效果 + 暖色背景
            ZStack {
                AppTheme.background
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                StickerImageView(
                    cutoutImage: cutoutUI,
                    outlineImage: currentOutlineImage,
                    effectStyle: stickerEffectStyle,
                    maxWidth: UIScreen.main.bounds.width * 0.75,
                    maxHeight: 240
                )
                .padding(.vertical, 20)
            }
        } else if let data = viewModel.imageData, let uiImage = UIImage(data: data) {
            // 无抠图：普通满屏图
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
        } else {
            Rectangle()
                .fill(AppTheme.placeholder)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "camera")
                            .font(.largeTitle)
                        Text("暂无照片")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AppTheme.bodyText.opacity(0.5))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("暂无照片，请点击下方选择照片")
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var aiUnavailableNotice: some View {
        if currentAIUnavailableMessage != nil {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 整理暂不可用")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.titleText)
                    Text("可以继续手动填写记录，照片和保存功能不受影响。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText.opacity(0.65))
                }
                Spacer(minLength: 0)
                if scanResultContainer?.shouldShowSubscriptionPrompt == true {
                    Button("去订阅") {
                        showSubscription = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(12)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var formContent: some View {
        VStack(spacing: 16) {
            nameSection
            dateSection
            if isRecognizing {
                generationLoadingSection
            } else {
                scrapbookDescriptionSection
            }
            if !isRecognizing && viewModel.shouldShowRecipeDetails {
                ingredientsSection
                stepsSection
            }
        }
        .padding(16)
    }

    private var nameTitle: String {
        "标题"
    }

    private var namePlaceholder: String {
        "给这张照片起个标题（可选）"
    }

    private var descriptionTitle: String {
        "记录内容"
    }

    private var descriptionIcon: String {
        "text.append"
    }

    private var ingredientsTitle: String {
        "食材"
    }

    private var stepsTitle: String {
        "步骤"
    }

    private var emptyIngredientsMessage: String {
        "暂无食材，可手动添加或使用 AI 整理"
    }

    private var emptyStepsMessage: String {
        "暂无步骤，可手动添加或使用 AI 整理"
    }

    private var generationLoadingSection: some View {
        AIGenerationLoadingView(
            statusText: "我在帮你整理这张照片",
            compact: true
        )
    }

    /// AI 描写存入备注，可直接作为记录文案继续编辑。
    @ViewBuilder
    private var scrapbookDescriptionSection: some View {
        if viewModel.shouldShowScrapbookDescription {
            VStack(alignment: .leading, spacing: 6) {
                Label(descriptionTitle, systemImage: descriptionIcon)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                descriptionVariantPicker
                TextEditor(text: $viewModel.notes)
                    .font(.body)
                    .foregroundStyle(AppTheme.titleText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 125)
                    .padding(8)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(descriptionTitle)
                    .accessibilityHint("AI 根据画面整理的文字，可自行修改")
            }
        }
    }

    @ViewBuilder
    private var descriptionVariantPicker: some View {
        if !viewModel.descriptionVariants.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.descriptionVariants) { variant in
                        DescriptionVariantOptionCard(
                            variant: variant,
                            isSelected: variant.id == viewModel.selectedDescriptionVariant?.id
                        ) {
                            viewModel.selectDescriptionVariant(variant)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// 菜名（可选）
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(nameTitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
            TextField(namePlaceholder, text: $viewModel.name)
                .font(.title3)
                .padding(12)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(nameTitle)
                .accessibilityHint("可选，不填将使用默认名称")
        }
    }

    /// 日期
    private var dateSection: some View {
        HStack {
            Text("日期")
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
            Spacer()
            DatePicker(
                "",
                selection: $viewModel.date,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 原材料列表
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ingredientsTitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Button {
                    openListEditor(.ingredients)
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.bodyText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑\(ingredientsTitle)")
            }

            if viewModel.ingredients.isEmpty {
                Text(emptyIngredientsMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.bodyText.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.ingredients.indices, id: \.self) { index in
                        Text(viewModel.ingredients[index])
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.titleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    /// 做法步骤列表
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stepsTitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Button {
                    openListEditor(.steps)
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.bodyText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑\(stepsTitle)")
            }

            if viewModel.steps.isEmpty {
                Text(emptyStepsMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.bodyText.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.bodyText.opacity(0.5))
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 4)
                            Text(viewModel.steps[index])
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.titleText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func openListEditor(_ editor: RecipeListEditor) {
        listEditorDraft = editor == .ingredients
            ? viewModel.ingredients.joined(separator: "\n")
            : viewModel.steps.joined(separator: "\n")
        listEditor = editor
    }

    private func listEditorSheet(for editor: RecipeListEditor) -> some View {
        NavigationStack {
            TextEditor(text: $listEditorDraft)
                .font(.body)
                .foregroundStyle(AppTheme.titleText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(AppTheme.background)
                .navigationTitle(AppLocalization.text(editor.title))
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    Text("每行填写一项，删除整行即可移除。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.cardBackground)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            listEditor = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            let items = listEditorDraft
                                .components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }

                            if editor == .ingredients {
                                viewModel.ingredients = items
                            } else {
                                viewModel.steps = items
                            }
                            listEditor = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }

    private var recipeUpdateDialog: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.bodyText)

                VStack(spacing: 6) {
                    Text("正在更新记录")
                        .font(.headline)
                        .foregroundStyle(AppTheme.bodyText)
                    Text("正在根据新的标题整理内容…")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppTheme.bodyText.opacity(0.7))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: 280)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }

    // MARK: - Actions

    private func saveButtonTapped() {
        guard viewModel.isValid,
              !viewModel.isSaving,
              !isRecognizing,
              !didCompleteSave else {
            return
        }

        viewModel.isSaving = true
        isShowingRecipeUpdateDialog = isEditing && viewModel.shouldRefreshDetailsForRenamedRecipe
        Task { await save() }
    }

    private func save() async {
        viewModel.aiError = nil
        defer {
            viewModel.isSaving = false
            isShowingRecipeUpdateDialog = false
        }

        if let recipeToEdit {
            do {
                try await viewModel.refreshRecipeDetailsForRenamedRecipeIfNeeded(subscriptionStore: subscriptionStore)
            } catch {
                print("[Recipe] Skipped AI detail refresh before saving: \(error.localizedDescription)")
            }
            viewModel.update(recipeToEdit)
            do {
                try modelContext.save()
            } catch {
                viewModel.aiError = AppLocalization.format("保存失败：%@", error.localizedDescription)
                return
            }
        } else {
            do {
                try viewModel.save(in: modelContext)
            } catch {
                viewModel.aiError = AppLocalization.format("保存失败：%@", error.localizedDescription)
                return
            }
        }
        didCompleteSave = true
        dismiss()
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let transfer = try? await item.loadTransferable(type: AddRecipeImageTransfer.self) {
                viewModel.imageData = transfer.data
                // 换图后清除旧抠图（新图没有抠图结果）
                viewModel.cutoutImageData = nil
                scanResultContainer?.reset()
            }
        }
    }

    private func initializeFormIfNeeded() {
        guard !didInitializeForm else { return }
        didInitializeForm = true

        if let recipeToEdit {
            viewModel.populate(from: recipeToEdit)
            return
        }

        guard let initialImageData else { return }
        viewModel.imageData = initialImageData

        if scanResultContainer != nil {
            applyScanImagesIfNeeded()
            applyScanSuggestionIfNeeded()
        } else {
            viewModel.cutoutImageData = initialCutoutImage?.pngData()
            if let suggestion = initialSuggestion {
                viewModel.applyAISuggestion(suggestion)
            }
        }
    }

    private func applyScanImagesIfNeeded() {
        guard let scanResultContainer,
              scanResultContainer.imageVersion != appliedImageVersion else {
            return
        }
        appliedImageVersion = scanResultContainer.imageVersion
        if let cutoutImage = scanResultContainer.cutoutImage,
           let pngData = cutoutImage.pngData() {
            viewModel.cutoutImageData = pngData
        }
    }

    private func applyScanSuggestionIfNeeded() {
        guard let scanResultContainer,
              scanResultContainer.suggestionVersion != appliedSuggestionVersion,
              let suggestion = scanResultContainer.suggestion else {
            return
        }
        appliedSuggestionVersion = scanResultContainer.suggestionVersion
        viewModel.applyAISuggestion(suggestion)
    }
}
