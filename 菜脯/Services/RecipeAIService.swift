import UIKit
import Foundation

// MARK: - AI Suggestion Result

/// 图片识别的内容类别。非食物图片会生成适合手帐使用的画面描述，而非虚构菜谱。
enum ImageContentKind: String {
    case dish
    case ingredient
    case object
    case person
    case scene
    case unknown

    var isFoodRelated: Bool {
        self == .dish || self == .ingredient
    }
}

/// AI 识别后返回的菜谱或照片手帐建议，所有字段可选，填充时只覆盖空字段
struct RecipeAISuggestion {
    var contentKind: ImageContentKind = .dish
    var recordKind: RecipeRecordKind = .foodRecipe
    var name: String?
    /// 人物、物品和场景照片的可编辑手帐描述
    var visualDescription: String?
    var visualDescriptionVariants: [DescriptionVariant]
    var difficulty: Difficulty?
    var cuisine: Cuisine?
    var cookingTime: CookingTime?
    var ingredients: [String]
    var steps: [String]

    init(
        contentKind: ImageContentKind = .dish,
        recordKind: RecipeRecordKind = .foodRecipe,
        name: String? = nil,
        visualDescription: String? = nil,
        visualDescriptionVariants: [DescriptionVariant] = [],
        difficulty: Difficulty? = nil,
        cuisine: Cuisine? = nil,
        cookingTime: CookingTime? = nil,
        ingredients: [String] = [],
        steps: [String] = []
    ) {
        self.contentKind = contentKind
        self.recordKind = recordKind
        self.name = name
        self.visualDescription = visualDescription
        self.visualDescriptionVariants = visualDescriptionVariants
        self.difficulty = difficulty
        self.cuisine = cuisine
        self.cookingTime = cookingTime
        self.ingredients = ingredients
        self.steps = steps
    }
}

enum DescriptionVariantStyle: String {
    case journal
    case story
    case poem
}

struct DescriptionVariant: Identifiable, Hashable {
    let style: DescriptionVariantStyle
    let title: String
    let text: String

    var id: String { style.rawValue }
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
            return AppLocalization.text("无法处理图片，请重试")
        case .networkError(let error):
            return AppLocalization.format(
                "网络错误：%@\n\n详情：%@ %d",
                error.localizedDescription,
                (error as NSError).domain,
                (error as NSError).code
            )
        case .apiError(let message):
            return AppLocalization.format("服务错误：%@", message)
        case .parseError(let msg):
            return AppLocalization.format("识别结果解析失败：%@", msg)
        case .rateLimited:
            return AppLocalization.text("请求过于频繁，请稍后再试")
        }
    }
}

// MARK: - Service

/// 调用阿里云通义千问视觉 API，识别菜品图片并返回菜谱建议。
/// 图片仅在内存中处理，转为 base64 后随请求发送，不落盘。
/// DashScope（千问）API Key 仅在服务端菜脯 BFF 的 `DASHSCOPE_API_KEY`；客户端只配 BFF 地址与 `X-App-Token`（与 cycle/MiniMax 无关）。
final class RecipeAIService {

    private static let model = "qwen3-vl-plus"

    // MARK: - Public API

    /// 识别图片中的菜品，返回菜谱建议。
    /// - Parameter image: 菜品照片
    /// - Returns: 识别结果（所有字段均可能为空/空数组）
    /// - Throws: RecipeAIError
    func analyze(image: UIImage) async throws -> RecipeAISuggestion {
        // 限制图片最大边长为 1024px，避免 base64 体积过大导致超时
        let resized = resizeIfNeeded(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.6) else {
            throw RecipeAIError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()
        print("[RecipeAI] Image size after resize: \(imageData.count / 1024)KB")

        let request = try buildImageRequest(base64Image: base64Image)
        let suggestion = try await send(request: request)
        return suggestion
    }

    /// 根据用户手动修正后的菜名，重新生成匹配的原材料与做法。
    /// - Parameter recipeName: 用户确认的菜名
    /// - Returns: 菜谱建议（重点使用 ingredients / steps）
    /// - Throws: RecipeAIError
    func suggestRecipe(named recipeName: String) async throws -> RecipeAISuggestion {
        let trimmedName = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return RecipeAISuggestion()
        }

        let request = try buildNameRequest(recipeName: trimmedName)
        let suggestion = try await send(request: request)
        return suggestion
    }

    /// 将已有菜谱翻译到目标语言。标签仍使用稳定 rawValue，不需要翻译。
    func translate(
        content: RecipeLocalizedContent,
        to language: AppLanguage
    ) async throws -> RecipeLocalizedContent {
        let request = try buildTranslationRequest(content: content, language: language)
        let data = try await sendRaw(request: request)
        return try parseLocalizedContent(data: data)
    }

    // MARK: - Private

    private func send(request: URLRequest) async throws -> RecipeAISuggestion {
        let data = try await sendRaw(request: request)
        return try parseResponse(data: data)
    }

    private func sendRaw(request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

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

        return data
    }

    private func baseRequest() throws -> URLRequest {
        let base = RecipeSecrets.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = RecipeSecrets.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !token.isEmpty else {
            throw RecipeAIError.apiError("未配置 BFF：将 Services/RecipeSecrets.swift.example 复制为 RecipeSecrets.swift 并填入 baseURL 与 appToken")
        }
        guard let url = URL(string: base) else {
            throw RecipeAIError.apiError("Invalid BFF URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        return request
    }

    private func buildImageRequest(base64Image: String) throws -> URLRequest {
        var request = try baseRequest()

        let cuisineOptions = Cuisine.allCases.map { $0.rawValue }.joined(separator: " | ")
        let difficultyOptions = Difficulty.allCases.map { $0.rawValue }.joined(separator: " | ")
        let cookingTimeOptions = CookingTime.allCases.map { $0.rawValue }.joined(separator: " | ")

        let prompt: String
        switch AppLanguage.current {
        case .chinese:
            prompt = """
        先判断图片内容，并以 JSON 返回。contentKind 必须为 dish、ingredient、object、person、scene、unknown 之一。recordKind 必须为 foodRecipe、babyMeal、babyDaily、scrapbook 之一。

        recordKind 判断规则：
        - 普通菜品或食材：foodRecipe
        - 画面明确是婴幼儿/小朋友，且正在吃饭、喂食、使用餐具，或画面有明显宝宝餐/辅食：babyMeal
        - 画面明确是婴幼儿/小朋友，但不是进食场景，例如玩耍、睡觉、出门、阅读、亲子互动、洗澡：babyDaily
        - 其他人物、物品、场景或无法判断：scrapbook

        若 recordKind 为 foodRecipe，请返回菜谱字段：
        - name: 菜名或食材名（字符串）
        - difficulty: 难度，必须是以下之一：\(difficultyOptions)
        - cuisine: 菜系，必须是以下之一：\(cuisineOptions)
        - cookingTime: 烹饪时长，必须是以下之一：\(cookingTimeOptions)
        - ingredients: 主要原材料列表（字符串数组，每条包含食材名和用量，如 "鸡胸肉 300g"）
        - steps: 做法步骤列表（字符串数组，有序，每条为一个步骤）
        - visualDescription: 空字符串
        - visualDescriptionVariants: 空数组

        若 recordKind 为 babyMeal：
        - name: 适合作为宝宝餐记录的标题
        - difficulty、cuisine、cookingTime 设为 null
        - ingredients: 画面可见或合理匹配的宝宝餐食材列表（字符串数组）
        - steps: 简短、温和的宝宝餐做法步骤（字符串数组）
        - visualDescription: 用中文写 2-4 行记录建议，每行格式为“餐次：”“吃了多少：”“喜欢程度：”“观察：”，无法确认的写“待补充”
        - visualDescriptionVariants: 空数组

        若 recordKind 为 babyDaily：
        - name: 适合作为宝宝日常手帐标题的简短文字
        - visualDescription: 使用 visualDescriptionVariants 第一项的 text
        - visualDescriptionVariants: 返回 3 个对象，style 分别为 journal、story、poem，title 分别为“手帐版”“故事版”“小诗版”。journal 用 3-5 行宝宝日常记录，每行格式为“场景：”“心情：”“成长瞬间：”“今日小记：”，无法确认的写“待补充”；story 写成 4-6 句温柔短故事；poem 写成 4-8 行小诗。三种都只描述画面可见事实，不猜测身份、关系、性格、健康或不可见事件。
        - difficulty、cuisine、cookingTime 设为 null；ingredients、steps 设为空数组。

        若 recordKind 为 scrapbook：
        - name: 适合作为手帐标题的简短文字
        - visualDescription: 使用 visualDescriptionVariants 第一项的 text
        - visualDescriptionVariants: 返回 3 个对象，style 分别为 journal、story、poem，title 分别为“手帐版”“故事版”“小诗版”。journal 写一段自然、温暖、具体的 2-4 句画面描写；story 基于可见画面写成 4-6 句微型故事；poem 基于可见画面写成 4-8 行小诗。人物请优先写可直接看见的表情、动作、穿搭、姿态、光线与氛围；若画面明确是幼童，可以使用“小朋友”或“可爱的宝宝”。只描述画面可见事实，不识别身份，不猜测关系、职业、性格、健康状况或其他不可见信息。物品可描述外观和“看起来像”的材质；不要把无法凭图片确认的材质当作事实。
        - difficulty、cuisine、cookingTime 设为 null；ingredients、steps 设为空数组。

        只返回 JSON，不要其他文字，不要 markdown 代码块。
        示例格式：
        {"contentKind":"dish","recordKind":"foodRecipe","name":"宫保鸡丁","visualDescription":"","visualDescriptionVariants":[],"difficulty":"中等","cuisine":"川菜","cookingTime":"30分钟","ingredients":["鸡胸肉 300g","花生 50g"],"steps":["鸡肉切丁腌制10分钟","热锅炒香干辣椒","加入鸡丁翻炒至变色","加酱汁翻炒出锅"]}
        """
        case .english:
            prompt = """
        First classify the image. Return JSON only. contentKind must be one of dish, ingredient, object, person, scene, unknown. recordKind must be one of foodRecipe, babyMeal, babyDaily, scrapbook.
        Use babyMeal only when an infant or young child is visibly eating, being fed, using tableware, or shown with clear baby food. Use babyDaily when an infant or young child is visible but the scene is not about eating, such as playing, sleeping, going out, reading, bathing, or family interaction. Use scrapbook for other non-food photos.

        For foodRecipe, return these recipe fields:
        - name: dish name in English
        - difficulty: must be one of these exact values: \(difficultyOptions)
        - cuisine: must be one of these exact values: \(cuisineOptions)
        - cookingTime: must be one of these exact values: \(cookingTimeOptions)
        - ingredients: an array of ingredients with quantities, written in English
        - steps: an ordered array of cooking instructions, written in English
        - visualDescription: an empty string
        - visualDescriptionVariants: an empty array

        For babyMeal: return a short baby meal title, null tags, baby-food ingredients, simple baby meal steps, a visualDescription with labeled lines: Meal, Amount eaten, Liked it, Observation, and an empty visualDescriptionVariants array. Use "To fill in" when not visible.

        For babyDaily: return a short baby daily scrapbook title, set visualDescription to the first visualDescriptionVariants text, and return exactly 3 visualDescriptionVariants objects. Their styles must be journal, story, poem, with titles "Journal", "Story", "Poem". Journal uses labeled lines: Scene, Mood, Growth moment, Daily note; story is a 4-6 sentence micro story; poem is a 4-8 line poem. Only describe visible facts and use "To fill in" when not visible. Do not infer identity, relationships, personality, health, or unseen events. Use empty arrays for ingredients and steps, and null for tags.

        For scrapbook: return a short scrapbook title in name, set visualDescription to the first visualDescriptionVariants text, and return exactly 3 visualDescriptionVariants objects. Their styles must be journal, story, poem, with titles "Journal", "Story", "Poem". Journal is a warm, specific 2-4 sentence visual description; story is a 4-6 sentence micro story grounded in the visible image; poem is a 4-8 line poem grounded in the visible image. For people, describe only visible expression, gesture, outfit, pose, lighting, and atmosphere; do not identify the person or infer private traits. For objects, describe visible appearance and "looks like" materials without stating uncertain materials as facts. Use empty arrays for ingredients and steps, and null for tags.

        Return JSON only, with no markdown or additional text.
        Example:
        {"contentKind":"dish","recordKind":"foodRecipe","name":"Kung Pao Chicken","visualDescription":"","visualDescriptionVariants":[],"difficulty":"中等","cuisine":"川菜","cookingTime":"30分钟","ingredients":["Chicken breast 300g","Peanuts 50g"],"steps":["Dice and marinate the chicken for 10 minutes","Stir-fry the dried chilies","Add chicken and cook until lightly browned","Add the sauce and finish cooking"]}
        """
        case .japanese:
            prompt = """
        まず画像を分類し、JSON 形式で返してください。contentKind は dish、ingredient、object、person、scene、unknown のいずれかです。recordKind は foodRecipe、babyMeal、babyDaily、scrapbook のいずれかです。
        幼い子どもが食事中、食べさせてもらっている、食器を使っている、または明確な離乳食・子どもの食事が写っている場合は babyMeal。幼い子どもが写っているが、遊び、睡眠、外出、読書、入浴、親子のふれあいなど食事ではない場合は babyDaily。その他の非食品写真は scrapbook。

        foodRecipe の場合は、次のレシピ項目を返してください：
        - name: 日本語の料理名
        - difficulty: 次のいずれかの値：\(difficultyOptions)
        - cuisine: 次のいずれかの値：\(cuisineOptions)
        - cookingTime: 次のいずれかの値：\(cookingTimeOptions)
        - ingredients: 分量を含む材料の配列。日本語で記述
        - steps: 調理手順の配列。日本語で記述
        - visualDescription: 空文字列
        - visualDescriptionVariants: 空配列

        babyMeal の場合は、短い赤ちゃんごはんのタイトル、null のタグ、食材、やさしい手順を返し、visualDescription は「食事：」「食べた量：」「好き度：」「観察：」の行形式にしてください。見えない内容は「未記入」とし、visualDescriptionVariants は空配列にしてください。

        babyDaily の場合は、短い赤ちゃん日記のタイトルを返し、visualDescription は visualDescriptionVariants の最初の text にしてください。visualDescriptionVariants は style が journal、story、poem の 3 件、title は「手帳」「物語」「小さな詩」にしてください。journal は「場面：」「気分：」「成長メモ：」「今日の一言：」の行形式、story は 4〜6 文の短い物語、poem は 4〜8 行の小さな詩にしてください。見える事実だけを書き、身元、関係、性格、健康、見えない出来事は推測しないでください。ingredients と steps は空配列、タグは null にしてください。

        scrapbook の場合は、name に短いスクラップブック用タイトル、visualDescription は visualDescriptionVariants の最初の text にしてください。visualDescriptionVariants は style が journal、story、poem の 3 件、title は「手帳」「物語」「小さな詩」にしてください。journal は自然で温かい 2〜4 文の情景描写、story は見える画面に基づく 4〜6 文の短い物語、poem は見える画面に基づく 4〜8 行の小さな詩にしてください。人物は見える表情、しぐさ、服装、姿勢、光、雰囲気だけを描写し、個人の特定や見えない属性の推測はしないでください。物は見える外観と「〜のように見える」材質だけを書き、確定できない材質を事実として書かないでください。ingredients と steps は空配列、タグは null にしてください。

        JSON のみを返し、Markdown や説明文は含めないでください。
        """
        }

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

    private func buildNameRequest(recipeName: String) throws -> URLRequest {
        var request = try baseRequest()

        let cuisineOptions = Cuisine.allCases.map { $0.rawValue }.joined(separator: " | ")
        let difficultyOptions = Difficulty.allCases.map { $0.rawValue }.joined(separator: " | ")
        let cookingTimeOptions = CookingTime.allCases.map { $0.rawValue }.joined(separator: " | ")

        let prompt: String
        switch AppLanguage.current {
        case .chinese:
            prompt = """
        用户手动确认这道菜的菜名是「\(recipeName)」。请根据这个菜名重新生成更匹配的菜谱信息，以 JSON 格式返回以下字段：
        - name: 使用用户确认的菜名，必须是「\(recipeName)」
        - difficulty: 难度，必须是以下之一：\(difficultyOptions)
        - cuisine: 菜系，必须是以下之一：\(cuisineOptions)
        - cookingTime: 烹饪时长，必须是以下之一：\(cookingTimeOptions)
        - ingredients: 主要原材料列表（字符串数组，每条包含食材名和用量，如 "鸡胸肉 300g"）
        - steps: 做法步骤列表（字符串数组，有序，每条为一个步骤）

        只返回 JSON，不要其他文字，不要 markdown 代码块。
        示例格式：
        {"name":"\(recipeName)","difficulty":"中等","cuisine":"川菜","cookingTime":"30分钟","ingredients":["鸡胸肉 300g","花生 50g"],"steps":["鸡肉切丁腌制10分钟","热锅炒香干辣椒","加入鸡丁翻炒至变色","加酱汁翻炒出锅"]}
        """
        case .english:
            prompt = """
        The user confirmed that the dish is named "\(recipeName)". Generate matching recipe details as JSON:
        - name: exactly "\(recipeName)"
        - difficulty: must be one of these exact values: \(difficultyOptions)
        - cuisine: must be one of these exact values: \(cuisineOptions)
        - cookingTime: must be one of these exact values: \(cookingTimeOptions)
        - ingredients: an array of ingredients with quantities, written in English
        - steps: an ordered array of cooking instructions, written in English

        Return JSON only, with no markdown or additional text.
        Example:
        {"name":"\(recipeName)","difficulty":"中等","cuisine":"川菜","cookingTime":"30分钟","ingredients":["Chicken breast 300g","Peanuts 50g"],"steps":["Dice and marinate the chicken for 10 minutes","Stir-fry the dried chilies","Add chicken and cook until lightly browned","Add the sauce and finish cooking"]}
        """
        case .japanese:
            prompt = """
        ユーザーが料理名を「\(recipeName)」と確認しました。この料理に合うレシピ情報を JSON 形式で生成してください：
        - name: 必ず「\(recipeName)」
        - difficulty: 次のいずれかの値：\(difficultyOptions)
        - cuisine: 次のいずれかの値：\(cuisineOptions)
        - cookingTime: 次のいずれかの値：\(cookingTimeOptions)
        - ingredients: 分量を含む材料の配列。日本語で記述
        - steps: 調理手順の配列。日本語で記述

        JSON のみを返し、Markdown や説明文は含めないでください。
        """
        }

        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildTranslationRequest(
        content: RecipeLocalizedContent,
        language: AppLanguage
    ) throws -> URLRequest {
        var request = try baseRequest()
        let input: [String: Any] = [
            "name": content.name,
            "notes": content.notes,
            "ingredients": content.ingredients,
            "steps": content.steps
        ]
        let inputData = try JSONSerialization.data(withJSONObject: input)
        let inputJSON = String(data: inputData, encoding: .utf8) ?? "{}"
        let prompt = """
        Translate this recipe into \(language.promptLanguageName).
        Preserve quantities, units, proper nouns, ordering, and meaning. Do not add or remove recipe details.
        Return JSON only with exactly these fields: name (string), notes (string), ingredients (string array), steps (string array).
        Input:
        \(inputJSON)
        """
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseLocalizedContent(data: Data) throws -> RecipeLocalizedContent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let rawContent = (message["content"] as? String)
                ?? (message["reasoning_content"] as? String) else {
            throw RecipeAIError.parseError("Invalid translation response")
        }

        let jsonString = extractJSON(from: rawContent)
        guard let jsonData = jsonString.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let name = info["name"] as? String,
              let ingredients = info["ingredients"] as? [String],
              let steps = info["steps"] as? [String] else {
            throw RecipeAIError.parseError("Failed to parse translated recipe")
        }

        return RecipeLocalizedContent(
            name: name,
            notes: info["notes"] as? String ?? "",
            ingredients: ingredients,
            steps: steps
        )
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

        let contentKind = (info["contentKind"] as? String).flatMap(ImageContentKind.init(rawValue:)) ?? .dish
        let recordKind = (info["recordKind"] as? String).flatMap(RecipeRecordKind.init(rawValue:)) ?? (contentKind.isFoodRelated ? .foodRecipe : .scrapbook)
        let name = info["name"] as? String
        let visualDescription = info["visualDescription"] as? String
        let visualDescriptionVariants = parseDescriptionVariants(
            info["visualDescriptionVariants"],
            fallbackText: visualDescription
        )
        let difficulty = (info["difficulty"] as? String).flatMap { Difficulty(rawValue: $0) }
        let cuisine = (info["cuisine"] as? String).flatMap { Cuisine(rawValue: $0) }
        let cookingTime = (info["cookingTime"] as? String).flatMap { CookingTime(rawValue: $0) }
        let ingredients = info["ingredients"] as? [String] ?? []
        let steps = info["steps"] as? [String] ?? []

        return RecipeAISuggestion(
            contentKind: contentKind,
            recordKind: recordKind,
            name: name,
            visualDescription: visualDescription,
            visualDescriptionVariants: visualDescriptionVariants,
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

    private func parseDescriptionVariants(_ rawValue: Any?, fallbackText: String?) -> [DescriptionVariant] {
        let variants = (rawValue as? [[String: Any]])?.compactMap { item -> DescriptionVariant? in
            guard let text = item["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let styleRawValue = item["style"] as? String ?? DescriptionVariantStyle.journal.rawValue
            let style = DescriptionVariantStyle(rawValue: styleRawValue) ?? .journal
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle: String
            if let title, !title.isEmpty {
                resolvedTitle = title
            } else {
                resolvedTitle = defaultVariantTitle(for: style)
            }
            return DescriptionVariant(
                style: style,
                title: resolvedTitle,
                text: text
            )
        } ?? []

        if !variants.isEmpty {
            return variants
        }

        guard let fallbackText,
              !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [
            DescriptionVariant(
                style: .journal,
                title: defaultVariantTitle(for: .journal),
                text: fallbackText
            )
        ]
    }

    private func defaultVariantTitle(for style: DescriptionVariantStyle) -> String {
        switch AppLanguage.current {
        case .chinese:
            switch style {
            case .journal: return "手帐版"
            case .story: return "故事版"
            case .poem: return "小诗版"
            }
        case .english:
            switch style {
            case .journal: return "Journal"
            case .story: return "Story"
            case .poem: return "Poem"
            }
        case .japanese:
            switch style {
            case .journal: return "手帳"
            case .story: return "物語"
            case .poem: return "小さな詩"
            }
        }
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
