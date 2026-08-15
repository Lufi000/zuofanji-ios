import StoreKit
import SwiftUI

// MARK: - Subscription View

struct SubscriptionView: View {

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var selectedPlanID = SubscriptionProductIDs.monthlyAutoRenewable
    @State private var purchasingProductID: String?
    @State private var isRestoring = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                quotaCard
                benefitsCard
                planPicker
                purchaseButton
                restoreButton
                legalLinks
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("菜脯 Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if subscriptionStore.products.isEmpty {
                await subscriptionStore.refreshProductsAndEntitlements()
            }
        }
        .alert("提示", isPresented: messageBinding) {
            Button("好的", role: .cancel) {
                subscriptionStore.userMessage = nil
            }
        } message: {
            Text(subscriptionStore.userMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: subscriptionStore.hasActiveSubscription ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(AppLocalization.text(subscriptionStore.hasActiveAIPlan ? "Plus 已启用" : "选择 菜脯 Plus 套餐"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.titleText)

            Text(AppLocalization.format(
                "免费用户每月可用 %d 次、每天最多 %d 次 AI 识别。开通 菜脯 Plus 后，每月可用 %d 次、每天最多 %d 次；连续包月更优惠，新用户可享前三天免费试用，单月套餐不自动续订。",
                SubscriptionStore.freeMonthlyAIQuota,
                SubscriptionStore.freeDailyAIQuota,
                SubscriptionStore.plusMonthlyAIQuota,
                SubscriptionStore.plusDailyAIQuota
            ))
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本月 AI 额度", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)
                Spacer()
                Text("\(subscriptionStore.remainingAIRequestsThisMonth)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.accent)
            }

            ProgressView(
                value: Double(subscriptionStore.usedAIRequestsThisMonth),
                total: Double(subscriptionStore.currentMonthlyAIQuota)
            )
            .tint(AppTheme.accent)

            Text(monthlyQuotaDescription)
                .font(.footnote)
                .foregroundStyle(AppTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("今日剩余")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Text("\(subscriptionStore.remainingAIRequestsToday) / \(subscriptionStore.currentDailyAIQuota)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.titleText)
            }

            if let expiresAt = subscriptionStore.oneMonthPassExpiresAt,
               subscriptionStore.hasActiveOneMonthPass,
               !subscriptionStore.hasActiveSubscription {
                Text("单月套餐有效至 \(expiresAt.formatted(.dateTime.year().month().day()))。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("camera.viewfinder", AppLocalization.text("拍照识别菜品、食材和做法"))
            benefitRow("text.badge.checkmark", AppLocalization.text("根据菜名重新生成原材料和步骤"))
            benefitRow(
                "gift",
                AppLocalization.format(
                    "免费用户每天 %d 次、每月 %d 次",
                    SubscriptionStore.freeDailyAIQuota,
                    SubscriptionStore.freeMonthlyAIQuota
                )
            )
            benefitRow("arrow.clockwise", AppLocalization.text("连续包月自动续订，单月套餐到期后手动续费"))
            benefitRow(
                "clock",
                AppLocalization.format(
                    "Plus 每天最多 %d 次，保障稳定服务",
                    SubscriptionStore.plusDailyAIQuota
                )
            )
            benefitRow("icloud", AppLocalization.text("云端 AI 推理服务由我们持续维护"))
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func benefitRow(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.titleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthlyQuotaDescription: String {
        if subscriptionStore.hasActiveAIPlan {
            return AppLocalization.format(
                "已用 %d 次，订阅有效期内下个账单周期自动恢复到 %d 次。",
                subscriptionStore.usedAIRequestsThisMonth,
                subscriptionStore.currentMonthlyAIQuota
            )
        }
        return AppLocalization.format(
            "已用 %d 次，免费额度每月恢复到 %d 次；开通 Plus 后可提升到 %d 次。",
            subscriptionStore.usedAIRequestsThisMonth,
            subscriptionStore.currentMonthlyAIQuota,
            SubscriptionStore.plusMonthlyAIQuota
        )
    }

    private var planPicker: some View {
        VStack(spacing: 12) {
            planOption(
                title: AppLocalization.text("连续包月（自动续订）"),
                subtitle: AppLocalization.text("新用户前三天免费试用，之后每月自动续订，可随时在 App Store 管理"),
                fallbackPrice: AppLocalization.text("¥12 / 月"),
                billingPeriodText: AppLocalization.text("订阅周期：1 个月"),
                product: subscriptionStore.autoRenewableMonthlyProduct,
                productID: SubscriptionProductIDs.monthlyAutoRenewable,
                isActive: subscriptionStore.hasActiveSubscription,
                badge: AppLocalization.text("推荐")
            )

            planOption(
                title: AppLocalization.text("单月套餐"),
                subtitle: AppLocalization.text("单月有效，不自动续订"),
                fallbackPrice: AppLocalization.text("¥18 / 月"),
                billingPeriodText: AppLocalization.text("有效期：1 个月"),
                product: subscriptionStore.oneMonthPassProduct,
                productID: SubscriptionProductIDs.oneMonthPass,
                isActive: subscriptionStore.hasActiveOneMonthPass && !subscriptionStore.hasActiveSubscription,
                badge: nil
            )
        }
    }

    private func planOption(
        title: String,
        subtitle: String,
        fallbackPrice: String,
        billingPeriodText: String,
        product: Product?,
        productID: String,
        isActive: Bool,
        badge: String?
    ) -> some View {
        Button {
            selectedPlanID = productID
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(product?.displayName ?? title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.titleText)

                        if isActive {
                            Text("已启用")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(product?.displayPrice ?? fallbackPrice)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.titleText)

                    Text(billingPeriodText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: selectedPlanID == productID ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedPlanID == productID ? AppTheme.accent : AppTheme.bodyText.opacity(0.45))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(selectedPlanID == productID ? AppTheme.accent.opacity(0.10) : AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedPlanID == productID ? AppTheme.accent : AppTheme.separator, lineWidth: selectedPlanID == productID ? 1.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent, in: Capsule())
                        .offset(x: -12, y: -10)
                }
            }
            .padding(.top, badge == nil ? 0 : 10)
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            if case .loading = subscriptionStore.loadingState {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在从 App Store 获取套餐价格")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.bodyText)
                }
            } else if case .idle = subscriptionStore.loadingState {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在准备套餐信息")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.bodyText)
                }
            } else if case .failed(let message) = subscriptionStore.loadingState {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accentRed)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("重新载入") {
                        Task { await subscriptionStore.refreshProductsAndEntitlements() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Button {
                Task {
                    purchasingProductID = selectedPlanID
                    if selectedPlanID == SubscriptionProductIDs.monthlyAutoRenewable {
                        await subscriptionStore.purchaseAutoRenewableMonthlySubscription()
                    } else {
                        await subscriptionStore.purchaseOneMonthPass()
                    }
                    purchasingProductID = nil
                }
            } label: {
                HStack {
                    if purchasingProductID != nil {
                        ProgressView()
                    }
                    Text(selectedPlanButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(purchasingProductID != nil || selectedPlanIsActive)
        }
    }

    private var selectedProduct: Product? {
        selectedPlanID == SubscriptionProductIDs.monthlyAutoRenewable
            ? subscriptionStore.autoRenewableMonthlyProduct
            : subscriptionStore.oneMonthPassProduct
    }

    private var selectedPlanIsActive: Bool {
        selectedPlanID == SubscriptionProductIDs.monthlyAutoRenewable
            ? subscriptionStore.hasActiveSubscription
            : subscriptionStore.hasActiveOneMonthPass && !subscriptionStore.hasActiveSubscription
    }

    private var canPurchaseSelectedPlan: Bool {
        guard selectedProduct != nil else { return false }
        if case .loaded = subscriptionStore.loadingState {
            return true
        }
        return false
    }

    private var selectedPlanButtonTitle: String {
        if selectedPlanIsActive {
            return AppLocalization.text("已启用")
        }
        if purchasingProductID != nil {
            return AppLocalization.text("正在处理")
        }
        if selectedProduct == nil {
            return AppLocalization.text("套餐暂不可用")
        }
        if !canPurchaseSelectedPlan {
            return AppLocalization.text("正在载入套餐")
        }
        return AppLocalization.text("订阅")
    }

    private var restoreButton: some View {
        Button {
            Task {
                isRestoring = true
                await subscriptionStore.restorePurchases()
                isRestoring = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRestoring {
                    ProgressView()
                }
                Text("恢复购买")
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.bodyText)
        .disabled(isRestoring)
    }

    private var legalLinks: some View {
        VStack(spacing: 8) {
            Text("订阅将通过 Apple ID 扣款，并按所选周期自动续订；你可以随时在 App Store 订阅管理中取消。")
                .font(.footnote)
                .foregroundStyle(AppTheme.bodyText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: SettingsLinks.privacyPolicy)
                Link("Terms of Use (EULA)", destination: SettingsLinks.terms)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.top, 2)
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { subscriptionStore.userMessage != nil },
            set: { isPresented in
                if !isPresented {
                    subscriptionStore.userMessage = nil
                }
            }
        )
    }
}
