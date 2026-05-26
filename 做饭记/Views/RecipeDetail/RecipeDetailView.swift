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
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                ingredientsSection
                stepsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
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

    /// 顶部紧凑信息区：小图只作为识别入口，详情阅读重点留给材料和做法。
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            dishThumbnail
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                infoSection
                tagsSection
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        }
    }

    /// 菜品小方图，统一比例避免详情页首屏被奇怪的原图比例撑开。
    @ViewBuilder
    private var dishThumbnail: some View {
        if let cutoutData = recipe.cutoutImageData, let cutoutImage = UIImage(data: cutoutData) {
            Image(uiImage: cutoutImage)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        } else if let uiImage = dishDisplayImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.placeholder)
                .frame(width: 104, height: 104)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.title2)
                        Text("暂无照片")
                            .font(.caption)
                    }
                    .foregroundStyle(AppTheme.bodyText.opacity(0.5))
                }
        }
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
            Text(recipe.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2)

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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    tagChips
                }

                VStack(alignment: .leading, spacing: 6) {
                    tagChips
                }
            }
        }
    }

    @ViewBuilder
    private var tagChips: some View {
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

    /// 原材料列表
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原材料")
                .font(.headline)
                .foregroundStyle(AppTheme.titleText)

            if recipe.ingredients.isEmpty {
                emptySectionButton(icon: "carrot", message: "还没有填写原材料")
            } else {
                LazyVGrid(columns: ingredientColumns, alignment: .leading, spacing: 6) {
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
                .padding(10)
                .background(AppTheme.cardBackground)
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
                .font(.headline)
                .foregroundStyle(AppTheme.titleText)

            if recipe.steps.isEmpty {
                emptySectionButton(icon: "list.bullet.clipboard", message: "还没有填写做法")
            } else {
                VStack(alignment: .leading, spacing: 6) {
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func emptySectionButton(icon: String, message: String) -> some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(message)
                    .font(.subheadline)
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .foregroundStyle(AppTheme.bodyText.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(AppTheme.cardBackground)
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
