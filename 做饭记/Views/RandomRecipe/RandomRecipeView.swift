import SwiftUI

// MARK: - Random Recipe View

/// 随机推荐一道菜谱的展示 sheet。
/// 由 ContentView 持有菜谱列表并负责随机抽取，
/// recipe 用 Binding 传入，以便"再随一道"时原地刷新内容无需关闭 sheet。
struct RandomRecipeView: View {

    @Binding var recipe: Recipe
    var onShuffle: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink(value: recipe) {
                        VStack(alignment: .leading, spacing: 20) {
                            heroImage
                            infoSection
                        }
                    }
                    .buttonStyle(.plain)

                    tagsSection
                    notesSection
                    Spacer(minLength: 24)
                    shuffleButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(AppTheme.background)
            .navigationTitle("今天吃什么？")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var heroImage: some View {
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.placeholder)
                .frame(height: 160)
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

    @ViewBuilder
    private var tagsSection: some View {
        let hasTags = recipe.difficulty != nil || recipe.cuisine != nil || recipe.cookingTime != nil
        if hasTags {
            HStack(spacing: 8) {
                if let d = recipe.difficulty { TagChipView.difficulty(d) }
                if let c = recipe.cuisine    { TagChipView.cuisine(c) }
                if let t = recipe.cookingTime { TagChipView.cookingTime(t) }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !recipe.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)

                Text(recipe.notes)
                    .font(.body)
                    .foregroundStyle(AppTheme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var shuffleButton: some View {
        Button {
            onShuffle()
        } label: {
            Label("再随一道", systemImage: "shuffle")
                .font(.body)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
