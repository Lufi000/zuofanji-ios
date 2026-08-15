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
    var recordKind: RecipeRecordKind = .foodRecipe
    var difficulty: Difficulty?
    var cuisine: Cuisine?
    var cookingTime: CookingTime?
    var descriptionVariants: [DescriptionVariant] = []
    var selectedDescriptionVariantID: DescriptionVariant.ID?
    var pendingDescriptionVariantID: DescriptionVariant.ID?
    var hasResolvedContentStructure = false

    // MARK: AI State

    var isAILoading: Bool = false
    var isSaving: Bool = false
    var aiError: String?
    var shouldShowSubscriptionPrompt: Bool = false

    private var originalRecipeName: String?

    // MARK: Validation

    /// 仅照片为必填项，其余均为可选
    var isValid: Bool {
        imageData != nil
    }

    /// 编辑模式下，菜名变化会触发原材料和做法的重新生成。
    var shouldRefreshDetailsForRenamedRecipe: Bool {
        hasResolvedContentStructure && hasRenamedRecipe && recordKind == .foodRecipe
    }

    var shouldShowRecipeDetails: Bool {
        hasResolvedContentStructure && recordKind.isFoodRelated
    }

    var shouldShowRecipeTags: Bool {
        recordKind == .foodRecipe
    }

    var shouldShowScrapbookDescription: Bool {
        !hasResolvedContentStructure || !recordKind.isFoodRelated || recordKind.isBabyRecord
    }

    var selectedDescriptionVariant: DescriptionVariant? {
        guard let selectedDescriptionVariantID else {
            return descriptionVariants.first
        }
        return descriptionVariants.first { $0.id == selectedDescriptionVariantID } ?? descriptionVariants.first
    }

    var shouldConfirmDescriptionReplacement: Bool {
        pendingDescriptionVariantID != nil
    }

    // MARK: AI Action

    /// 调用 AI 识别当前图片，并同步刷新透明背景抠图。
    func analyzeImage(subscriptionStore: SubscriptionStore) async {
        guard let data = imageData, let image = UIImage(data: data) else { return }
        isAILoading = true
        aiError = nil
        shouldShowSubscriptionPrompt = false
        hasResolvedContentStructure = false
        defer { isAILoading = false }

        let cutoutTask = Task.detached(priority: .userInitiated) {
            let service = ImageCutoutService()
            service.featherRadius = 1.5
            service.edgeErosionRadius = 1.0
            return await service.extractForeground(from: image)
        }

        do {
            try subscriptionStore.validateAIRequestAccess()
            let suggestion = try await RecipeAIService().analyze(image: image)
            subscriptionStore.recordSuccessfulAIRequest()
            applyAISuggestion(suggestion)
        } catch {
            shouldShowSubscriptionPrompt = !subscriptionStore.hasActiveAIPlan && error is AISubscriptionAccessError
            aiError = (error as? RecipeAIError)?.errorDescription ?? error.localizedDescription
        }

        if let cutoutImage = await cutoutTask.value,
           let pngData = cutoutImage.pngData() {
            cutoutImageData = pngData
        }
    }

    /// 将 AI 建议写入表单，已有内容不覆盖
    func applyAISuggestion(_ suggestion: RecipeAISuggestion) {
        recordKind = suggestion.recordKind
        hasResolvedContentStructure = true
        descriptionVariants = suggestion.visualDescriptionVariants
        selectedDescriptionVariantID = descriptionVariants.first?.id
        pendingDescriptionVariantID = nil

        guard suggestion.recordKind.isFoodRelated else {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggestedName = suggestion.name {
                name = suggestedName
            }
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let description = selectedDescriptionVariant?.text ?? suggestion.visualDescription {
                notes = description
            }
            return
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedName = suggestion.name {
            name = suggestedName
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let description = suggestion.visualDescription {
            notes = description
        }
        if difficulty == nil { difficulty = suggestion.difficulty }
        if cuisine == nil { cuisine = suggestion.cuisine }
        if cookingTime == nil { cookingTime = suggestion.cookingTime }
        if ingredients.isEmpty { ingredients = suggestion.ingredients }
        if steps.isEmpty { steps = suggestion.steps }
    }

    func selectDescriptionVariant(_ variant: DescriptionVariant) {
        guard variant.id != selectedDescriptionVariantID else { return }
        if shouldReplaceDescriptionImmediately {
            applyDescriptionVariant(variant)
        } else {
            pendingDescriptionVariantID = variant.id
        }
    }

    func confirmPendingDescriptionVariantReplacement() {
        guard let pendingDescriptionVariantID,
              let variant = descriptionVariants.first(where: { $0.id == pendingDescriptionVariantID }) else {
            self.pendingDescriptionVariantID = nil
            return
        }
        applyDescriptionVariant(variant)
    }

    func cancelPendingDescriptionVariantReplacement() {
        pendingDescriptionVariantID = nil
    }

    /// 用户在编辑模式手动改菜名后，用新菜名重新生成原材料和做法。
    func refreshRecipeDetailsForRenamedRecipeIfNeeded(subscriptionStore: SubscriptionStore) async throws {
        guard hasRenamedRecipe else { return }

        try subscriptionStore.validateAIRequestAccess()
        let suggestion = try await RecipeAIService().suggestRecipe(named: resolvedName)
        subscriptionStore.recordSuccessfulAIRequest()
        if !suggestion.ingredients.isEmpty {
            ingredients = suggestion.ingredients
        }
        if !suggestion.steps.isEmpty {
            steps = suggestion.steps
        }
        difficulty = suggestion.difficulty ?? difficulty
        cuisine = suggestion.cuisine ?? cuisine
        cookingTime = suggestion.cookingTime ?? cookingTime
    }

    // MARK: CRUD Actions

    /// 保存新菜谱到 SwiftData
    func save(in context: ModelContext) throws {
        let recipe = Recipe(
            name: resolvedName,
            date: date,
            imageData: imageData,
            cutoutImageData: cutoutImageData,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: ingredients,
            steps: steps,
            recordKind: recordKind,
            difficulty: difficulty,
            cuisine: cuisine,
            cookingTime: cookingTime
        )
        recipe.setCurrentContentLanguage(AppLanguage.current)
        context.insert(recipe)
        do {
            try context.save()
            print("[Recipe] Saved: \(recipe.name), ingredients: \(recipe.ingredients.count), steps: \(recipe.steps.count)")
        } catch {
            context.delete(recipe)
            print("[Recipe] Save failed: \(error)")
            throw error
        }
    }

    /// 用已有菜谱填充表单（编辑模式）
    func populate(from recipe: Recipe) {
        let content = recipe.content(for: AppLanguage.current)
        name = content.name
        originalRecipeName = content.name
        date = recipe.date
        imageData = recipe.imageData
        cutoutImageData = recipe.cutoutImageData
        notes = content.notes
        ingredients = content.ingredients
        steps = content.steps
        recordKind = recipe.recordKind
        hasResolvedContentStructure = true
        difficulty = recipe.difficulty
        cuisine = recipe.cuisine
        cookingTime = recipe.cookingTime
        descriptionVariants = []
        selectedDescriptionVariantID = nil
        pendingDescriptionVariantID = nil
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
        recipe.recordKind = recordKind
        recipe.setCurrentContentLanguage(AppLanguage.current)
        recipe.difficulty = difficulty
        recipe.cuisine = cuisine
        recipe.cookingTime = cookingTime
        recipe.updatedAt = .now
    }

    // MARK: - Private

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return AppLocalization.format(
            "未命名 %@",
            date.formatted(.dateTime.month(.wide).day().year())
        )
    }

    private var hasRenamedRecipe: Bool {
        guard let originalRecipeName else { return false }
        return originalRecipeName.trimmingCharacters(in: .whitespacesAndNewlines) != resolvedName
    }

    private var shouldReplaceDescriptionImmediately: Bool {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else { return true }
        return descriptionVariants.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedNotes }
    }

    private func applyDescriptionVariant(_ variant: DescriptionVariant) {
        selectedDescriptionVariantID = variant.id
        notes = variant.text
        pendingDescriptionVariantID = nil
    }
}
