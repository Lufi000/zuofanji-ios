import SwiftUI
import PhotosUI
import SwiftData

// MARK: - Content View (Tab Bar Root)

/// 应用主入口。
/// iOS 18+ 使用新 Tab API，"+" 通过 role: .search 脱离胶囊独立显示。
/// iOS 17 fallback 使用旧 tabItem 写法。
struct ContentView: View {

    @State private var selectedTab: AppTab = .recipes
    @State private var recipesResetToken = 0
    @State private var showAddSheet = false
    @State private var showCamera = false
    @State private var addRecipePresentation: AddRecipePresentation?
    @State private var showSettings = false
    @State private var showSubscription = false
    @State private var shouldOpenSubscriptionAfterScan = false
    @State private var capturedImageData: Data?
    @State private var showScan = false
    @State private var scanResult = ScanResultContainer()

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    var body: some View {
        tabViewContent
            .sheet(isPresented: $showAddSheet) {
                AddSourceSheet(
                    onCamera: {
                        showAddSheet = false
                        showCamera = true
                    },
                    onPhotoLibrary: {
                        showAddSheet = false
                        showPhotoPicker = true
                    }
                )
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.cardBackground)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(
                    onCapture: { data in
                        capturedImageData = data
                        showCamera = false
                    },
                    onCancel: { showCamera = false }
                )
            }
            .onChange(of: showCamera) { _, isShowing in
                if !isShowing, capturedImageData != nil {
                    showScan = true
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    if let transfer = try? await item.loadTransferable(type: PhotoImageTransfer.self) {
                        capturedImageData = transfer.data
                        showScan = true
                    }
                    photoPickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showScan, onDismiss: {
                if !scanResult.cancelled {
                    addRecipePresentation = AddRecipePresentation(
                        imageData: capturedImageData,
                        suggestion: scanResult.suggestion,
                        aiUnavailableMessage: scanResult.aiUnavailableMessage,
                        cutoutImage: scanResult.cutoutImage,
                        outlineImage: scanResult.outlineImage
                    )
                } else {
                    capturedImageData = nil
                    scanResult.suggestion = nil
                    scanResult.aiUnavailableMessage = nil
                    scanResult.cutoutImage = nil
                    scanResult.outlineImage = nil
                }
                scanResult.cancelled = false
                if shouldOpenSubscriptionAfterScan {
                    shouldOpenSubscriptionAfterScan = false
                    showSubscription = true
                }
            }) {
                if let data = capturedImageData {
                    RecipeScanView(
                        imageData: data,
                        resultContainer: scanResult,
                        onOpenSubscription: {
                            shouldOpenSubscriptionAfterScan = true
                        }
                    )
                }
            }
            .sheet(item: $addRecipePresentation, onDismiss: {
                capturedImageData = nil
                scanResult.suggestion = nil
                scanResult.aiUnavailableMessage = nil
                scanResult.cutoutImage = nil
                scanResult.outlineImage = nil
            }) { presentation in
                AddRecipeView(
                    initialImageData: presentation.imageData,
                    initialSuggestion: presentation.suggestion,
                    initialAIUnavailableMessage: presentation.aiUnavailableMessage,
                    initialCutoutImage: presentation.cutoutImage,
                    initialOutlineImage: presentation.outlineImage
                )
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { showSettings = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSubscription) {
                NavigationStack {
                    SubscriptionView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { showSubscription = false }
                            }
                        }
                }
            }
    }

    // MARK: - Tab View (版本分支)

    @ViewBuilder
    private var tabViewContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tabSelection) {
                Tab("菜谱", systemImage: "fork.knife", value: AppTab.recipes) {
                    RecipeListView(
                        resetToken: recipesResetToken,
                        onOpenSettings: { showSettings = true },
                        onAddRecipe: { showAddSheet = true }
                    )
                }
                Tab("随机", systemImage: "die.face.5.fill", value: AppTab.random) {
                    RandomRecipeTabView()
                }
                Tab("添加", systemImage: "plus.circle.fill", value: AppTab.add, role: .search) {
                    Color.clear
                }
            }
            .tint(AppTheme.accent)
            .toolbarBackground(AppTheme.cardBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        } else {
            TabView(selection: tabSelection) {
                RecipeListView(
                    resetToken: recipesResetToken,
                    onOpenSettings: { showSettings = true },
                    onAddRecipe: { showAddSheet = true }
                )
                .tabItem { Label("菜谱", systemImage: "fork.knife") }
                .tag(AppTab.recipes)

                RandomRecipeTabView()
                    .tabItem { Label("随机", systemImage: "die.face.5.fill") }
                    .tag(AppTab.random)

                Color.clear
                    .tabItem { Label("添加", systemImage: "plus.circle.fill") }
                    .tag(AppTab.add)
            }
            .tint(AppTheme.accent)
            .toolbarBackground(AppTheme.cardBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .recipes {
                    recipesResetToken += 1
                }

                if newTab == .add {
                    selectedTab = .recipes
                    recipesResetToken += 1
                    showAddSheet = true
                } else {
                    selectedTab = newTab
                }
            }
        )
    }
}

private struct AddRecipePresentation: Identifiable {
    let id = UUID()
    let imageData: Data?
    let suggestion: RecipeAISuggestion?
    let aiUnavailableMessage: String?
    let cutoutImage: UIImage?
    let outlineImage: UIImage?
}

// MARK: - Add Source Sheet

/// 底部来源选择：相机 / 上传图片
private struct AddSourceSheet: View {

    var onCamera: () -> Void
    var onPhotoLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("添加菜谱")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.bodyText)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            Button {
                onCamera()
            } label: {
                Label("相机", systemImage: "camera")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .font(.body)
            }

            Divider()

            Button {
                onPhotoLibrary()
            } label: {
                Label("上传图片", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .font(.body)
            }
        }
        .foregroundStyle(AppTheme.titleText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.cardBackground)
    }
}

// MARK: - Photo Image Transfer

/// 从 PhotosPicker 可靠加载图片为 Data
private struct PhotoImageTransfer: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PhotoImageTransfer(data: data)
        }
    }
}

// MARK: - Tab Enum

private enum AppTab: Hashable {
    case recipes
    case random
    case add
}
