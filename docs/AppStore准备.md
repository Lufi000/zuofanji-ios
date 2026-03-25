# App Store 上架（仓库已就绪部分 + 你需在 Connect 完成的）

## 已在工程内处理

- **Bundle ID**：`com.lufi000.zuofanji`（与 GitHub 用户名一致；若你要用自有域名，请在 Xcode / `project.yml` / App Store Connect 三处同步改掉）。
- **版本**：Marketing `1.0.0`，Build `1`；`Info.plist` 使用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，与 Xcode 一致。
- **出口合规**：`ITSAppUsesNonExemptEncryption = false`（仅标准 HTTPS，无自定义加密时与 Connect 问卷常见选项一致）。
- **权限文案**：相机/相册说明中补充「可选用于识别菜谱」，与实际上传图片至阿里云做识图一致。
- **隐私清单**：`做饭记/Resources/PrivacyInfo.xcprivacy` 已加入 target，声明不追踪；收集类型含「照片或视频」、用途为 App 功能。请在 **App Store Connect → App 隐私** 中填写与之一致或更细化的说明（含与第三方共享、阿里云等）。

## 你必须在 App Store Connect / Apple 侧完成

1. 使用 **相同 Bundle ID** 新建 App（若曾用 `com.example.zuofanji` 建过，需新建或用新 ID）。
2. 填写 **隐私政策 URL**（需可公开访问）。
3. 上传 **各尺寸截图**、描述、关键词、年龄分级等。
4. **审核备注（建议粘贴）**：  
   `本应用可选使用相机/相册选择菜品照片；用户主动发起时，图片会通过 HTTPS 发送至阿里云 DashScope（通义千问视觉）以生成菜谱建议，不在我方服务器存储。菜谱数据保存在设备本地（SwiftData）。`
5. **Archive**：Xcode → Product → Archive → Validate → Distribute；后续每次上架递增 **Build** 号。
6. **API Key**：仍在本机 `RecipeSecrets.swift`，勿提交 Git；上架包内仍可被提取，长期建议改为自有代理。

## 验证

- Xcode：**Product → Archive** 前用 Release 在真机跑通相机、相册、识图。
- 上传后在 Connect 中确认 **构建版本** 已出现且无合规告警。
