import SwiftUI
import PhotosUI
import SwiftData

// MARK: - Content View (Tab Bar Root)

/// 应用主入口。
/// iOS 18+ 使用新 Tab API，"+" 通过 role: .search 脱离胶囊独立显示。
/// iOS 17 fallback 使用旧 tabItem 写法。
struct ContentView: View {

    @State private var selectedTab: AppTab = .recipes
    @State private var showAddSheet = false
    @State private var showCamera = false
    @State private var showAddRecipe = false
    @State private var showSettings = false
    @State private var capturedImageData: Data?
    @State private var showScan = false
    private let scanResult = ScanResultContainer()

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
                    // 直接用 showAddRecipe 触发 sheet，数据从 scanResult 引用类型读取，
                    // 不经过 @State 中转，避免 SwiftUI 批量更新时序导致 initialSuggestion=nil
                    showAddRecipe = true
                } else {
                    capturedImageData = nil
                    scanResult.suggestion = nil
                    scanResult.cutoutImage = nil
                    scanResult.outlineImage = nil
                }
                scanResult.cancelled = false
            }) {
                if let data = capturedImageData {
                    RecipeScanView(
                        imageData: data,
                        resultContainer: scanResult
                    )
                }
            }
            .sheet(isPresented: $showAddRecipe, onDismiss: {
                capturedImageData = nil
                scanResult.suggestion = nil
                scanResult.cutoutImage = nil
                scanResult.outlineImage = nil
            }) {
                AddRecipeView(
                    initialImageData: capturedImageData,
                    initialSuggestion: scanResult.suggestion,
                    initialCutoutImage: scanResult.cutoutImage,
                    initialOutlineImage: scanResult.outlineImage
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
    }

    // MARK: - Tab View (版本分支)

    @ViewBuilder
    private var tabViewContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("菜谱", systemImage: "book", value: AppTab.recipes) {
                    RecipeListView(
                        onOpenSettings: { showSettings = true },
                        onAddRecipe: { showAddSheet = true }
                    )
                }
                Tab("随机", systemImage: "shuffle", value: AppTab.random) {
                    RandomRecipeTabView()
                }
                Tab("添加", systemImage: "plus", value: AppTab.add, role: .search) {
                    Color.clear
                }
            }
            .tint(AppTheme.accent)
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .add {
                    selectedTab = .recipes
                    showAddSheet = true
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                RecipeListView(
                    onOpenSettings: { showSettings = true },
                    onAddRecipe: { showAddSheet = true }
                )
                .tabItem { Label("菜谱", systemImage: "book") }
                .tag(AppTab.recipes)

                RandomRecipeTabView()
                    .tabItem { Label("随机", systemImage: "shuffle") }
                    .tag(AppTab.random)

                Color.clear
                    .tabItem { Label("添加", systemImage: "plus") }
                    .tag(AppTab.add)
            }
            .tint(AppTheme.accent)
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .add {
                    selectedTab = .recipes
                    showAddSheet = true
                }
            }
        }
    }
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
