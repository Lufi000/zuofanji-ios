import SwiftUI
import SwiftData
import UIKit

// MARK: - Add Recipe ViewModel

/// 新增/编辑菜谱的表单状态与业务逻辑。
/// 职责：管理表单字段、输入校验、调用 AI 服务、保存到 SwiftData。
@Observable
@MainActor
final class AddRecipeViewModel {

    // MARK: Form Fields

    var name: String = ""
    var date: Date = .now
    var imageData: Data?
    /// 抠图 PNG（透明背景），从 ScanResultContainer 传入
    var cutoutImageData: Data?
    var notes: String = ""
    var ingredients: [String] = []
    var steps: [String] = []
    var difficulty: Difficulty?
    var cuisine: Cuisine?
    var cookingTime: CookingTime?

    // MARK: AI State

    var isAILoading: Bool = false
    var aiError: String?

    // MARK: Validation

    /// 仅照片为必填项，其余均为可选
    var isValid: Bool {
        imageData != nil
    }

    // MARK: AI Action

    /// 调用 AI 识别当前图片，将结果填入表单（只覆盖空字段）
    func analyzeImage() async {
        guard let data = imageData, let image = UIImage(data: data) else { return }
        isAILoading = true
        aiError = nil
        defer { isAILoading = false }

        do {
            let suggestion = try await RecipeAIService().analyze(image: image)
            applyAISuggestion(suggestion)
        } catch {
            aiError = (error as? RecipeAIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 将 AI 建议写入表单，已有内容不覆盖
    func applyAISuggestion(_ suggestion: RecipeAISuggestion) {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedName = suggestion.name {
            name = suggestedName
        }
        if difficulty == nil { difficulty = suggestion.difficulty }
        if cuisine == nil { cuisine = suggestion.cuisine }
        if cookingTime == nil { cookingTime = suggestion.cookingTime }
        if ingredients.isEmpty { ingredients = suggestion.ingredients }
        if steps.isEmpty { steps = suggestion.steps }
    }

    // MARK: CRUD Actions

    /// 保存新菜谱到 SwiftData
    func save(in context: ModelContext) {
        let recipe = Recipe(
            name: resolvedName,
            date: date,
            imageData: imageData,
            cutoutImageData: cutoutImageData,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: ingredients,
            steps: steps,
            difficulty: difficulty,
            cuisine: cuisine,
            cookingTime: cookingTime
        )
        context.insert(recipe)
        do {
            try context.save()
            print("[Recipe] Saved: \(recipe.name), ingredients: \(recipe.ingredients.count), steps: \(recipe.steps.count)")
        } catch {
            print("[Recipe] Save failed: \(error)")
        }
    }

    /// 用已有菜谱填充表单（编辑模式）
    func populate(from recipe: Recipe) {
        name = recipe.name
        date = recipe.date
        imageData = recipe.imageData
        cutoutImageData = recipe.cutoutImageData
        notes = recipe.notes
        ingredients = recipe.ingredients
        steps = recipe.steps
        difficulty = recipe.difficulty
        cuisine = recipe.cuisine
        cookingTime = recipe.cookingTime
    }

    /// 更新已有菜谱
    func update(_ recipe: Recipe) {
        recipe.name = resolvedName
        recipe.date = date
        recipe.imageData = imageData
        recipe.cutoutImageData = cutoutImageData
        recipe.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.ingredients = ingredients
        recipe.steps = steps
        recipe.difficulty = difficulty
        recipe.cuisine = cuisine
        recipe.cookingTime = cookingTime
        recipe.updatedAt = .now
    }

    // MARK: - Private

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "未命名 \(date.formatted(.dateTime.month(.wide).day().year()))"
    }
}
