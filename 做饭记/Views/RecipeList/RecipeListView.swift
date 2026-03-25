import SwiftUI
import SwiftData

// MARK: - Recipe List View (Feed)

/// 菜谱页：支持缩略图网格 / 列表两种视图，按标签筛选；设置入口在右上角。
struct RecipeListView: View {

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

    // MARK: - Data

    @Query(sort: \Recipe.date, order: .reverse)
    private var allRecipes: [Recipe]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                if filteredRecipes.isEmpty {
                    emptyView
                        .padding(.top, 80)
                } else {
                    Group {
                        if viewMode == .list {
                            listContent
                        } else {
                            gridContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("What's Cooking")
            .toolbar {
                // 视图切换：单独在左侧，一眼可见
                ToolbarItem(placement: .topBarLeading) {
                    viewModeButton
                }
                // 筛选 + 设置：折叠进右侧 ··· 菜单
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
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

    /// 右上角 ··· 菜单：包含「筛选」和「设置」
    private var moreMenu: some View {
        Menu {
            Button {
                showFilterSheet = true
            } label: {
                Label(
                    hasActiveFilters ? "筛选（已开启）" : "筛选",
                    systemImage: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }

            Button {
                onOpenSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(AppTheme.bodyText)
        }
        .accessibilityLabel("更多操作")
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
