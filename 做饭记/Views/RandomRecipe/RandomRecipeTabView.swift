import SwiftUI
import SwiftData
import AudioToolbox
import AVFoundation

// MARK: - Shuffle Sound Helper

/// 换菜音效播放器（单例，供摇一摇和按钮共用）
private final class ShuffleSoundPlayer {
    static let shared = ShuffleSoundPlayer()
    private var soundID: SystemSoundID = 0
    
    private init() {
        loadSound()
    }
    
    private func loadSound() {
        if let url = Bundle.main.url(forResource: "shake_sound", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
    }
    
    func play() {
        if soundID != 0 {
            AudioServicesPlaySystemSound(soundID)
        }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    deinit {
        if soundID != 0 {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }
}

// MARK: - Shake Detection

/// 用于检测摇一摇手势的 ViewController
private class ShakeDetectingViewController: UIViewController {
    var onShake: (() -> Void)?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShuffleSoundPlayer.shared.play()
            onShake?()
        }
    }
}

/// SwiftUI 包装器
private struct ShakeDetectorView: UIViewControllerRepresentable {
    let onShake: () -> Void
    
    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let vc = ShakeDetectingViewController()
        vc.onShake = onShake
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}

// MARK: - Random Recipe Tab View

/// "随机"tab 的根页面，自管理随机抽取逻辑。
/// 每次进入此 tab 时自动抽一道；点击"再随一道"或摇一摇换一道。
struct RandomRecipeTabView: View {

    @Query private var allRecipes: [Recipe]
    @State private var currentRecipe: Recipe?

    var body: some View {
        NavigationStack {
            Group {
                if let recipe = currentRecipe {
                    recipeContent(recipe)
                } else {
                    emptyState
                }
            }
            .navigationTitle("今天吃什么？")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .background {
                ShakeDetectorView { shakeToShuffle() }
            }
        }
        .onAppear { pickIfNeeded() }
    }

    // MARK: - Subviews

    private func recipeContent(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NavigationLink(value: recipe) {
                    VStack(alignment: .leading, spacing: 20) {
                        heroImage(recipe)
                        infoSection(recipe)
                    }
                }
                .buttonStyle(.plain)

                tagsSection(recipe)
                notesSection(recipe)
                Spacer(minLength: 24)
                shuffleButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .id(recipe.id)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.spring(duration: 0.3, bounce: 0.15), value: recipe.id)
        }
        .background(AppTheme.background)
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50 {
                        ShuffleSoundPlayer.shared.play()
                        pickAnother()
                    }
                }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.bodyText.opacity(0.4))
            Text("还没有菜谱")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(AppTheme.titleText)
            Text("先去添加几道菜，再来随机试试吧")
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }

    @ViewBuilder
    private func heroImage(_ recipe: Recipe) -> some View {
        if let data = recipe.imageData, let uiImage = UIImage(data: data) {
            Color.clear
                .aspectRatio(3/4, contentMode: .fit)
                .overlay {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Color.clear
                .aspectRatio(3/4, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.placeholder)
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.largeTitle)
                        Text("暂无照片")
                            .font(.subheadline)
                    }
                    .foregroundStyle(AppTheme.bodyText.opacity(0.5))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func infoSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.titleText)

            Text(recipe.date, format: .dateTime.year().month().day().weekday())
                .font(.subheadline)
                .foregroundStyle(AppTheme.bodyText)
        }
    }

    @ViewBuilder
    private func tagsSection(_ recipe: Recipe) -> some View {
        let hasTags = recipe.difficulty != nil || recipe.cuisine != nil || recipe.cookingTime != nil
        if hasTags {
            HStack(spacing: 8) {
                if let d = recipe.difficulty   { TagChipView.difficulty(d) }
                if let c = recipe.cuisine      { TagChipView.cuisine(c) }
                if let t = recipe.cookingTime  { TagChipView.cookingTime(t) }
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ recipe: Recipe) -> some View {
        if !recipe.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)

                Text(recipe.notes)
                    .font(.body)
                    .foregroundStyle(AppTheme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var shuffleButton: some View {
        Button {
            ShuffleSoundPlayer.shared.play()
            pickAnother()
        } label: {
            Label("换一道", systemImage: "shuffle")
                .font(.body)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    /// 首次进入时若还没有当前菜谱则抽一道。
    private func pickIfNeeded() {
        guard currentRecipe == nil, !allRecipes.isEmpty else { return }
        currentRecipe = allRecipes.randomElement()
    }

    /// 换一道（排除当前这道）。
    private func pickAnother() {
        guard !allRecipes.isEmpty else { return }
        let candidates = allRecipes.filter { $0.id != currentRecipe?.id }
        currentRecipe = candidates.isEmpty ? allRecipes.randomElement() : candidates.randomElement()
    }
    
    /// 摇一摇换菜（音效和震动在 ShakeDetectingViewController 中触发）
    private func shakeToShuffle() {
        guard !allRecipes.isEmpty else { return }
        pickAnother()
    }
}
