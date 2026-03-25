import SwiftUI

// MARK: - Recipe Detail View

/// 单道菜谱完整信息展示，支持进入编辑和删除。
struct RecipeDetailView: View {

    let recipe: Recipe

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroImage
                infoSection
                tagsSection
                ingredientsSection
                stepsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background)
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
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

    /// 顶部大图，按原始比例完整显示，不裁剪。
    @ViewBuilder
    private var heroImage: some View {
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.placeholder)
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
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

    /// 菜名 + 日期
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.titleText)

            Text(recipe.date, format: .dateTime.year().month().day().weekday())
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
        }
    }

    /// 标签
    @ViewBuilder
    private var tagsSection: some View {
        let hasTags = recipe.difficulty != nil || recipe.cuisine != nil || recipe.cookingTime != nil
        if hasTags {
            HStack(spacing: 8) {
                if let d = recipe.difficulty {
                    TagChipView.difficulty(d)
                }
                if let c = recipe.cuisine {
                    TagChipView.cuisine(c)
                }
                if let t = recipe.cookingTime {
                    TagChipView.cookingTime(t)
                }
            }
        }
    }

    /// 原材料列表
    @ViewBuilder
    private var ingredientsSection: some View {
        if !recipe.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("原材料")
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipe.ingredients, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(AppTheme.bodyText.opacity(0.4))
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(item)
                                .font(.body)
                                .foregroundStyle(AppTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// 做法步骤
    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("做法")
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recipe.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(AppTheme.bodyText.opacity(0.5))
                                .clipShape(Circle())
                                .padding(.top, 1)
                            Text(recipe.steps[index])
                                .font(.body)
                                .foregroundStyle(AppTheme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteRecipe() {
        modelContext.delete(recipe)
        dismiss()
    }
}
