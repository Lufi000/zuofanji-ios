import SwiftUI
import SwiftData
import UIKit

// MARK: - Settings View

/// 设置页：订阅、支持、备份与法律信息等。
struct SettingsView: View {

    var onDone: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppearancePreference.storageKey) private var appearancePreferenceRawValue = AppearancePreference.defaultRawValue
    @AppStorage(StickerEffectStyle.storageKey) private var stickerEffectStyleRawValue = StickerEffectStyle.defaultRawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.current.rawValue
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var isTranslatingRecipes = false
    @State private var translationProgress = 0
    @State private var translationTotal = 0
    @State private var translationError: String?
    @State private var backupShareItem: BackupShareItem?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            List {
                subscriptionSection
                languageSection
                appearanceSection
                stickerEffectSection
                supportSection
                dataSection
                legalSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("设置")
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { onDone() }
                    }
                }
            }
            .alert("菜谱翻译失败", isPresented: translationErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(translationError ?? "")
            }
            .alert("备份失败", isPresented: backupErrorPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(backupError ?? "")
            }
            .sheet(item: $backupShareItem) { item in
                ActivityShareSheet(activityItems: [item.url])
            }
        }
    }

    // MARK: - Sections

    private var subscriptionSection: some View {
        Section("AI 订阅") {
            NavigationLink {
                SubscriptionView()
            } label: {
                Label("菜脯 Plus", systemImage: "sparkles")
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearancePreferenceRawValue) {
                ForEach(AppearancePreference.displayOrder) { preference in
                    Text(preference.title)
                        .tag(preference.rawValue)
                }
            } label: {
                Label("外观选择", systemImage: "paintpalette")
            }
        } footer: {
            Text(currentAppearancePreference.description)
        }
    }

    private var stickerEffectSection: some View {
        Section {
            Picker(selection: $stickerEffectStyleRawValue) {
                ForEach(StickerEffectStyle.displayOrder) { style in
                    Text(style.title)
                        .tag(style.rawValue)
                }
            } label: {
                Label("贴纸效果", systemImage: "wand.and.stars")
            }
        } footer: {
            Text(currentStickerEffectStyle.description)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $languageRawValue) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName)
                        .tag(language.rawValue)
                }
            } label: {
                Label("语言", systemImage: "globe")
            }
            .disabled(isTranslatingRecipes)
            .onChange(of: languageRawValue) { oldValue, newValue in
                guard oldValue != newValue,
                      let language = AppLanguage(rawValue: newValue) else { return }
                Task {
                    await translateRecipesIfNeeded(to: language)
                }
            }

            if isTranslatingRecipes {
                ProgressView(
                    value: Double(translationProgress),
                    total: Double(max(translationTotal, 1))
                ) {
                    Text("正在翻译菜谱")
                } currentValueLabel: {
                    Text("\(translationProgress) / \(translationTotal)")
                }
            }
        } header: {
            Text("显示语言")
        } footer: {
            Text("切换语言后，界面和已有菜谱都会显示为所选语言。首次切换时需要联网翻译菜谱。")
        }
    }

    private var supportSection: some View {
        Section("支持") {
            Button {
                rateApp()
            } label: {
                Label("给菜脯评分", systemImage: "star")
            }

            Button {
                openURL(SettingsLinks.supportEmail)
            } label: {
                Label("Support and Feedback", systemImage: "envelope")
            }

            NavigationLink {
                FAQView()
            } label: {
                Label("FAQ", systemImage: "questionmark.circle")
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(AppTheme.bodyText)
            }

            HStack {
                Text("菜脯")
                Spacer()
                Text("记录每天做的菜")
                    .foregroundStyle(AppTheme.bodyText)
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            Button {
                createBackupShareItem()
            } label: {
                Label("备份我的菜谱", systemImage: "externaldrive")
            }
            .disabled(recipes.isEmpty)
        }
    }

    private var legalSection: some View {
        Section("法律") {
            Link(destination: SettingsLinks.privacyPolicy) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            Link(destination: SettingsLinks.terms) {
                Label("Terms", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Helpers

    private func rateApp() {
        if let appStoreReviewURL = SettingsLinks.appStoreReviewURL {
            openURL(appStoreReviewURL)
        } else {
            requestReview()
        }
    }

    private func createBackupShareItem() {
        let payload = RecipeBackupPayload(
            appName: "菜脯",
            appVersion: appVersion,
            exportedAt: .now,
            recipes: recipes.map(RecipeBackupItem.init(recipe:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("caipu-backup-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url, options: .atomic)
            backupShareItem = BackupShareItem(url: url)
        } catch {
            backupError = AppLocalization.format("备份失败：%@", error.localizedDescription)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var currentAppearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRawValue) ?? .defaultPreference
    }

    private var currentStickerEffectStyle: StickerEffectStyle {
        StickerEffectStyle(rawValue: stickerEffectStyleRawValue) ?? .defaultStyle
    }

    private var translationErrorPresented: Binding<Bool> {
        Binding(
            get: { translationError != nil },
            set: { if !$0 { translationError = nil } }
        )
    }

    private var backupErrorPresented: Binding<Bool> {
        Binding(
            get: { backupError != nil },
            set: { if !$0 { backupError = nil } }
        )
    }

    @MainActor
    private func translateRecipesIfNeeded(to language: AppLanguage) async {
        let pendingRecipes = recipes.filter { !$0.hasLocalizedContent(for: language) }
        guard !pendingRecipes.isEmpty else { return }

        isTranslatingRecipes = true
        translationProgress = 0
        translationTotal = pendingRecipes.count
        translationError = nil
        defer { isTranslatingRecipes = false }

        let service = RecipeAIService()
        for recipe in pendingRecipes {
            do {
                let sourceLanguage = recipe.sourceLanguage
                let sourceContent = recipe.content(for: sourceLanguage)
                if recipe.sourceLanguageRawValue == nil {
                    recipe.sourceLanguageRawValue = sourceLanguage.rawValue
                    recipe.setLocalizedContent(sourceContent, for: sourceLanguage)
                }
                let translated = try await service.translate(
                    content: sourceContent,
                    to: language
                )
                recipe.setLocalizedContent(translated, for: language)
                recipe.updatedAt = .now
                try modelContext.save()
                translationProgress += 1
            } catch {
                translationError = error.localizedDescription
                return
            }
        }
    }
}

// MARK: - FAQ

private struct FAQView: View {

    var body: some View {
        List {
            FAQRow(
                question: AppLocalization.text("菜谱数据会同步到云端吗？"),
                answer: AppLocalization.text("不会。菜谱默认保存在设备本地；使用识图功能时，只有你主动选择的图片会用于生成菜谱建议。")
            )

            FAQRow(
                question: AppLocalization.text("为什么识别结果偶尔不准确？"),
                answer: AppLocalization.text("光线、遮挡、菜品摆放和图片清晰度都会影响识别。你可以在保存前手动修改名称、配料、步骤和备注。")
            )

            FAQRow(
                question: AppLocalization.text("如何备份我的菜谱？"),
                answer: AppLocalization.text("在设置里的“备份我的菜谱”中分享 JSON 备份文件，可以保存到文件 App、iCloud Drive 或发送给自己。")
            )

            FAQRow(
                question: AppLocalization.text("如何反馈问题或建议？"),
                answer: AppLocalization.text("在设置里点击 Support and Feedback，会打开邮件并自动带上 App 版本信息。")
            )
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("FAQ")
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct FAQRow: View {

    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.headline)
                .foregroundStyle(AppTheme.titleText)

            Text(answer)
                .font(.body)
                .foregroundStyle(AppTheme.bodyText)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Links

enum SettingsLinks {

    private static let appStoreID = ""
    private static let supportAddress = "loyatfei@gmail.com"

    static let privacyPolicy = URL(string: "https://api.smallbeebee.com/caipu/privacy")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var appStoreReviewURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    static var supportEmail: URL {
        let subject = "菜脯 Support and Feedback"
        let body = """


        ---
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))
        """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        return URL(string: "mailto:\(supportAddress)?subject=\(encodedSubject)&body=\(encodedBody)")!
    }
}

// MARK: - Backup

private struct RecipeBackupPayload: Codable {

    let appName: String
    let appVersion: String
    let exportedAt: Date
    let recipes: [RecipeBackupItem]
}

private struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct RecipeBackupItem: Codable {

    let name: String
    let date: Date
    let imageBase64: String?
    let cutoutImageBase64: String?
    let notes: String
    let ingredients: [String]
    let steps: [String]
    let recordKind: String?
    let difficulty: String?
    let cuisine: String?
    let cookingTime: String?
    let createdAt: Date
    let updatedAt: Date

    init(recipe: Recipe) {
        let content = recipe.localizedContent
        self.name = content.name
        self.date = recipe.date
        self.imageBase64 = recipe.imageData?.base64EncodedString()
        self.cutoutImageBase64 = recipe.cutoutImageData?.base64EncodedString()
        self.notes = content.notes
        self.ingredients = content.ingredients
        self.steps = content.steps
        self.recordKind = recipe.recordKindRawValue
        self.difficulty = recipe.difficultyRawValue
        self.cuisine = recipe.cuisineRawValue
        self.cookingTime = recipe.cookingTimeRawValue
        self.createdAt = recipe.createdAt
        self.updatedAt = recipe.updatedAt
    }
}
