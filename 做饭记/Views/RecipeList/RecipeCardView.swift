import SwiftUI

// MARK: - Recipe Card View (Feed Style)

/// Feed 流卡片：上图下文布局。
/// 全宽大图 + 菜名（如有）+ 日期 + 标签。
struct RecipeCardView: View {

    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            infoSection
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(recipe.name.isEmpty ? "未命名" : recipe.name)，\(recipe.date.formatted(.dateTime.year().month().day()))")
        .accessibilityHint("双击打开菜谱详情")
    }

    // MARK: - Subviews

    /// 顶部大图
    /// 横图（宽≥高）完整显示在 4:3 框内；竖图顶部对齐裁剪到 4:3，保留食物主体。
    private var imageSection: some View {
        GeometryReader { geo in
            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                let isPortrait = uiImage.size.height > uiImage.size.width
                if isPortrait {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width * 3 / 4)
                        .clipped()
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width)
                }
            } else {
                Rectangle()
                    .fill(AppTheme.placeholder)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title)
                            .foregroundStyle(AppTheme.bodyText.opacity(0.3))
                    }
            }
        }
        .aspectRatio(4/3, contentMode: .fit)
    }

    /// 底部信息：菜名 + 日期 + 标签
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 菜名（可能是自动生成的默认名）
            if !recipe.name.isEmpty {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2)
            }

            // 日期
            Text(recipe.date, format: .dateTime.year().month().day())
                .font(.caption)
                .foregroundStyle(AppTheme.bodyText)

            // 标签行
            tagsView
        }
        .padding(12)
    }

    /// 标签
    @ViewBuilder
    private var tagsView: some View {
        let tags = collectTags()
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.text) { tag in
                    TagChipView(text: tag.text, color: tag.color)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct TagInfo: Hashable {
        let text: String
        let color: Color

        func hash(into hasher: inout Hasher) {
            hasher.combine(text)
        }

        static func == (lhs: TagInfo, rhs: TagInfo) -> Bool {
            lhs.text == rhs.text
        }
    }

    private func collectTags() -> [TagInfo] {
        var result: [TagInfo] = []
        if let d = recipe.difficulty {
            result.append(TagInfo(text: d.rawValue, color: AppTheme.tagDifficulty))
        }
        if let c = recipe.cuisine {
            result.append(TagInfo(text: c.rawValue, color: AppTheme.tagCuisine))
        }
        if let t = recipe.cookingTime {
            result.append(TagInfo(text: t.rawValue, color: AppTheme.tagCookingTime))
        }
        return result
    }
}

// MARK: - Recipe Thumbnail View (Grid Cell)

/// 缩略图网格用的小卡片：小图 + 菜名/日期，一屏可展示更多菜谱。
struct RecipeThumbnailView: View {

    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailImage
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name.isEmpty ? "未命名" : recipe.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2)
                Text(recipe.date, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(AppTheme.bodyText)
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name.isEmpty ? "未命名" : recipe.name)，\(recipe.date.formatted(.dateTime.month().day()))")
    }

    /// 缩略图
    /// 横图完整显示在 4:3 框内；竖图顶部对齐裁剪到 4:3。
    private var thumbnailImage: some View {
        GeometryReader { geo in
            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                let isPortrait = uiImage.size.height > uiImage.size.width
                if isPortrait {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width * 3 / 4)
                        .clipped()
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width)
                }
            } else {
                Rectangle()
                    .fill(AppTheme.placeholder)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title3)
                            .foregroundStyle(AppTheme.bodyText.opacity(0.3))
                    }
            }
        }
        .aspectRatio(4/3, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10))
    }
}
