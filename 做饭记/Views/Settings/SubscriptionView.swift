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
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Snap Recipe Plus")
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

            Text(subscriptionStore.hasActiveAIPlan ? "Plus 已启用" : "选择 Snap Recipe Plus 套餐")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.titleText)

            Text("持续使用云端 AI 菜谱识别服务。连续包月更优惠，新用户可享前三天免费试用；单月套餐不自动续订。两种套餐都包含每月 \(SubscriptionStore.monthlyAIQuota) 次、每天最多 \(SubscriptionStore.dailyAIQuota) 次 AI 识别。")
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
                total: Double(SubscriptionStore.monthlyAIQuota)
            )
            .tint(AppTheme.accent)

            Text("已用 \(subscriptionStore.usedAIRequestsThisMonth) 次，订阅有效期内下个账单周期自动恢复到 \(SubscriptionStore.monthlyAIQuota) 次。")
                .font(.footnote)
                .foregroundStyle(AppTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("今日剩余")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.bodyText)
                Spacer()
                Text("\(subscriptionStore.remainingAIRequestsToday) / \(SubscriptionStore.dailyAIQuota)")
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
            benefitRow("camera.viewfinder", "拍照识别菜品、食材和做法")
            benefitRow("text.badge.checkmark", "根据菜名重新生成原材料和步骤")
            benefitRow("arrow.clockwise", "连续包月自动续订，单月套餐到期后手动续费")
            benefitRow("clock", "每天最多 \(SubscriptionStore.dailyAIQuota) 次，保障稳定服务")
            benefitRow("icloud", "云端 AI 推理服务由我们持续维护")
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

    private var planPicker: some View {
        VStack(spacing: 12) {
            planOption(
                title: "连续包月",
                subtitle: "新用户前三天免费试用，之后每月自动续订，可随时在 App Store 管理",
                fallbackPrice: "¥12 / 月",
                product: subscriptionStore.autoRenewableMonthlyProduct,
                productID: SubscriptionProductIDs.monthlyAutoRenewable,
                isActive: subscriptionStore.hasActiveSubscription,
                badge: "推荐"
            )

            planOption(
                title: "单月套餐",
                subtitle: "单月有效，不自动续订",
                fallbackPrice: "¥18 / 月",
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

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent, in: Capsule())
                        }

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

    private var selectedPlanButtonTitle: String {
        if selectedPlanIsActive {
            return "已启用"
        }
        if selectedProduct == nil {
            return "订阅"
        }
        return "订阅"
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
