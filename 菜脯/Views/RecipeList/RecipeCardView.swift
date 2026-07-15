import SwiftUI
import UIKit
import ImageIO

// MARK: - Recipe Card View (Feed Style)

/// Feed 流卡片：上图下文布局。
/// 全宽大图 + 菜名（如有）+ 日期 + 标签。
struct RecipeCardView: View {

    let recipe: Recipe
    let appearancePreference: AppearancePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            infoSection
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .overlay {
            if appearancePreference == .scrapbook {
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .strokeBorder(AppTheme.bodyText.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .shadow(color: .black.opacity(appearancePreference == .scrapbook ? 0.05 : 0.06), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            AppLocalization.format(
                "%@，%@",
                recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name,
                recipe.date.formatted(.dateTime.year().month().day())
            )
        )
        .accessibilityHint("双击打开菜谱详情")
    }

    // MARK: - Subviews

    /// 顶部大图
    /// 横图（宽≥高）完整显示在 4:3 框内；竖图顶部对齐裁剪到 4:3，保留食物主体。
    @ViewBuilder
    private var imageSection: some View {
        if appearancePreference == .scrapbook {
            scrapbookImageSection
        } else {
            classicImageSection
        }
    }

    /// 底部信息：菜名 + 日期 + 标签
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: infoSpacing) {
            // 菜名（可能是自动生成的默认名）
            if !recipe.localizedContent.name.isEmpty {
                Text(recipe.localizedContent.name)
                    .font(titleFont)
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2)
            }

            // 日期
            Text(recipe.date, format: .dateTime.year().month().day())
                .font(dateFont)
                .foregroundStyle(AppTheme.bodyText)

            // 标签行
            tagsView
        }
        .padding(12)
    }

    private var cardBackground: Color {
        appearancePreference == .scrapbook ? .clear : AppTheme.cardBackground
    }

    private var cardCornerRadius: CGFloat {
        appearancePreference == .scrapbook ? 8 : 12
    }

    private var infoSpacing: CGFloat {
        appearancePreference == .scrapbook ? 3 : 8
    }

    private var titleFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 18, weight: .semibold, relativeTo: .headline) : .headline
    }

    private var dateFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 13, weight: .regular, relativeTo: .caption) : .caption
    }

    private var classicImageSection: some View {
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
                placeholderImage(font: .title)
            }
        }
        .aspectRatio(4/3, contentMode: .fit)
    }

    private var scrapbookImageSection: some View {
        Color.clear
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                if let data = recipe.cutoutImageData, let uiImage = UIImage(data: data) {
                    TrimmedCutoutImage(
                        data: data,
                        fallbackImage: uiImage,
                        padding: EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8),
                        shadowOpacity: 0.18,
                        shadowRadius: 8,
                        shadowY: 5,
                        maxPixelDimension: 1400
                    )
                } else if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                } else {
                    placeholderImage(font: .title)
                        .padding(12)
                }
            }
    }

    private func placeholderImage(font: Font) -> some View {
        Rectangle()
            .fill(AppTheme.placeholder)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(font)
                    .foregroundStyle(AppTheme.bodyText.opacity(0.3))
            }
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
        if recipe.recordKind != .foodRecipe {
            result.append(TagInfo(text: recipe.recordKind.localizedName, color: AppTheme.tagCuisine))
        }
        if let d = recipe.difficulty {
            result.append(TagInfo(text: d.localizedName, color: AppTheme.tagDifficulty))
        }
        if let c = recipe.cuisine {
            result.append(TagInfo(text: c.localizedName, color: AppTheme.tagCuisine))
        }
        if let t = recipe.cookingTime {
            result.append(TagInfo(text: t.localizedName, color: AppTheme.tagCookingTime))
        }
        return result
    }
}

// MARK: - Recipe Thumbnail View (Grid Cell)

/// 缩略图网格用的小卡片：小图 + 菜名/日期，一屏可展示更多菜谱。
struct RecipeThumbnailView: View {

    private enum FloatingCaptionPosition {
        case bottomLeading
        case topTrailing
        case bottomTrailing
        case topLeading
        case center

        var alignment: Alignment {
            switch self {
            case .bottomLeading:
                return .bottomLeading
            case .topTrailing:
                return .topTrailing
            case .bottomTrailing:
                return .bottomTrailing
            case .topLeading:
                return .topLeading
            case .center:
                return .center
            }
        }

        var horizontalAlignment: HorizontalAlignment {
            switch self {
            case .topTrailing, .bottomTrailing:
                return .trailing
            default:
                return .leading
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .topTrailing, .bottomTrailing:
                return .trailing
            default:
                return .leading
            }
        }

        var frameAlignment: Alignment {
            switch self {
            case .topTrailing, .bottomTrailing:
                return .trailing
            default:
                return .leading
            }
        }
    }

    let recipe: Recipe
    let appearancePreference: AppearancePreference
    var collageIndex: Int = 0
    var imageAspectRatio: CGFloat = 4 / 3
    var usesScrapbookJitter: Bool = true
    var usesFloatingCaption: Bool = false
    private let infoSectionHeight: CGFloat = 68

    var body: some View {
        Group {
            if usesFloatingCaption, appearancePreference == .scrapbook {
                scrapbookFloatingCard
            } else if usesFloatingCaption {
                thumbnailImage
                    .overlay(alignment: floatingCaptionAlignment) {
                        GeometryReader { proxy in
                            floatingCaption(containerSize: proxy.size)
                                .padding(floatingCaptionPadding)
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height,
                                    alignment: floatingCaptionAlignment
                                )
                        }
                        .allowsHitTesting(false)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnailImage
                    thumbnailInfoSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .shadow(color: .black.opacity(appearancePreference == .scrapbook ? 0.05 : 0.06), radius: 3, x: 0, y: 1)
        .rotationEffect(scrapbookRotation)
        .padding(.top, scrapbookTopPadding)
        .padding(.bottom, scrapbookBottomPadding)
        .offset(y: scrapbookYOffset)
        .padding(.vertical, scrapbookVerticalBreathingRoom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "%@，%@",
                recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name,
                recipe.date.formatted(.dateTime.month().day())
            )
        )
    }

    private var scrapbookFloatingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            scrapbookThumbnailImage
                .frame(maxWidth: .infinity)

            scrapbookOutsideCaption
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var scrapbookOutsideCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name)
                .font(.scrapbook(size: scrapbookOutsideTitleSize, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(recipe.date, format: .dateTime.month().day())
                .font(.scrapbook(size: scrapbookOutsideDateSize, weight: .regular, relativeTo: .caption))
                .foregroundStyle(AppTheme.bodyText)

            ForEach(Array(scrapbookDetailLines(maxCount: scrapbookOutsideDetailLineLimit).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.scrapbook(size: scrapbookOutsideDetailSize, weight: .regular, relativeTo: .caption2))
                    .foregroundStyle(AppTheme.bodyText.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rotationEffect(floatingCaptionRotation)
    }

    private var thumbnailInfoSection: some View {
        VStack(alignment: .leading, spacing: infoSpacing) {
            Text(recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name)
                .font(titleFont)
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2, reservesSpace: true)
            Text(recipe.date, format: .dateTime.month().day())
                .font(dateFont)
                .foregroundStyle(AppTheme.bodyText)
            if appearancePreference == .scrapbook {
                ForEach(Array(scrapbookDetailLines(maxCount: 2).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.scrapbook(size: 10, weight: .regular, relativeTo: .caption2))
                        .foregroundStyle(AppTheme.bodyText.opacity(0.86))
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(height: thumbnailInfoSectionHeight, alignment: .topLeading)
    }

    private func floatingCaption(containerSize: CGSize) -> some View {
        VStack(alignment: floatingCaptionTextAlignment, spacing: floatingCaptionSpacing) {
            Text(recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name)
                .font(floatingTitleFont(containerSize: containerSize))
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2)
                .multilineTextAlignment(floatingTextAlignment)
                .shadow(color: scrapbookTextShadowColor, radius: scrapbookTextShadowRadius, x: 0, y: 1)
            Text(recipe.date, format: .dateTime.month().day())
                .font(floatingDateFont(containerSize: containerSize))
                .foregroundStyle(AppTheme.bodyText)
                .shadow(color: scrapbookTextShadowColor, radius: scrapbookTextShadowRadius, x: 0, y: 1)
            if appearancePreference == .scrapbook {
                ForEach(Array(scrapbookDetailLines(maxCount: floatingDetailLineLimit(containerSize: containerSize)).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(floatingDetailFont(containerSize: containerSize))
                        .foregroundStyle(AppTheme.bodyText.opacity(0.9))
                        .lineLimit(1)
                        .multilineTextAlignment(floatingTextAlignment)
                        .shadow(color: scrapbookTextShadowColor, radius: scrapbookTextShadowRadius, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal, floatingCaptionHorizontalInset)
        .padding(.vertical, floatingCaptionVerticalInset)
        .frame(maxWidth: floatingCaptionMaxWidth(containerSize: containerSize), alignment: floatingFrameAlignment)
        .background {
            if appearancePreference != .scrapbook {
                RoundedRectangle(cornerRadius: 6)
                    .fill(floatingCaptionBackground)
            }
        }
        .overlay {
            if appearancePreference != .scrapbook {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AppTheme.bodyText.opacity(0.16), lineWidth: 1)
            }
        }
        .shadow(color: floatingCaptionShadowColor, radius: floatingCaptionShadowRadius, x: 0, y: 2)
        .rotationEffect(floatingCaptionRotation)
    }

    /// 缩略图
    /// 横图完整显示在 4:3 框内；竖图顶部对齐裁剪到 4:3。
    @ViewBuilder
    private var thumbnailImage: some View {
        if appearancePreference == .scrapbook {
            scrapbookThumbnailImage
        } else {
            classicThumbnailImage
        }
    }

    private var cardBackground: Color {
        appearancePreference == .scrapbook ? .clear : AppTheme.cardBackground
    }

    private var cardCornerRadius: CGFloat {
        appearancePreference == .scrapbook ? 8 : 10
    }

    private var infoSpacing: CGFloat {
        appearancePreference == .scrapbook ? 1 : 4
    }

    private var thumbnailInfoSectionHeight: CGFloat {
        appearancePreference == .scrapbook ? 92 : infoSectionHeight
    }

    private var titleFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 15, weight: .semibold, relativeTo: .subheadline) : .subheadline
    }

    private var dateFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 12, weight: .regular, relativeTo: .caption2) : .caption2
    }

    private func floatingTitleFont(containerSize: CGSize) -> Font {
        guard appearancePreference == .scrapbook else {
            return .caption.weight(.semibold)
        }
        return .scrapbook(
            size: floatingTitleSize(containerSize: containerSize),
            weight: .semibold,
            relativeTo: .headline
        )
    }

    private func floatingDateFont(containerSize: CGSize) -> Font {
        guard appearancePreference == .scrapbook else {
            return .caption2
        }
        return .scrapbook(
            size: floatingDateSize(containerSize: containerSize),
            weight: .regular,
            relativeTo: .caption
        )
    }

    private func floatingDetailFont(containerSize: CGSize) -> Font {
        .scrapbook(
            size: floatingDetailSize(containerSize: containerSize),
            weight: .regular,
            relativeTo: .caption2
        )
    }

    private func floatingTitleSize(containerSize: CGSize) -> CGFloat {
        let longEdge = max(containerSize.width, containerSize.height)
        return min(max(longEdge * 0.16, 18), 34)
    }

    private func floatingDateSize(containerSize: CGSize) -> CGFloat {
        min(max(floatingTitleSize(containerSize: containerSize) * 0.5, 10), 15)
    }

    private func floatingDetailSize(containerSize: CGSize) -> CGFloat {
        min(max(floatingTitleSize(containerSize: containerSize) * 0.42, 9.5), 14)
    }

    private func floatingCaptionMaxWidth(containerSize: CGSize) -> CGFloat {
        guard appearancePreference == .scrapbook else {
            return 145
        }
        return min(max(containerSize.width * 0.92, 160), 300)
    }

    private func floatingDetailLineLimit(containerSize: CGSize) -> Int {
        let longEdge = max(containerSize.width, containerSize.height)
        if longEdge > 260 {
            return 3
        }
        if longEdge > 180 {
            return 2
        }
        return 1
    }

    private var scrapbookOutsideTitleSize: CGFloat {
        if imageAspectRatio > 1.45 {
            return 30
        }
        if imageAspectRatio < 0.9 {
            return 21
        }
        return 24
    }

    private var scrapbookOutsideDateSize: CGFloat {
        min(max(scrapbookOutsideTitleSize * 0.48, 11), 15)
    }

    private var scrapbookOutsideDetailSize: CGFloat {
        min(max(scrapbookOutsideTitleSize * 0.44, 10), 14)
    }

    private var scrapbookOutsideDetailLineLimit: Int {
        imageAspectRatio > 1.2 ? 3 : 2
    }

    private var floatingCaptionHorizontalInset: CGFloat {
        appearancePreference == .scrapbook ? 0 : 9
    }

    private var floatingCaptionVerticalInset: CGFloat {
        appearancePreference == .scrapbook ? 0 : 7
    }

    private var floatingCaptionSpacing: CGFloat {
        appearancePreference == .scrapbook ? 1 : 2
    }

    private var floatingCaptionBackground: Color {
        appearancePreference == .scrapbook ? AppTheme.cardBackground.opacity(0.86) : AppTheme.cardBackground.opacity(0.92)
    }

    private var floatingCaptionShadowColor: Color {
        appearancePreference == .scrapbook ? .clear : .black.opacity(0.08)
    }

    private var floatingCaptionShadowRadius: CGFloat {
        appearancePreference == .scrapbook ? 0 : 3
    }

    private var scrapbookTextShadowColor: Color {
        appearancePreference == .scrapbook ? AppTheme.notebookPaper.opacity(0.65) : .clear
    }

    private var scrapbookTextShadowRadius: CGFloat {
        appearancePreference == .scrapbook ? 1.5 : 0
    }

    private var floatingCaptionAlignment: Alignment {
        floatingCaptionPosition.alignment
    }

    private var floatingCaptionTextAlignment: HorizontalAlignment {
        floatingCaptionPosition.horizontalAlignment
    }

    private var floatingTextAlignment: TextAlignment {
        floatingCaptionPosition.textAlignment
    }

    private var floatingFrameAlignment: Alignment {
        floatingCaptionPosition.frameAlignment
    }

    private var floatingCaptionPosition: FloatingCaptionPosition {
        let positions: [FloatingCaptionPosition] = [
            .bottomLeading,
            .topTrailing,
            .bottomTrailing,
            .topLeading,
            .bottomLeading,
            .bottomLeading
        ]
        return positions[collageIndex % positions.count]
    }

    private var floatingCaptionPadding: EdgeInsets {
        let values: [EdgeInsets] = [
            EdgeInsets(top: 8, leading: 9, bottom: 10, trailing: 8),
            EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 9),
            EdgeInsets(top: 8, leading: 8, bottom: 10, trailing: 9),
            EdgeInsets(top: 10, leading: 9, bottom: 8, trailing: 8),
            EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
            EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 8)
        ]
        return values[collageIndex % values.count]
    }

    private var floatingCaptionRotation: Angle {
        guard appearancePreference == .scrapbook else { return .degrees(0) }
        let degrees: [Double] = [-2.2, 1.8, -1.4, 2.0, -0.8, 1.2]
        return .degrees(degrees[collageIndex % degrees.count])
    }

    private var scrapbookRotation: Angle {
        guard appearancePreference == .scrapbook else { return .degrees(0) }
        let degrees: [Double] = [-2.4, 1.6, -1.1, 2.1, -1.8, 0.9]
        return .degrees(degrees[collageIndex % degrees.count])
    }

    private var scrapbookTopPadding: CGFloat {
        guard appearancePreference == .scrapbook, usesScrapbookJitter else { return 0 }
        let paddings: [CGFloat] = [0, 30, 6, 42, 2, 26]
        return paddings[collageIndex % paddings.count]
    }

    private var scrapbookBottomPadding: CGFloat {
        guard appearancePreference == .scrapbook, usesScrapbookJitter else { return 0 }
        let paddings: [CGFloat] = [24, 0, 28, 2, 22, 4]
        return paddings[collageIndex % paddings.count]
    }

    private var scrapbookYOffset: CGFloat {
        guard appearancePreference == .scrapbook, usesScrapbookJitter else { return 0 }
        return collageIndex.isMultiple(of: 2) ? -6 : 18
    }

    private var scrapbookVerticalBreathingRoom: CGFloat {
        appearancePreference == .scrapbook && usesScrapbookJitter ? 8 : 0
    }

    private func scrapbookDetailLines(maxCount: Int) -> [String] {
        guard maxCount > 0 else { return [] }

        let content = recipe.localizedContent
        var lines: [String] = []

        if let noteLine = firstUsefulNoteLine(from: content.notes) {
            lines.append(noteLine)
        }

        if !content.ingredients.isEmpty {
            lines.append(contentsOf: content.ingredients.prefix(2))
        }

        if let firstStep = content.steps.first {
            lines.append(firstStep)
        }

        if lines.isEmpty {
            lines.append(contentsOf: collectScrapbookTags())
        }

        return lines
            .map(shortenedScrapbookLine)
            .filter { !$0.isEmpty }
            .prefix(maxCount)
            .map { $0 }
    }

    private func firstUsefulNoteLine(from notes: String) -> String? {
        notes
            .components(separatedBy: CharacterSet.newlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func shortenedScrapbookLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return String(trimmed.prefix(17)) + "..."
    }

    private func collectScrapbookTags() -> [String] {
        [
            recipe.recordKind != .foodRecipe ? recipe.recordKind.localizedName : nil,
            recipe.difficulty?.localizedName,
            recipe.cuisine?.localizedName,
            recipe.cookingTime?.localizedName
        ].compactMap { $0 }
    }

    private var classicThumbnailImage: some View {
        GeometryReader { geo in
            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                let isPortrait = uiImage.size.height > uiImage.size.width
                if isPortrait {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width / imageAspectRatio)
                        .clipped()
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.width / imageAspectRatio)
                }
            } else {
                placeholderImage(font: .title3)
            }
        }
        .aspectRatio(imageAspectRatio, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10))
    }

    private var scrapbookThumbnailImage: some View {
        Color.clear
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .overlay {
                if let data = recipe.cutoutImageData, let uiImage = UIImage(data: data) {
                    TrimmedCutoutImage(
                        data: data,
                        fallbackImage: uiImage,
                        padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                        shadowOpacity: 0.16,
                        shadowRadius: 5,
                        shadowY: 3,
                        maxPixelDimension: 900
                    )
                } else if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(8)
                } else {
                    placeholderImage(font: .title3)
                        .padding(8)
                }
            }
    }

    private func placeholderImage(font: Font) -> some View {
        Rectangle()
            .fill(AppTheme.placeholder)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(font)
                    .foregroundStyle(AppTheme.bodyText.opacity(0.3))
            }
    }
}

struct TrimmedCutoutImage: View {

    let data: Data
    let fallbackImage: UIImage
    let padding: EdgeInsets
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let maxPixelDimension: CGFloat?

    @State private var displayImage: UIImage?

    init(
        data: Data,
        fallbackImage: UIImage,
        padding: EdgeInsets,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat,
        maxPixelDimension: CGFloat? = nil
    ) {
        self.data = data
        self.fallbackImage = fallbackImage
        self.padding = padding
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.maxPixelDimension = maxPixelDimension
        _displayImage = State(initialValue: CutoutImageTrimCache.shared.image(for: data, maxPixelDimension: maxPixelDimension))
    }

    var body: some View {
        Group {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .padding(padding)
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
            } else {
                Color.clear
                    .overlay {
                        Image(uiImage: fallbackImage)
                            .resizable()
                            .scaledToFit()
                            .padding(padding)
                            .opacity(0.001)
                    }
            }
        }
            .task(id: data) {
                if let cachedImage = CutoutImageTrimCache.shared.image(for: data, maxPixelDimension: maxPixelDimension) {
                    withTransaction(Transaction(animation: nil)) {
                        displayImage = cachedImage
                    }
                    return
                }

                let trimmedImage = await Task.detached(priority: .utility) {
                    UIImage.trimmedCutoutImage(from: data, maxPixelDimension: maxPixelDimension)
                }.value

                guard let trimmedImage else {
                    return
                }

                CutoutImageTrimCache.shared.setImage(trimmedImage, for: data, maxPixelDimension: maxPixelDimension)
                withTransaction(Transaction(animation: nil)) {
                    displayImage = trimmedImage
                }
            }
    }
}

final class CutoutImageTrimCache {

    static let shared = CutoutImageTrimCache()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "caipu.cutout-trim-cache")
    private var inFlightKeys: Set<String> = []

    private init() {
        cache.countLimit = 80
    }

    func image(for data: Data, maxPixelDimension: CGFloat?) -> UIImage? {
        cache.object(forKey: cacheKey(for: data, maxPixelDimension: maxPixelDimension) as NSString)
    }

    func setImage(_ image: UIImage, for data: Data, maxPixelDimension: CGFloat?) {
        cache.setObject(image, forKey: cacheKey(for: data, maxPixelDimension: maxPixelDimension) as NSString)
    }

    func prewarm(_ imageDataList: [Data], limit: Int, maxPixelDimension: CGFloat?) {
        let uncachedItems = imageDataList.prefix(limit).filter { image(for: $0, maxPixelDimension: maxPixelDimension) == nil }
        guard !uncachedItems.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            for data in uncachedItems {
                let key = self.cacheKey(for: data, maxPixelDimension: maxPixelDimension)
                let shouldStart = queue.sync {
                    let shouldStart = self.cache.object(forKey: key as NSString) == nil && !self.inFlightKeys.contains(key)
                    if shouldStart {
                        self.inFlightKeys.insert(key)
                    }
                    return shouldStart
                }

                guard shouldStart else { continue }
                defer {
                    queue.sync {
                        _ = self.inFlightKeys.remove(key)
                    }
                }

                guard let image = UIImage.trimmedCutoutImage(from: data, maxPixelDimension: maxPixelDimension) else { continue }
                cache.setObject(image, forKey: key as NSString)
            }
        }
    }

    private func cacheKey(for data: Data, maxPixelDimension: CGFloat?) -> String {
        let dimension = maxPixelDimension.map { Int($0.rounded()) } ?? 0
        return "\(data.count)-\(data.hashValue)-\(dimension)"
    }
}

private extension UIImage {

    static func trimmedCutoutImage(from data: Data, maxPixelDimension: CGFloat?) -> UIImage? {
        autoreleasepool {
            let image: UIImage?
            if let maxPixelDimension {
                image = downsampledImage(from: data, maxPixelDimension: maxPixelDimension)
            } else {
                image = UIImage(data: data)
            }
            return image?.trimmingTransparentInsets()
        }
    }

    static func downsampledImage(from data: Data, maxPixelDimension: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelDimension.rounded()))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }

    func trimmingTransparentInsets(alphaThreshold: UInt8 = 8) -> UIImage {
        guard let cgImage else { return self }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundOpaquePixel = false

        for y in 0..<height {
            for x in 0..<width {
                let alphaIndex = y * bytesPerRow + x * bytesPerPixel + 3
                guard pixels[alphaIndex] > alphaThreshold else { continue }

                foundOpaquePixel = true
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard foundOpaquePixel else { return self }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard let croppedImage = cgImage.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: croppedImage, scale: scale, orientation: imageOrientation)
    }
}
