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
    /// 抠图结果（透明背景）
    var initialCutoutImage: UIImage?
    /// 贴纸描边轮廓图
    var initialOutlineImage: UIImage?

    @State private var viewModel = AddRecipeViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var tagsExpanded = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { recipeToEdit != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    photoHeroSection
                    formContent
                }
            }
            .background(AppTheme.background)
            .navigationTitle(isEditing ? "编辑菜谱" : "新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.isValid)
                        .accessibilityHint("保存菜谱，需先添加照片")
                }
            }
            .alert("识别失败", isPresented: Binding(
                get: { viewModel.aiError != nil },
                set: { if !$0 { viewModel.aiError = nil } }
            )) {
                Button("好") { viewModel.aiError = nil }
            } message: {
                Text(viewModel.aiError ?? "")
            }
            .onAppear {
                if let recipeToEdit {
                    viewModel.populate(from: recipeToEdit)
                } else if let initialImageData {
                    viewModel.imageData = initialImageData
                    viewModel.cutoutImageData = initialCutoutImage?.pngData()
                    print("[AddRecipeView] onAppear: initialSuggestion=\(initialSuggestion?.name ?? "nil"), ingredients=\(initialSuggestion?.ingredients.count ?? -1)")
                    if let suggestion = initialSuggestion {
                        viewModel.applyAISuggestion(suggestion)
                        tagsExpanded = true
                        print("[AddRecipeView] Applied suggestion: name=\(viewModel.name), ingredients=\(viewModel.ingredients.count)")
                    }
                }
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
                    hasPhoto ? "更换" : "选择照片",
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
            .accessibilityLabel(hasPhoto ? "更换照片" : "选择照片")
            .accessibilityHint("从相册选择一张图片作为菜品照片")
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            // 左下角：AI 识别按钮，仅有图片时显示
            if viewModel.imageData != nil {
                Button {
                    Task { await viewModel.analyzeImage() }
                    tagsExpanded = true
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isAILoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("识别中…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("AI 识别填写")
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
                .disabled(viewModel.isAILoading)
                .padding(12)
                .accessibilityLabel("AI 识别填写")
                .accessibilityHint("自动识别菜名、菜系、难度、烹饪时间、原材料和做法")
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            loadPhoto(from: newItem)
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
                    outlineImage: initialOutlineImage,
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

    private var formContent: some View {
        VStack(spacing: 16) {
            nameSection
            dateSection
            ingredientsSection
            stepsSection
            tagsSection
        }
        .padding(16)
    }

    /// 菜名（可选）
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("菜名")
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
            TextField("给这道菜起个名字（可选）", text: $viewModel.name)
                .font(.title3)
                .padding(12)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("菜名")
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

    /// 原材料列表（可增删）
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("原材料")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Button {
                    viewModel.ingredients.append("")
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(AppTheme.bodyText)
                }
                .accessibilityLabel("添加原材料")
            }

            if viewModel.ingredients.isEmpty {
                Text("暂无原材料，可手动添加或使用 AI 识别")
                    .font(.caption)
                    .foregroundStyle(AppTheme.bodyText.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.ingredients.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("食材名称和用量", text: $viewModel.ingredients[index])
                                .font(.subheadline)
                            Button {
                                viewModel.ingredients.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .accessibilityLabel("删除此原材料")
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

    /// 做法步骤列表（可增删）
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("做法")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Button {
                    viewModel.steps.append("")
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(AppTheme.bodyText)
                }
                .accessibilityLabel("添加步骤")
            }

            if viewModel.steps.isEmpty {
                Text("暂无做法步骤，可手动添加或使用 AI 识别")
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
                            TextField("步骤描述", text: $viewModel.steps[index], axis: .vertical)
                                .font(.subheadline)
                                .lineLimit(2...6)
                            Button {
                                viewModel.steps.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .accessibilityLabel("删除此步骤")
                            .padding(.top, 2)
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

    /// 标签（可选，默认折叠）
    private var tagsSection: some View {
        DisclosureGroup(isExpanded: $tagsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // 难度
                VStack(alignment: .leading, spacing: 6) {
                    Text("难度")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                    HStack(spacing: 8) {
                        ForEach(Difficulty.allCases) { d in
                            TagChipView.difficulty(d, isSelected: viewModel.difficulty == d) {
                                viewModel.difficulty = viewModel.difficulty == d ? nil : d
                            }
                        }
                    }
                }

                // 菜式
                VStack(alignment: .leading, spacing: 6) {
                    Text("菜式")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Cuisine.allCases) { c in
                                    TagChipView.cuisine(c, isSelected: viewModel.cuisine == c) {
                                        viewModel.cuisine = viewModel.cuisine == c ? nil : c
                                    }
                                    .id(c)
                                }
                            }
                        }
                        .onChange(of: viewModel.cuisine) { _, newCuisine in
                            if let cuisine = newCuisine {
                                // 延迟等待 DisclosureGroup 展开动画完成后再滚动
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        proxy.scrollTo(cuisine, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }

                // 耗时
                VStack(alignment: .leading, spacing: 6) {
                    Text("耗时")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                    HStack(spacing: 8) {
                        ForEach(CookingTime.allCases) { t in
                            TagChipView.cookingTime(t, isSelected: viewModel.cookingTime == t) {
                                viewModel.cookingTime = viewModel.cookingTime == t ? nil : t
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("标签（可选）")
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func save() {
        if let recipeToEdit {
            viewModel.update(recipeToEdit)
        } else {
            viewModel.save(in: modelContext)
        }
        dismiss()
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let transfer = try? await item.loadTransferable(type: AddRecipeImageTransfer.self) {
                viewModel.imageData = transfer.data
                // 换图后清除旧抠图（新图没有抠图结果）
                viewModel.cutoutImageData = nil
            }
        }
    }
}
