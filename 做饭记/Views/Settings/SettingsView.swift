import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Settings View

/// 设置页：订阅、支持、备份与法律信息等。
struct SettingsView: View {

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    var body: some View {
        NavigationStack {
            List {
                subscriptionSection
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
        }
    }

    // MARK: - Sections

    private var subscriptionSection: some View {
        Section("AI 订阅") {
            NavigationLink {
                SubscriptionView()
            } label: {
                Label("Snap Recipe Plus", systemImage: "sparkles")
            }
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
                Text("What's Cooking")
                Spacer()
                Text("记录每天做的菜")
                    .foregroundStyle(AppTheme.bodyText)
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            ShareLink(
                item: backupDocument,
                subject: Text("菜脯备份"),
                preview: SharePreview("caipu-backup.json")
            ) {
                Label("备份我的菜谱", systemImage: "externaldrive")
            }
            .disabled(recipes.isEmpty)
        }
    }

    private var legalSection: some View {
        Section("法律") {
            Button {
                openURL(SettingsLinks.privacyPolicy)
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            Button {
                openURL(SettingsLinks.terms)
            } label: {
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

    private var backupDocument: RecipeBackupDocument {
        let payload = RecipeBackupPayload(
            appName: "菜脯",
            appVersion: appVersion,
            exportedAt: .now,
            recipes: recipes.map(RecipeBackupItem.init(recipe:))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return RecipeBackupDocument(json: "{}")
        }

        return RecipeBackupDocument(json: json)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - FAQ

private struct FAQView: View {

    var body: some View {
        List {
            FAQRow(
                question: "菜谱数据会同步到云端吗？",
                answer: "不会。菜谱默认保存在设备本地；使用识图功能时，只有你主动选择的图片会用于生成菜谱建议。"
            )

            FAQRow(
                question: "为什么识别结果偶尔不准确？",
                answer: "光线、遮挡、菜品摆放和图片清晰度都会影响识别。你可以在保存前手动修改名称、配料、步骤和备注。"
            )

            FAQRow(
                question: "如何备份我的菜谱？",
                answer: "在设置里的“备份我的菜谱”中分享 JSON 备份文件，可以保存到文件 App、iCloud Drive 或发送给自己。"
            )

            FAQRow(
                question: "如何反馈问题或建议？",
                answer: "在设置里点击 Support and Feedback，会打开邮件并自动带上 App 版本信息。"
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

private enum SettingsLinks {

    private static let appStoreID = ""
    private static let supportAddress = "loyatfei@gmail.com"

    static let privacyPolicy = URL(string: "https://lufi000.github.io/zuofanji-ios/privacy.html")!
    static let terms = URL(string: "https://lufi000.github.io/zuofanji-ios/terms.html")!

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

private struct RecipeBackupDocument: Transferable {

    let json: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { document in
            Data(document.json.utf8)
        }
    }
}

private struct RecipeBackupItem: Codable {

    let name: String
    let date: Date
    let imageBase64: String?
    let cutoutImageBase64: String?
    let notes: String
    let ingredients: [String]
    let steps: [String]
    let difficulty: String?
    let cuisine: String?
    let cookingTime: String?
    let createdAt: Date
    let updatedAt: Date

    init(recipe: Recipe) {
        self.name = recipe.name
        self.date = recipe.date
        self.imageBase64 = recipe.imageData?.base64EncodedString()
        self.cutoutImageBase64 = recipe.cutoutImageData?.base64EncodedString()
        self.notes = recipe.notes
        self.ingredients = recipe.ingredients
        self.steps = recipe.steps
        self.difficulty = recipe.difficultyRawValue
        self.cuisine = recipe.cuisineRawValue
        self.cookingTime = recipe.cookingTimeRawValue
        self.createdAt = recipe.createdAt
        self.updatedAt = recipe.updatedAt
    }
}
