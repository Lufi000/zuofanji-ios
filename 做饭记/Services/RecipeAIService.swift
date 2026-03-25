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
        }
    }
}

// MARK: - Service

/// 调用阿里云通义千问视觉 API，识别菜品图片并返回菜谱建议。
/// 图片仅在内存中处理，转为 base64 后随请求发送，不落盘。
/// API Key 放在本地 `RecipeSecrets.swift`（由 `RecipeSecrets.swift.example` 复制），勿提交仓库；上架前建议改为自有代理。
final class RecipeAIService {

    private static let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    private static let model = "qwen3-vl-plus"

    // MARK: - Public API

    /// 识别图片中的菜品，返回菜谱建议。
    /// - Parameter image: 菜品照片
    /// - Returns: 识别结果（所有字段均可能为空/空数组）
    /// - Throws: RecipeAIError
    func analyze(image: UIImage) async throws -> RecipeAISuggestion {
        let apiKey = RecipeSecrets.dashScopeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw RecipeAIError.apiError("未配置 API Key：将 Services/RecipeSecrets.swift.example 复制为 RecipeSecrets.swift 并填入密钥")
        }

        // 限制图片最大边长为 1024px，避免 base64 体积过大导致超时
        let resized = resizeIfNeeded(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.6) else {
            throw RecipeAIError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()
        print("[RecipeAI] Image size after resize: \(imageData.count / 1024)KB")

        let request = try buildRequest(base64Image: base64Image, apiKey: apiKey)

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

        return try parseResponse(data: data)
    }

    // MARK: - Private

    private func buildRequest(base64Image: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: Self.baseURL) else {
            throw RecipeAIError.apiError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
