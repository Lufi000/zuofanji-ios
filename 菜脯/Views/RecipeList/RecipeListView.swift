import SwiftUI
import SwiftData

// MARK: - Recipe List View (Feed)

/// 菜谱页：支持缩略图网格 / 列表两种视图，按标签筛选；筛选和设置为独立入口。
struct RecipeListView: View {

    /// 外部更新该值时，菜谱页回到根页面。
    var resetToken: Int = 0
    /// 点击右上角设置时回调
    var onOpenSettings: () -> Void
    /// 空状态时「记一笔」等添加入口（与底部 + 一致，弹出相机/上传选择）
    var onAddRecipe: () -> Void

    // MARK: - View Mode

    enum ViewMode: String, CaseIterable {
        case grid = "缩略图"
        case magazine = "拼贴"
        case list = "列表"

        var iconName: String {
            switch self {
            case .grid:
                return "square.grid.2x2"
            case .magazine:
                return "rectangle.grid.2x2"
            case .list:
                return "list.bullet"
            }
        }
    }
    @State private var viewMode: ViewMode = .grid

    // MARK: - Filter State

    @State private var filterDifficulty: Difficulty?
    @State private var filterCuisine: Cuisine?
    @State private var filterCookingTime: CookingTime?
    @State private var showFilterSheet = false
    @State private var navigationPath = NavigationPath()
    @AppStorage(AppearancePreference.storageKey) private var appearancePreferenceRawValue = AppearancePreference.defaultRawValue

    // MARK: - Data

    @Query(sort: \Recipe.date, order: .reverse)
    private var allRecipes: [Recipe]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 16) {
                    filterStatusBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(1)

                    if filteredRecipes.isEmpty {
                        emptyView
                            .padding(.top, hasActiveFilters ? 24 : 32)
                    } else {
                        Group {
                            if viewMode == .list {
                                listContent
                            } else if viewMode == .magazine {
                                magazineContent
                            } else {
                                gridContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .background {
                pageBackground
            }
            .navigationTitle("菜脯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(toolbarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // 视图切换：单独在左侧，一眼可见
                ToolbarItem(placement: .topBarLeading) {
                    viewModeButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }
            .onChange(of: resetToken) { _, _ in
                navigationPath.removeLast(navigationPath.count)
            }
            .onChange(of: viewMode) { _, _ in
                prewarmCutoutTrimCacheIfNeeded()
            }
            .onChange(of: appearancePreferenceRawValue) { _, _ in
                prewarmCutoutTrimCacheIfNeeded()
            }
            .task {
                prewarmCutoutTrimCacheIfNeeded()
            }
        }
    }

    private var listContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeCardView(recipe: recipe, appearancePreference: appearancePreference)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        modelContext.delete(recipe)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var gridContent: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(filteredRecipes.enumerated()), id: \.element.id) { index, recipe in
                recipeThumbnailLink(
                    recipe: recipe,
                    index: index,
                    imageAspectRatio: 4 / 3,
                    usesScrapbookJitter: true,
                    usesFloatingCaption: false
                )
            }
        }
    }

    private var magazineContent: some View {
        LazyVStack(spacing: 14) {
            ForEach(Array(stride(from: 0, to: filteredRecipes.count, by: 6)), id: \.self) { startIndex in
                magazineGroup(startIndex: startIndex)
            }
        }
    }

    private func magazineGroup(startIndex: Int) -> some View {
        VStack(spacing: 12) {
            magazineRecipeLinkIfAvailable(at: startIndex, imageAspectRatio: 16 / 10)

            if startIndex + 1 < filteredRecipes.count {
                HStack(alignment: .top, spacing: 12) {
                    magazineRecipeLinkIfAvailable(at: startIndex + 1, imageAspectRatio: 1)
                    magazineRecipeLinkIfAvailable(at: startIndex + 2, imageAspectRatio: 4 / 3)
                }
            }

            if startIndex + 3 < filteredRecipes.count {
                HStack(alignment: .top, spacing: 12) {
                    magazineRecipeLinkIfAvailable(at: startIndex + 3, imageAspectRatio: 3 / 4)
                    VStack(spacing: 12) {
                        magazineRecipeLinkIfAvailable(at: startIndex + 4, imageAspectRatio: 1)
                        magazineRecipeLinkIfAvailable(at: startIndex + 5, imageAspectRatio: 16 / 10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func magazineRecipeLinkIfAvailable(at index: Int, imageAspectRatio: CGFloat) -> some View {
        if index < filteredRecipes.count {
            recipeThumbnailLink(
                recipe: filteredRecipes[index],
                index: index,
                imageAspectRatio: imageAspectRatio,
                usesScrapbookJitter: false,
                usesFloatingCaption: true
            )
        }
    }

    private func recipeThumbnailLink(
        recipe: Recipe,
        index: Int,
        imageAspectRatio: CGFloat,
        usesScrapbookJitter: Bool,
        usesFloatingCaption: Bool
    ) -> some View {
        NavigationLink(value: recipe) {
            RecipeThumbnailView(
                recipe: recipe,
                appearancePreference: appearancePreference,
                collageIndex: index,
                imageAspectRatio: imageAspectRatio,
                usesScrapbookJitter: usesScrapbookJitter,
                usesFloatingCaption: usesFloatingCaption
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                modelContext.delete(recipe)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Filtered Data

    private var filteredRecipes: [Recipe] {
        allRecipes.filter { recipe in
            if let d = filterDifficulty, recipe.difficultyRawValue != d.rawValue {
                return false
            }
            if let c = filterCuisine, recipe.cuisineRawValue != c.rawValue {
                return false
            }
            if let t = filterCookingTime, recipe.cookingTimeRawValue != t.rawValue {
                return false
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        filterDifficulty != nil || filterCuisine != nil || filterCookingTime != nil
    }

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRawValue) ?? .defaultPreference
    }

    private var toolbarBackground: Color {
        appearancePreference == .scrapbook ? AppTheme.notebookPaper : AppTheme.background
    }

    @ViewBuilder
    private var pageBackground: some View {
        if appearancePreference == .scrapbook {
            NotebookPaperBackground()
                .ignoresSafeArea()
        } else {
            AppTheme.background
                .ignoresSafeArea()
        }
    }

    private var activeFilterLabels: [String] {
        [
            filterDifficulty.map { AppLocalization.format("难度 %@", $0.localizedName) },
            filterCuisine.map { AppLocalization.format("菜式 %@", $0.localizedName) },
            filterCookingTime.map { AppLocalization.format("耗时 %@", $0.localizedName) }
        ].compactMap { $0 }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyView: some View {
        if hasActiveFilters {
            EmptyStateView.noFilterResults(onClear: clearFilters)
        } else {
            EmptyStateView.noRecipes(onAdd: onAddRecipe)
        }
    }

    private var viewModeButton: some View {
        Menu {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.iconName)
                }
            }
        } label: {
            Image(systemName: viewMode.iconName)
                .foregroundStyle(AppTheme.bodyText)
        }
        .accessibilityLabel(AppLocalization.format("当前视图：%@", viewMode.rawValue))
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(AppTheme.bodyText)
        }
        .accessibilityLabel("设置")
    }

    private var filterStatusBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if hasActiveFilters {
                        ForEach(activeFilterLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(AppTheme.titleText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.accent.opacity(0.14), in: Capsule())
                        }
                    } else {
                        Text("全部菜谱")
                            .font(.caption)
                            .foregroundStyle(AppTheme.bodyText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.placeholder.opacity(0.78), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                showFilterSheet = true
            }
            .accessibilityLabel(
                hasActiveFilters
                    ? AppLocalization.format("当前筛选：%@", activeFilterLabels.joined(separator: AppLocalization.text("，")))
                    : AppLocalization.text("当前筛选：全部菜谱")
            )
            .accessibilityHint("轻点调整筛选条件")

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.bodyText)
                }
                .accessibilityLabel("清除筛选")
            }
        }
    }

    private func prewarmCutoutTrimCacheIfNeeded() {
        guard appearancePreference == .scrapbook, viewMode != .list else { return }
        CutoutImageTrimCache.shared.prewarm(
            filteredRecipes.compactMap(\.cutoutImageData),
            limit: viewMode == .magazine ? 12 : 18,
            maxPixelDimension: 900
        )
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("难度") {
                    HStack(spacing: 8) {
                        ForEach(Difficulty.allCases) { d in
                            TagChipView.difficulty(d, isSelected: filterDifficulty == d) {
                                filterDifficulty = filterDifficulty == d ? nil : d
                            }
                        }
                    }
                }

                Section("菜式") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Cuisine.allCases) { c in
                                TagChipView.cuisine(c, isSelected: filterCuisine == c) {
                                    filterCuisine = filterCuisine == c ? nil : c
                                }
                            }
                        }
                    }
                }

                Section("耗时") {
                    HStack(spacing: 8) {
                        ForEach(CookingTime.allCases) { t in
                            TagChipView.cookingTime(t, isSelected: filterCookingTime == t) {
                                filterCookingTime = filterCookingTime == t ? nil : t
                            }
                        }
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button("清除所有筛选", role: .destructive) {
                            clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showFilterSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func clearFilters() {
        filterDifficulty = nil
        filterCuisine = nil
        filterCookingTime = nil
    }
}
