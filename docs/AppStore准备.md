# App Store 上架（仓库已就绪部分 + 你需在 Connect 完成的）

## 已在工程内处理

- **Bundle ID**：`com.lufi000.zuofanji`（应用改名不改变 Bundle ID；Xcode / `project.yml` / App Store Connect 三处需保持一致）。
- **版本**：Marketing `1.0.3`，Build `3`；`Info.plist` 使用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，与 Xcode 一致。
- **出口合规**：`ITSAppUsesNonExemptEncryption = false`（仅标准 HTTPS，无自定义加密时与 Connect 问卷常见选项一致）。
- **权限文案**：相机/相册说明中补充「可选用于识别菜谱」，与实际上传图片至阿里云做识图一致。
- **隐私清单**：`菜脯/Resources/PrivacyInfo.xcprivacy` 已加入 target，声明不追踪；收集类型含「照片或视频」、用途为 App 功能。请在 **App Store Connect → App 隐私** 中填写与之一致或更细化的说明（含与第三方共享、阿里云等）。

## 隐私政策 & 技术支持页面

法律页面由现有 BFF 服务公开托管，App 内购买页直接使用以下 HTTPS 地址：

- **隐私政策 URL（填 App Store Connect）**：`https://api.smallbeebee.com/caipu/privacy`
- **Terms of Use (EULA) URL**：`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- **技术支持**：`https://api.smallbeebee.com/caipu/privacy#support`

## 你必须在 App Store Connect / Apple 侧完成

1. 使用 **相同 Bundle ID** 新建 App（若曾用其他旧 ID 建过，需新建或用新 ID）。
2. 填写 **隐私政策 URL**：`https://api.smallbeebee.com/caipu/privacy`。
3. 若表单中有 **技术支持 URL**：使用 `https://api.smallbeebee.com/caipu/privacy#support`。
4. 在 **App Description / App 描述** 末尾加入 Apple 标准 EULA 链接：
   `Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
5. 上传 **各尺寸截图**、描述、关键词、年龄分级等。
6. **审核备注（建议粘贴）**：
   `本应用可选使用相机/相册选择菜品照片；用户主动发起时，图片会通过 HTTPS 发送至阿里云 DashScope（通义千问视觉）以生成菜谱建议，不在我方服务器存储。菜谱数据保存在设备本地（SwiftData）。`
7. 针对 3.1.2(c) 回复审核时，先在 **App Store Connect → App 信息 / App Description** 加上上一条 EULA 链接，或在 **License Agreement / EULA** 字段填入同一 URL；然后在 **App Review Information → Notes** 中补充：
   `The Snap Pickle Plus purchase screen includes the auto-renewable subscription title, 1-month length, localized App Store price, and functional links to the Privacy Policy (https://api.smallbeebee.com/caipu/privacy) and Terms of Use (EULA). The Privacy Policy URL is set in App Store Connect, and the App Store description includes the Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
8. 回复审核消息时可粘贴：
   `We corrected the invalid links. The Snap Pickle Plus purchase screen now includes functional links to the Privacy Policy (https://api.smallbeebee.com/caipu/privacy) and Terms of Use (EULA) (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/). We also added the EULA link to the App Store description and set the Privacy Policy URL in App Store Connect. A screen recording showing both links opening successfully is attached.`
9. **Archive**：Xcode → Product → Archive → Validate → Distribute；后续每次上架递增 **Build** 号。
10. **API Key**：仍在本机 `RecipeSecrets.swift`，勿提交 Git；上架包内仍可被提取，长期建议改为自有代理。

## 2.1(b) IAP 未随版本送审

这是 App Store Connect 的提交配置问题，不是 StoreKit 代码问题。首次提交 IAP 时，商品必须与一个新的 App 版本一起送审。

### 需要提交的商品

| App 内用途 | Product ID | App Store Connect 类型 |
| --- | --- | --- |
| 连续包月 | `com.lufi000.caipu.plus.monthly` | Auto-Renewable Subscription，周期 1 个月 |
| 单月套餐 | `com.lufi000.caipu.onemonth` | Non-Renewing Subscription |

Product ID 必须与 `菜脯/Services/SubscriptionStore.swift` 完全一致，不能修改大小写或增加空格。

### App Store Connect 操作顺序

1. 打开 **Apps → 菜脯 → Monetization → Subscriptions**，进入连续包月商品。
2. 补齐至少一种语言的 Display Name、Description、订阅周期、价格和销售地区。
3. 在 **Review Information → App Review Screenshot** 上传 App 内“菜脯 Plus”购买页截图。截图应清楚显示连续包月名称、价格、1 个月周期和购买按钮。
4. 确认连续包月状态变为 **Ready to Submit**。
5. 打开 **Monetization → In-App Purchases**，进入单月套餐。
6. 补齐 Localization、价格、销售地区，并上传 App Review Screenshot。建议先在 App 内选中“单月套餐”再截图，使名称、价格、有效期和购买按钮清晰可见。
7. 确认单月套餐状态变为 **Ready to Submit**。
8. 创建并上传一个新 Build，Build 号必须高于已拒绝的 Build。
9. 回到新的 iOS App 版本页面，选择新 Build。
10. 滚动到 **In-App Purchases and Subscriptions**，点击 **Select In-App Purchases or Subscriptions**（已有选择时显示 **Edit**）。
11. 同时勾选以上两个商品并点击 **Done**。不要只在 Monetization 页面创建商品而漏掉这一步。
12. 保存版本并重新 **Add for Review / Submit for Review**。提交前确认版本页面能直接看到两个 IAP。

若商品无法被勾选，先检查其状态是否为 **Ready to Submit**，以及 Paid Apps Agreement、税务和收款资料是否已经生效。

### 审核备注

在 App Review Information → Notes 中填写：

`The app includes two In-App Purchase products on the Snap Pickle Plus screen: an auto-renewable monthly subscription (com.lufi000.caipu.plus.monthly) and a non-renewing one-month pass (com.lufi000.caipu.onemonth). Both products have been submitted with this app version. The purchase screen is available at Settings → Snap Pickle Plus. No account or login is required to access it.`

### 回复审核团队

`Hello App Review Team,`

`Thank you for the clarification. We have completed the required metadata and App Review screenshots for both In-App Purchase products. We submitted the auto-renewable monthly subscription (com.lufi000.caipu.plus.monthly) and the non-renewing one-month pass (com.lufi000.caipu.onemonth) together with a new app build. The purchase screen can be accessed at Settings → Snap Pickle Plus, and no login is required.`

`Thank you.`

## 验证

- Xcode：**Product → Archive** 前用 Release 在真机跑通相机、相册、识图。
- 上传后在 Connect 中确认 **构建版本** 已出现且无合规告警。
