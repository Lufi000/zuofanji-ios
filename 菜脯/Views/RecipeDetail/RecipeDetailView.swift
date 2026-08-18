import SwiftUI

// MARK: - Recipe Detail View

/// 单道菜谱完整信息展示，支持进入编辑和删除。
struct RecipeDetailView: View {

    let recipe: Recipe

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @AppStorage(AppearancePreference.storageKey) private var appearancePreferenceRawValue = AppearancePreference.defaultRawValue
    @AppStorage(StickerEffectStyle.storageKey) private var stickerEffectStyleRawValue = StickerEffectStyle.defaultRawValue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                detailContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .contentMargins(.top, 16, for: .scrollContent)
        .background {
            pageBackground
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(toolbarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddRecipeView(recipeToEdit: recipe)
        }
        .confirmationDialog("确定要删除这道菜谱吗？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deleteRecipe()
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Subviews

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRawValue) ?? .defaultPreference
    }

    private var isScrapbook: Bool {
        appearancePreference == .scrapbook
    }

    private var stickerEffectStyle: StickerEffectStyle {
        StickerEffectStyle(rawValue: stickerEffectStyleRawValue) ?? .defaultStyle
    }

    private var toolbarBackground: Color {
        isScrapbook ? AppTheme.notebookPaper : AppTheme.background
    }

    @ViewBuilder
    private var pageBackground: some View {
        if isScrapbook {
            NotebookPaperBackground()
                .ignoresSafeArea()
        } else {
            AppTheme.background
                .ignoresSafeArea()
        }
    }

    /// 顶部信息区：大图在上，菜名和日期在下，让详情页更突出内容本身。
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            dishHeroImage
            infoSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 菜品主图，统一比例避免详情页首屏被奇怪的原图比例撑开。
    @ViewBuilder
    private var dishHeroImage: some View {
        if let cutoutData = recipe.cutoutImageData, let cutoutImage = UIImage(data: cutoutData) {
            heroImageContainer {
                TrimmedCutoutImage(
                    data: cutoutData,
                    fallbackImage: cutoutImage,
                    padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                    shadowOpacity: 0.12,
                    shadowRadius: 10,
                    shadowY: 5,
                    effectStyle: stickerEffectStyle
                )
            }
        } else if let uiImage = dishDisplayImage {
            heroImageContainer {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            heroImageContainer {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                    Text("暂无照片")
                        .font(.subheadline)
                }
                .foregroundStyle(AppTheme.bodyText.opacity(0.5))
            }
        }
    }

    private func heroImageContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ZStack {
            if !isScrapbook {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dishDisplayImage: UIImage? {
        if let cutoutData = recipe.cutoutImageData, let cutoutImage = UIImage(data: cutoutData) {
            return cutoutImage
        }
        if let data = recipe.imageData, let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    /// 菜名 + 日期
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.localizedContent.name)
                .font(isScrapbook ? .scrapbook(size: 32, relativeTo: .title) : .title)
                .fontWeight(isScrapbook ? .regular : .bold)
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2)

            Text(recipe.date, format: .dateTime.year().month().day().weekday())
                .font(isScrapbook ? .scrapbook(size: 17, relativeTo: .subheadline) : .subheadline)
                .foregroundStyle(AppTheme.bodyText)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch recipe.recordKind {
        case .foodRecipe:
            ingredientsSection
            stepsSection
            if !recipe.localizedContent.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notesSection(title: "备注", icon: "note.text")
            }
        case .babyMeal:
            notesSection(title: "宝宝记录", icon: "heart.text.square")
            ingredientsSection
            stepsSection
        case .babyDaily:
            notesSection(title: "宝宝小记", icon: "heart.text.square")
        case .scrapbook:
            notesSection(title: "手帐描述", icon: "sparkles")
        }
    }

    /// 原材料列表
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.recordKind == .babyMeal ? "食材" : "原材料")
                .font(sectionTitleFont)
                .foregroundStyle(AppTheme.titleText)

            if recipe.localizedContent.ingredients.isEmpty {
                emptySectionButton(
                    icon: "carrot",
                    message: recipe.recordKind == .babyMeal ? "还没有记录食材" : "还没有填写原材料"
                )
            } else {
                LazyVGrid(columns: ingredientColumns, alignment: .leading, spacing: 6) {
                    ForEach(recipe.localizedContent.ingredients, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(AppTheme.bodyText.opacity(0.4))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(item)
                                .font(bodyFont)
                                .foregroundStyle(AppTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(10)
                .background(sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var ingredientColumns: [GridItem] {
        [
            GridItem(.flexible(), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading)
        ]
    }

    /// 做法步骤
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("做法")
                .font(sectionTitleFont)
                .foregroundStyle(AppTheme.titleText)

            if recipe.localizedContent.steps.isEmpty {
                emptySectionButton(
                    icon: "list.bullet.clipboard",
                    message: recipe.recordKind == .babyMeal ? "还没有记录做法" : "还没有填写做法"
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipe.localizedContent.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(AppTheme.bodyText.opacity(0.5))
                                .clipShape(Circle())
                                .padding(.top, 1)
                            Text(recipe.localizedContent.steps[index])
                                .font(bodyFont)
                                .foregroundStyle(AppTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(sectionBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func notesSection(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(sectionTitleFont)
                .foregroundStyle(AppTheme.titleText)

            let notes = recipe.localizedContent.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if notes.isEmpty {
                emptySectionButton(icon: icon, message: "还没有填写记录")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(noteRows(from: notes), id: \.self) { row in
                        Text(row)
                            .font(bodyFont)
                            .foregroundStyle(AppTheme.bodyText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func noteRows(from notes: String) -> [String] {
        let rows = notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return rows.isEmpty ? [notes] : rows
    }

    private var sectionTitleFont: Font {
        isScrapbook ? .scrapbook(size: 22, relativeTo: .headline) : .headline
    }

    private var bodyFont: Font {
        isScrapbook ? .scrapbook(size: 18, relativeTo: .body) : .body
    }

    private var sectionBackground: Color {
        isScrapbook ? .clear : AppTheme.cardBackground
    }

    private func emptySectionButton(icon: String, message: String) -> some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(LocalizedStringKey(message))
                    .font(isScrapbook ? .scrapbook(size: 16, relativeTo: .subheadline) : .subheadline)
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.bodyText.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(sectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint("双击编辑菜谱")
    }

    // MARK: - Actions

    private func deleteRecipe() {
        modelContext.delete(recipe)
        dismiss()
    }
}
