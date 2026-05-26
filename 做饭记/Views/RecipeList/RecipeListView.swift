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
        case list = "列表"
    }
    @State private var viewMode: ViewMode = .list

    // MARK: - Filter State

    @State private var filterDifficulty: Difficulty?
    @State private var filterCuisine: Cuisine?
    @State private var filterCookingTime: CookingTime?
    @State private var showFilterSheet = false
    @State private var navigationPath = NavigationPath()

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
            .background(AppTheme.background)
            .navigationTitle("What's Cooking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
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
        }
    }

    private var listContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeCardView(recipe: recipe)
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
            ForEach(filteredRecipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeThumbnailView(recipe: recipe)
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

    private var activeFilterLabels: [String] {
        [
            filterDifficulty.map { "难度 \($0.rawValue)" },
            filterCuisine.map { "菜式 \($0.rawValue)" },
            filterCookingTime.map { "耗时 \($0.rawValue)" }
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
        Button {
            viewMode = viewMode == .list ? .grid : .list
        } label: {
            Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                .foregroundStyle(AppTheme.bodyText)
        }
        .accessibilityLabel(viewMode == .list ? "切换为缩略图" : "切换为列表")
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
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(AppTheme.accent)

                Text("当前筛选")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.titleText)

                if hasActiveFilters {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(activeFilterLabels, id: \.self) { label in
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.titleText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accent.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                } else {
                    Text("全部菜谱")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.placeholder, in: Capsule())

                    Spacer(minLength: 0)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.bodyText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                showFilterSheet = true
            }
            .accessibilityLabel(hasActiveFilters ? "当前筛选：\(activeFilterLabels.joined(separator: "，"))" : "当前筛选：全部菜谱")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 0.5)
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
