# 做饭记 · iOS 无障碍自查与 App Store 上架填写说明

## 一、App Store Connect 上架需填写的无障碍项

在 **App Store Connect → 你的 App → App 信息 / 版本信息** 中，有 **「App 无障碍」/「Accessibility」** 相关选项（部分区域显示为「无障碍营养标签」）。

### 需逐项勾选/声明的能力

| 能力 | 说明 | 本应用建议 |
|------|------|------------|
| **VoiceOver** | 仅用读屏可完成主要任务 | 已为关键控件添加 `accessibilityLabel`/`accessibilityHint`，建议实测后勾选「支持」 |
| **Voice Control** | 语音控制 | 使用系统标准控件，一般可用；建议实测后勾选 |
| **Larger Text** | 支持更大字号（动态类型） | 使用系统字体/未固定字号时可支持；若未做专门适配可先填「不支持」或实测 |
| **Dark Interface** | 深色模式 | 当前为浅色主题，可填「不支持」 |
| **Differentiate Without Color** | 不单靠颜色区分 | 控件有图标/文字，可填「支持」 |
| **Sufficient Contrast** | 对比度足够 | 已用主题色，建议实测后勾选 |
| **Reduced Motion** | 减少动画 | 未做专门适配可填「不支持」或实测 |
| **Captions** | 视频/音频字幕 | 无音视频，可填「不适用」或「不支持」 |
| **Audio Descriptions** | 音视频内容口述 | 无音视频，可填「不适用」或「不支持」 |

### 填写步骤（概要）

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)，进入对应 App。
2. 找到 **「App 无障碍」/「Manage App Accessibility」**（可能在版本页或 App 信息页）。
3. 选择设备（如 iPhone）。
4. 对每项能力选择 **Yes / No / 不适用**。
5. 保存为草稿后点击 **Publish**，生效后会在 App Store 产品页展示。

可选：填写 **Accessibility URL**，链接到更详细的无障碍说明（如本文件或网页）。

---

## 二、本应用已做的无障碍实现（VoiceOver 相关）

- **Tab 栏**：首页、设置 Tab 已具备可读标签。
- **首页**：「添加新菜谱」「筛选」按钮有 `accessibilityLabel`，必要时带 `accessibilityHint`。
- **新建/编辑菜谱**：照片区、菜名、日期、备注、标签、保存/取消均有可读标签或说明。
- **菜谱卡片**：卡片内容可被读屏识别（图片有描述、文字可读）。
- **空状态**：「记一笔」等操作按钮有明确标签。
- **设置页**：列表项为系统控件，默认可读。

建议在真机上开启 **VoiceOver**（设置 → 辅助功能 → 旁白），逐页操作一遍，确认主要流程可完成后再在 App Store Connect 中声明支持 VoiceOver。

---

## 三、参考链接

- [VoiceOver 评估标准](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria)
- [无障碍营养标签概览](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- [管理 App 无障碍](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels)
