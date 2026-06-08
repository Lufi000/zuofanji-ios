import Foundation
import StoreKit

// MARK: - Subscription Product IDs

enum SubscriptionProductIDs {
    static let monthlyAutoRenewable = "com.lufi000.caipu.plus.monthly"
    static let oneMonthPass = "com.lufi000.caipu.onemonth"
    static let all = [monthlyAutoRenewable, oneMonthPass]
}

// MARK: - AI Quotas

enum AISubscriptionQuota {
    static let monthly = 100
    static let daily = 20
}

// MARK: - AI Subscription Entitlement

enum AISubscriptionAccessError: LocalizedError {
    case subscriptionRequired
    case monthlyQuotaExceeded
    case dailyQuotaExceeded

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return AppLocalization.text("开通 菜脯 Plus 后即可使用 AI 识别。")
        case .monthlyQuotaExceeded:
            return AppLocalization.text("本月 AI 识别额度已用完。额度会在下个订阅周期自动刷新。")
        case .dailyQuotaExceeded:
            return AppLocalization.format(
                "今天的 AI 识别额度已用完。每天最多可使用 %d 次，请明天再试。",
                AISubscriptionQuota.daily
            )
        }
    }
}

// MARK: - Subscription Store

@MainActor
final class SubscriptionStore: ObservableObject {

    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let monthlyAIQuota = AISubscriptionQuota.monthly
    static let dailyAIQuota = AISubscriptionQuota.daily

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var userMessage: String?

    private static let productLoadTimeoutNanoseconds: UInt64 = 8 * 1_000_000_000
    private let defaults = UserDefaults.standard
    private let oneMonthPassExpiresAtKey = "subscription.oneMonthPassExpiresAt"
    private let usageMonthKey = "subscription.aiUsageMonth"
    private let usageCountKey = "subscription.aiUsageCount"
    private let usageDayKey = "subscription.aiUsageDay"
    private let usageDayCountKey = "subscription.aiUsageDayCount"
    private var transactionUpdatesTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    var autoRenewableMonthlyProduct: Product? {
        products.first { $0.id == SubscriptionProductIDs.monthlyAutoRenewable }
    }

    var oneMonthPassProduct: Product? {
        products.first { $0.id == SubscriptionProductIDs.oneMonthPass }
    }

    var hasActiveSubscription: Bool {
        purchasedProductIDs.contains(SubscriptionProductIDs.monthlyAutoRenewable)
    }

    var hasActiveOneMonthPass: Bool {
        guard let expiresAt = oneMonthPassExpiresAt else { return false }
        return expiresAt > Date()
    }

    var hasActiveAIPlan: Bool {
        hasActiveSubscription || hasActiveOneMonthPass
    }

    var oneMonthPassExpiresAt: Date? {
        let timestamp = defaults.double(forKey: oneMonthPassExpiresAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    var usedAIRequestsThisMonth: Int {
        guard defaults.string(forKey: usageMonthKey) == currentMonthString() else { return 0 }
        return defaults.integer(forKey: usageCountKey)
    }

    var remainingAIRequestsThisMonth: Int {
        max(Self.monthlyAIQuota - usedAIRequestsThisMonth, 0)
    }

    var usedAIRequestsToday: Int {
        guard defaults.string(forKey: usageDayKey) == currentDayString() else { return 0 }
        return defaults.integer(forKey: usageDayCountKey)
    }

    var remainingAIRequestsToday: Int {
        max(Self.dailyAIQuota - usedAIRequestsToday, 0)
    }

    init() {
        transactionUpdatesTask = listenForTransactionUpdates()
        Task { await updateCustomerProductStatus() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
        refreshTask?.cancel()
    }

    func refreshProductsAndEntitlements() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performProductsAndEntitlementsRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performProductsAndEntitlementsRefresh() async {
        loadingState = .loading
        userMessage = nil

        do {
            let loadedProducts = try await loadProductsWithTimeout()
            guard !loadedProducts.isEmpty else {
                throw ProductLoadingError.noProducts
            }
            products = loadedProducts.sorted { $0.displayName < $1.displayName }
            await updateCustomerProductStatus()
            loadingState = .loaded
        } catch ProductLoadingError.timedOut {
            loadingState = .failed(AppLocalization.text("载入 App Store 套餐信息超时，请稍后重试"))
        } catch {
            loadingState = .failed(AppLocalization.text("无法从 App Store 载入订阅信息，请检查网络后重试"))
        }
    }

    func purchaseAutoRenewableMonthlySubscription() async {
        await purchase(
            productID: SubscriptionProductIDs.monthlyAutoRenewable,
            initialProduct: autoRenewableMonthlyProduct,
            missingProductMessage: AppLocalization.text("连续包月订阅信息暂时不可用，请稍后重试")
        )
    }

    func purchaseOneMonthPass() async {
        await purchase(
            productID: SubscriptionProductIDs.oneMonthPass,
            initialProduct: oneMonthPassProduct,
            missingProductMessage: AppLocalization.text("单月套餐信息暂时不可用，请稍后重试")
        )
    }

    private func purchase(productID: String, initialProduct: Product?, missingProductMessage: String) async {
        var product = initialProduct
        if product == nil {
            await refreshProductsAndEntitlements()
            product = products.first { $0.id == productID }
        }

        guard let product else {
            userMessage = missingProductMessage
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                if transaction.productID == SubscriptionProductIDs.oneMonthPass {
                    activateOneMonthPass(from: transaction.purchaseDate)
                }
                await updateCustomerProductStatus()
                await transaction.finish()
                userMessage = AppLocalization.text("菜脯 Plus 已启用")
            case .userCancelled:
                break
            case .pending:
                userMessage = AppLocalization.text("购买正在等待确认")
            @unknown default:
                userMessage = AppLocalization.text("购买状态暂时无法确认")
            }
        } catch StoreError.failedVerification {
            userMessage = AppLocalization.text("购买验证失败，请稍后再试")
        } catch {
            if let message = purchaseErrorMessage(for: error) {
                userMessage = message
            }
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateCustomerProductStatus()
            await restoreOneMonthPassFromTransactionHistory()
            userMessage = hasActiveAIPlan
                ? AppLocalization.text("菜脯 Plus 已恢复")
                : AppLocalization.text("没有找到可恢复的套餐")
        } catch {
            userMessage = AppLocalization.text("暂时无法连接 App Store 恢复购买，请稍后再试")
        }
    }

    func validateAIRequestAccess() throws {
        guard hasActiveAIPlan else {
            throw AISubscriptionAccessError.subscriptionRequired
        }
        guard remainingAIRequestsThisMonth > 0 else {
            throw AISubscriptionAccessError.monthlyQuotaExceeded
        }
        guard remainingAIRequestsToday > 0 else {
            throw AISubscriptionAccessError.dailyQuotaExceeded
        }
    }

    func recordSuccessfulAIRequest() {
        let month = currentMonthString()
        let monthCount = defaults.string(forKey: usageMonthKey) == month
            ? defaults.integer(forKey: usageCountKey) + 1
            : 1
        defaults.set(month, forKey: usageMonthKey)
        defaults.set(monthCount, forKey: usageCountKey)

        let day = currentDayString()
        let dayCount = defaults.string(forKey: usageDayKey) == day
            ? defaults.integer(forKey: usageDayCountKey) + 1
            : 1
        defaults.set(day, forKey: usageDayKey)
        defaults.set(dayCount, forKey: usageDayCountKey)
        objectWillChange.send()
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { break }

                do {
                    let transaction = try self.checkVerified(verification)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    await MainActor.run {
                        self.userMessage = AppLocalization.text("订阅状态验证失败")
                    }
                }
            }
        }
    }

    private func updateCustomerProductStatus() async {
        var activeProductIDs = Set<String>()

        for await verification in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(verification),
                  SubscriptionProductIDs.all.contains(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }

            if transaction.productID == SubscriptionProductIDs.oneMonthPass {
                activateOneMonthPass(from: transaction.purchaseDate)
            } else {
                activeProductIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeProductIDs
    }

    private func loadProductsWithTimeout() async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask {
                try await Product.products(for: SubscriptionProductIDs.all)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: Self.productLoadTimeoutNanoseconds)
                throw ProductLoadingError.timedOut
            }

            guard let products = try await group.next() else {
                throw ProductLoadingError.noResult
            }
            group.cancelAll()
            return products
        }
    }

    private func restoreOneMonthPassFromTransactionHistory() async {
        for await verification in Transaction.all {
            guard let transaction = try? checkVerified(verification),
                  transaction.productID == SubscriptionProductIDs.oneMonthPass,
                  transaction.revocationDate == nil else {
                continue
            }
            activateOneMonthPass(from: transaction.purchaseDate)
        }
    }

    private func activateOneMonthPass(from purchaseDate: Date) {
        let expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: purchaseDate) ?? purchaseDate.addingTimeInterval(30 * 24 * 60 * 60)
        let currentExpiry = oneMonthPassExpiresAt ?? .distantPast
        if expiresAt > currentExpiry {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: oneMonthPassExpiresAtKey)
            objectWillChange.send()
        }
    }

    private func currentMonthString(in calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: Date())
        guard let year = comps.year, let month = comps.month else { return "" }
        return String(format: "%04d-%02d", year, month)
    }

    private func currentDayString(in calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func purchaseErrorMessage(for error: Error) -> String? {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .userCancelled:
                return nil
            case .networkError:
                return AppLocalization.text("网络连接不稳定，暂时无法连接 App Store，请稍后再试")
            case .notAvailableInStorefront:
                return AppLocalization.text("当前地区暂不支持购买此套餐")
            case .notEntitled:
                return AppLocalization.text("当前 Apple ID 暂时无法购买此套餐")
            default:
                return AppLocalization.text("暂时无法完成购买，请稍后再试")
            }
        }

        return AppLocalization.text("暂时无法完成购买，请稍后再试")
    }
}

private enum StoreError: Error {
    case failedVerification
}

private enum ProductLoadingError: Error {
    case timedOut
    case noResult
    case noProducts
}
