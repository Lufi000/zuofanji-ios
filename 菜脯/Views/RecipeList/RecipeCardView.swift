import SwiftUI
import UIKit

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
                        shadowY: 5
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

    let recipe: Recipe
    let appearancePreference: AppearancePreference
    var collageIndex: Int = 0
    private let infoSectionHeight: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailImage
            VStack(alignment: .leading, spacing: infoSpacing) {
                Text(recipe.localizedContent.name.isEmpty ? AppLocalization.text("未命名") : recipe.localizedContent.name)
                    .font(titleFont)
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2, reservesSpace: true)
                Text(recipe.date, format: .dateTime.month().day())
                    .font(dateFont)
                    .foregroundStyle(AppTheme.bodyText)
            }
            .padding(8)
            .frame(height: infoSectionHeight, alignment: .topLeading)
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

    private var titleFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 15, weight: .semibold, relativeTo: .subheadline) : .subheadline
    }

    private var dateFont: Font {
        appearancePreference == .scrapbook ? .scrapbook(size: 12, weight: .regular, relativeTo: .caption2) : .caption2
    }

    private var scrapbookRotation: Angle {
        guard appearancePreference == .scrapbook else { return .degrees(0) }
        let degrees: [Double] = [-2.4, 1.6, -1.1, 2.1, -1.8, 0.9]
        return .degrees(degrees[collageIndex % degrees.count])
    }

    private var scrapbookTopPadding: CGFloat {
        guard appearancePreference == .scrapbook else { return 0 }
        let paddings: [CGFloat] = [0, 30, 6, 42, 2, 26]
        return paddings[collageIndex % paddings.count]
    }

    private var scrapbookBottomPadding: CGFloat {
        guard appearancePreference == .scrapbook else { return 0 }
        let paddings: [CGFloat] = [24, 0, 28, 2, 22, 4]
        return paddings[collageIndex % paddings.count]
    }

    private var scrapbookYOffset: CGFloat {
        guard appearancePreference == .scrapbook else { return 0 }
        return collageIndex.isMultiple(of: 2) ? -6 : 18
    }

    private var scrapbookVerticalBreathingRoom: CGFloat {
        appearancePreference == .scrapbook ? 8 : 0
    }

    private var classicThumbnailImage: some View {
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
                placeholderImage(font: .title3)
            }
        }
        .aspectRatio(4/3, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 10))
    }

    private var scrapbookThumbnailImage: some View {
        Color.clear
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                if let data = recipe.cutoutImageData, let uiImage = UIImage(data: data) {
                    TrimmedCutoutImage(
                        data: data,
                        fallbackImage: uiImage,
                        padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                        shadowOpacity: 0.16,
                        shadowRadius: 5,
                        shadowY: 3
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

    @State private var displayImage: UIImage?

    init(
        data: Data,
        fallbackImage: UIImage,
        padding: EdgeInsets,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat
    ) {
        self.data = data
        self.fallbackImage = fallbackImage
        self.padding = padding
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        _displayImage = State(initialValue: CutoutImageTrimCache.shared.image(for: data))
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
                if let cachedImage = CutoutImageTrimCache.shared.image(for: data) {
                    withTransaction(Transaction(animation: nil)) {
                        displayImage = cachedImage
                    }
                    return
                }

                let trimmedImage = await Task.detached(priority: .utility) {
                    UIImage(data: data)?.trimmingTransparentInsets()
                }.value

                guard let trimmedImage else {
                    return
                }

                CutoutImageTrimCache.shared.setImage(trimmedImage, for: data)
                withTransaction(Transaction(animation: nil)) {
                    displayImage = trimmedImage
                }
            }
    }
}

final class CutoutImageTrimCache {

    static let shared = CutoutImageTrimCache()

    private let cache = NSCache<NSData, UIImage>()
    private let queue = DispatchQueue(label: "caipu.cutout-trim-cache")
    private var inFlightKeys: Set<NSData> = []

    private init() {
        cache.countLimit = 180
    }

    func image(for data: Data) -> UIImage? {
        cache.object(forKey: data as NSData)
    }

    func setImage(_ image: UIImage, for data: Data) {
        cache.setObject(image, forKey: data as NSData)
    }

    func prewarm(_ imageDataList: [Data], limit: Int) {
        let uncachedItems = imageDataList.prefix(limit).filter { image(for: $0) == nil }
        guard !uncachedItems.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            for data in uncachedItems {
                let key = data as NSData
                let shouldStart = queue.sync {
                    let shouldStart = self.cache.object(forKey: key) == nil && !self.inFlightKeys.contains(key)
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

                guard let image = UIImage(data: data)?.trimmingTransparentInsets() else { continue }
                cache.setObject(image, forKey: key)
            }
        }
    }
}

private extension UIImage {

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
