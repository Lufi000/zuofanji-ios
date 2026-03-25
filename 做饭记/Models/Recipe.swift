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

    // MARK: Tags（用 rawValue 存储，便于 Predicate 筛选）

    var difficultyRawValue: String?
    var cuisineRawValue: String?
    var cookingTimeRawValue: String?

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

    // MARK: Init

    init(
        name: String,
        date: Date = .now,
        imageData: Data? = nil,
        cutoutImageData: Data? = nil,
        notes: String = "",
        ingredients: [String] = [],
        steps: [String] = [],
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
        self.difficultyRawValue = difficulty?.rawValue
        self.cuisineRawValue = cuisine?.rawValue
        self.cookingTimeRawValue = cookingTime?.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - Tag Enums

/// 难度：简单 / 中等 / 难
enum Difficulty: String, CaseIterable, Identifiable, Codable {
    case easy = "简单"
    case medium = "中等"
    case hard = "难"

    var id: String { rawValue }
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
}

/// 耗时区间
enum CookingTime: String, CaseIterable, Identifiable, Codable {
    case fifteen = "15分钟"
    case thirty = "30分钟"
    case oneHour = "1小时"
    case overOneHour = "1小时以上"

    var id: String { rawValue }
}
