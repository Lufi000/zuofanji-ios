import Foundation
import SwiftData

// MARK: - Recipe Model

/// 菜谱记录：一道菜的完整信息。
/// 标签字段（难度/菜式/耗时）存储为 rawValue 字符串，
/// 以便 SwiftData #Predicate 可直接按字符串筛选。
@Model
final class Recipe {

    var name: String
    var date: Date

    /// 菜品照片，SwiftData 自动外置存储大数据
    @Attribute(.externalStorage)
    var imageData: Data?

    /// 抠图结果（透明背景 PNG），用于贴纸展示
    @Attribute(.externalStorage)
    var cutoutImageData: Data?

    var notes: String

    /// 原材料列表，每条格式如 "鸡胸肉 300g"
    var ingredients: [String]

    /// 做法步骤列表，有序
    var steps: [String]

    /// 记录类型：普通菜谱 / 宝宝餐 / 宝宝日常 / 普通手帐。
    var recordKindRawValue: String?

    // MARK: Tags（用 rawValue 存储，便于 Predicate 筛选）

    var difficultyRawValue: String?
    var cuisineRawValue: String?
    var cookingTimeRawValue: String?

    /// 原始内容所使用的语言，以及按语言缓存的菜谱译文。
    var sourceLanguageRawValue: String?
    var localizedContentsData: Data?

    var createdAt: Date
    var updatedAt: Date

    // MARK: Computed（类型安全访问）

    @Transient
    var difficulty: Difficulty? {
        get { difficultyRawValue.flatMap { Difficulty(rawValue: $0) } }
        set { difficultyRawValue = newValue?.rawValue }
    }

    @Transient
    var cuisine: Cuisine? {
        get { cuisineRawValue.flatMap { Cuisine(rawValue: $0) } }
        set { cuisineRawValue = newValue?.rawValue }
    }

    @Transient
    var cookingTime: CookingTime? {
        get { cookingTimeRawValue.flatMap { CookingTime(rawValue: $0) } }
        set { cookingTimeRawValue = newValue?.rawValue }
    }

    @Transient
    var recordKind: RecipeRecordKind {
        get {
            if let recordKindRawValue,
               let kind = RecipeRecordKind(rawValue: recordKindRawValue) {
                return kind
            }
            return ingredients.isEmpty && steps.isEmpty ? .scrapbook : .foodRecipe
        }
        set { recordKindRawValue = newValue.rawValue }
    }

    // MARK: Init

    init(
        name: String,
        date: Date = .now,
        imageData: Data? = nil,
        cutoutImageData: Data? = nil,
        notes: String = "",
        ingredients: [String] = [],
        steps: [String] = [],
        recordKind: RecipeRecordKind = .foodRecipe,
        difficulty: Difficulty? = nil,
        cuisine: Cuisine? = nil,
        cookingTime: CookingTime? = nil
    ) {
        self.name = name
        self.date = date
        self.imageData = imageData
        self.cutoutImageData = cutoutImageData
        self.notes = notes
        self.ingredients = ingredients
        self.steps = steps
        self.recordKindRawValue = recordKind.rawValue
        self.difficultyRawValue = difficulty?.rawValue
        self.cuisineRawValue = cuisine?.rawValue
        self.cookingTimeRawValue = cookingTime?.rawValue
        self.sourceLanguageRawValue = nil
        self.localizedContentsData = nil
        self.createdAt = .now
        self.updatedAt = .now
    }

    func content(for language: AppLanguage) -> RecipeLocalizedContent {
        if let content = localizedContents[language.rawValue] {
            return content
        }
        return originalContent
    }

    @Transient
    var localizedContent: RecipeLocalizedContent {
        content(for: AppLanguage.current)
    }

    func setCurrentContentLanguage(_ language: AppLanguage) {
        sourceLanguageRawValue = language.rawValue
        localizedContentsData = try? JSONEncoder().encode([
            language.rawValue: originalContent
        ])
    }

    func setLocalizedContent(_ content: RecipeLocalizedContent, for language: AppLanguage) {
        var contents = localizedContents
        contents[language.rawValue] = content
        localizedContentsData = try? JSONEncoder().encode(contents)
    }

    func hasLocalizedContent(for language: AppLanguage) -> Bool {
        localizedContents[language.rawValue] != nil
    }

    @Transient
    var sourceLanguage: AppLanguage {
        if let rawValue = sourceLanguageRawValue,
           let language = AppLanguage(rawValue: rawValue) {
            return language
        }
        return RecipeLocalizedContent.inferLanguage(from: originalContent)
    }

    @Transient
    private var originalContent: RecipeLocalizedContent {
        RecipeLocalizedContent(
            name: name,
            notes: notes,
            ingredients: ingredients,
            steps: steps
        )
    }

    @Transient
    private var localizedContents: [String: RecipeLocalizedContent] {
        guard let localizedContentsData,
              let contents = try? JSONDecoder().decode(
                [String: RecipeLocalizedContent].self,
                from: localizedContentsData
              ) else {
            return [:]
        }
        return contents
    }
}

enum RecipeRecordKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case foodRecipe
    case babyMeal
    case babyDaily
    case scrapbook

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .foodRecipe:
            return AppLocalization.text("菜谱")
        case .babyMeal:
            return AppLocalization.text("宝宝餐")
        case .babyDaily:
            return AppLocalization.text("宝宝日常")
        case .scrapbook:
            return AppLocalization.text("生活手帐")
        }
    }

    var isFoodRelated: Bool {
        self == .foodRecipe || self == .babyMeal
    }

    var isBabyRecord: Bool {
        self == .babyMeal || self == .babyDaily
    }
}

struct RecipeLocalizedContent: Codable {
    let name: String
    let notes: String
    let ingredients: [String]
    let steps: [String]

    static func inferLanguage(from content: RecipeLocalizedContent) -> AppLanguage {
        let text = ([content.name, content.notes] + content.ingredients + content.steps).joined()
        let scalars = text.unicodeScalars
        if scalars.contains(where: {
            (0x3040...0x30FF).contains($0.value)
        }) {
            return .japanese
        }
        if scalars.contains(where: {
            (0x4E00...0x9FFF).contains($0.value)
        }) {
            return .chinese
        }
        return .english
    }
}

// MARK: - Tag Enums

/// 难度：简单 / 中等 / 难
enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy = "简单"
    case medium = "中等"
    case hard = "难"

    var id: String { rawValue }

    var localizedName: String { AppLocalization.text(rawValue) }
}

/// 菜式：地域 / 国别菜系
enum Cuisine: String, CaseIterable, Identifiable, Codable {
    // 中国菜系
    case sichuan       = "川菜"
    case cantonese     = "粤菜"
    case chaoshan      = "潮汕菜"
    case hunan         = "湘菜"
    case shandong      = "鲁菜"
    case jiangsu       = "苏菜"
    case zhejiang      = "浙菜"
    case fujian        = "闽菜"
    case northeast     = "东北菜"
    case beijing       = "京菜"
    // 东亚 & 东南亚
    case japanese      = "日料"
    case korean        = "韩料"
    case taiwanese     = "台湾菜"
    case hongkong      = "港式茶餐"
    case vietnamese    = "越南菜"
    case thai          = "泰餐"
    case burmese       = "缅甸菜"
    case singaporean   = "新加坡菜"
    case malaysian     = "马来菜"
    // 南亚
    case indian        = "印度菜"
    case pakistani     = "巴基斯坦菜"
    case srilankan     = "斯里兰卡菜"
    case nepali        = "尼泊尔菜"
    // 西方
    case french        = "法国菜"
    case italian       = "意大利菜"
    case spanish       = "西班牙菜"
    case greek         = "希腊菜"
    case german        = "德国菜"
    case western       = "西餐"
    case mediterranean = "地中海菜"
    // 兜底
    case other         = "其他"

    var id: String { rawValue }

    var localizedName: String { AppLocalization.text(rawValue) }
}

/// 耗时区间
enum CookingTime: String, CaseIterable, Identifiable, Codable {
    case fifteen = "15分钟"
    case thirty = "30分钟"
    case oneHour = "1小时"
    case overOneHour = "1小时以上"

    var id: String { rawValue }

    var localizedName: String { AppLocalization.text(rawValue) }
}
