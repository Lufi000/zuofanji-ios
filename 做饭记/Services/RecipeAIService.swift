import UIKit
import Foundation

// MARK: - AI Suggestion Result

/// AI 识别后返回的菜谱建议，所有字段可选，填充时只覆盖空字段
struct RecipeAISuggestion {
    var name: String?
    var difficulty: Difficulty?
    var cuisine: Cuisine?
    var cookingTime: CookingTime?
    var ingredients: [String]
    var steps: [String]

    init(
        name: String? = nil,
        difficulty: Difficulty? = nil,
        cuisine: Cuisine? = nil,
        cookingTime: CookingTime? = nil,
        ingredients: [String] = [],
        steps: [String] = []
    ) {
        self.name = name
        self.difficulty = difficulty
        self.cuisine = cuisine
        self.cookingTime = cookingTime
        self.ingredients = ingredients
        self.steps = steps
    }
}

// MARK: - Service Errors

enum RecipeAIError: Error, LocalizedError {
    case invalidImage
    case networkError(Error)
    case apiError(String)
    case parseError(String)
    case rateLimited
    /// 本机按自然日统计的每日上限（与账号无关）
    case dailyLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法处理图片，请重试"
        case .networkError(let error):
            return "网络错误：\(error.localizedDescription)\n\n详情：\((error as NSError).domain) \((error as NSError).code)"
        case .apiError(let message):
            return "服务错误：\(message)"
        case .parseError(let msg):
            return "识别结果解析失败：\(msg)"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .dailyLimitExceeded:
            return "AI 分析每天最多使用 \(RecipeAIUsageLimiter.maxPerDay) 次，请明天再试"
        }
    }
}

// MARK: - Service

/// 调用阿里云通义千问视觉 API，识别菜品图片并返回菜谱建议。
/// 图片仅在内存中处理，转为 base64 后随请求发送，不落盘。
/// DashScope（千问）API Key 仅在服务端做饭记 BFF 的 `DASHSCOPE_API_KEY`；客户端只配 BFF 地址与 `X-App-Token`（与 cycle/MiniMax 无关）。
final class RecipeAIService {

    private static let model = "qwen3-vl-plus"

    // MARK: - Public API

    /// 识别图片中的菜品，返回菜谱建议。
    /// - Parameter image: 菜品照片
    /// - Returns: 识别结果（所有字段均可能为空/空数组）
    /// - Throws: RecipeAIError
    func analyze(image: UIImage) async throws -> RecipeAISuggestion {
        guard RecipeAIUsageLimiter.canConsume() else {
            throw RecipeAIError.dailyLimitExceeded
        }

        let base = RecipeSecrets.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = RecipeSecrets.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !token.isEmpty else {
            throw RecipeAIError.apiError("未配置 BFF：将 Services/RecipeSecrets.swift.example 复制为 RecipeSecrets.swift 并填入 baseURL 与 appToken")
        }

        // 限制图片最大边长为 1024px，避免 base64 体积过大导致超时
        let resized = resizeIfNeeded(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.6) else {
            throw RecipeAIError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()
        print("[RecipeAI] Image size after resize: \(imageData.count / 1024)KB")

        let request = try buildRequest(base64Image: base64Image, baseURLString: base, appToken: token)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[RecipeAI] Network error: \(error)")
            throw RecipeAIError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                throw RecipeAIError.rateLimited
            }
            if httpResponse.statusCode != 200 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw RecipeAIError.apiError("HTTP \(httpResponse.statusCode): \(message)")
            }
        }

        let suggestion = try parseResponse(data: data)
        RecipeAIUsageLimiter.recordSuccessfulConsumption()
        return suggestion
    }

    // MARK: - Private

    private func buildRequest(base64Image: String, baseURLString: String, appToken: String) throws -> URLRequest {
        guard let url = URL(string: baseURLString) else {
            throw RecipeAIError.apiError("Invalid BFF URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let cuisineOptions = Cuisine.allCases.map { $0.rawValue }.joined(separator: " | ")
        let difficultyOptions = Difficulty.allCases.map { $0.rawValue }.joined(separator: " | ")
        let cookingTimeOptions = CookingTime.allCases.map { $0.rawValue }.joined(separator: " | ")

        let prompt = """
        请识别这张图片中的菜品，以 JSON 格式返回以下字段：
        - name: 菜名（字符串）
        - difficulty: 难度，必须是以下之一：\(difficultyOptions)
        - cuisine: 菜系，必须是以下之一：\(cuisineOptions)
        - cookingTime: 烹饪时长，必须是以下之一：\(cookingTimeOptions)
        - ingredients: 主要原材料列表（字符串数组，每条包含食材名和用量，如 "鸡胸肉 300g"）
        - steps: 做法步骤列表（字符串数组，有序，每条为一个步骤）

        只返回 JSON，不要其他文字，不要 markdown 代码块。
        示例格式：
        {"name":"宫保鸡丁","difficulty":"中等","cuisine":"川菜","cookingTime":"30分钟","ingredients":["鸡胸肉 300g","花生 50g"],"steps":["鸡肉切丁腌制10分钟","热锅炒香干辣椒","加入鸡丁翻炒至变色","加酱汁翻炒出锅"]}
        """

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(data: Data) throws -> RecipeAISuggestion {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("[RecipeAI] parseResponse failed at structure level. raw=\(raw)")
            throw RecipeAIError.parseError("Invalid response structure")
        }

        // qwen3-vl-plus 是思考模型：最终回答在 content，推理过程在 reasoning_content。
        // 若 content 为 null（极少情况），回退到 reasoning_content 中提取 JSON。
        let rawContent: String
        if let c = message["content"] as? String, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawContent = c
        } else if let r = message["reasoning_content"] as? String {
            print("[RecipeAI] content is null/empty, falling back to reasoning_content")
            rawContent = r
        } else {
            print("[RecipeAI] both content and reasoning_content are missing. message keys: \(message.keys.sorted())")
            throw RecipeAIError.parseError("No content in response")
        }

        print("[RecipeAI] rawContent prefix: \(String(rawContent.prefix(300)))")

        let jsonString = extractJSON(from: rawContent)

        guard let jsonData = jsonString.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw RecipeAIError.parseError("Failed to parse suggestion JSON")
        }

        let name = info["name"] as? String
        let difficulty = (info["difficulty"] as? String).flatMap { Difficulty(rawValue: $0) }
        let cuisine = (info["cuisine"] as? String).flatMap { Cuisine(rawValue: $0) }
        let cookingTime = (info["cookingTime"] as? String).flatMap { CookingTime(rawValue: $0) }
        let ingredients = info["ingredients"] as? [String] ?? []
        let steps = info["steps"] as? [String] ?? []

        return RecipeAISuggestion(
            name: name,
            difficulty: difficulty,
            cuisine: cuisine,
            cookingTime: cookingTime,
            ingredients: ingredients,
            steps: steps
        )
    }

    /// 剥离模型有时返回的 markdown 代码块包裹
    private func extractJSON(from content: String) -> String {
        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```json") {
            result = String(result.dropFirst(7))
        } else if result.hasPrefix("```") {
            result = String(result.dropFirst(3))
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 限制图片最大边长，避免 base64 体积过大导致请求超时
    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Daily usage (per device, local calendar day)

enum RecipeAIUsageLimiter {
    /// 每日最多调用 AI 分析次数（本机存储，按用户设备自然日重置）
    static let maxPerDay = 10

    private static let defaults = UserDefaults.standard
    private static let countKey = "recipeAI.dailyUsageCount"
    private static let dayKey = "recipeAI.dailyUsageDay"

    private static func todayString(in calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func canConsume() -> Bool {
        usageCountForToday() < maxPerDay
    }

    static func usageCountForToday() -> Int {
        let today = todayString()
        guard defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    static func recordSuccessfulConsumption() {
        let today = todayString()
        let count: Int
        if defaults.string(forKey: dayKey) == today {
            count = defaults.integer(forKey: countKey) + 1
        } else {
            count = 1
        }
        defaults.set(today, forKey: dayKey)
        defaults.set(count, forKey: countKey)
    }
}
