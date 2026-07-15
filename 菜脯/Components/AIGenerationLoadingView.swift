import SwiftUI

/// AI 文字生成中的轻量等待态：手写骨架、流光和等待小纸条。
struct AIGenerationLoadingView: View {
    let statusText: String
    var showsProgress = false
    var progress: CGFloat = 0
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerOffset: CGFloat = -1
    @State private var tipIndex = 0

    private let tips = [
        "小技巧：主体拍清楚一点，贴纸边缘会更干净。",
        "你可以把照片整理成一页记录，不一定非要是食物。",
        "识别完成前，也可以先看看贴纸效果。",
        "平铺模式会把记录文字变成手帐旁注。",
        "保存后，文字还可以继续手动改。",
        "有抠图时，照片会自动变成贴纸感。"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.titleText)
                        .contentTransition(.opacity)

                    Text("文字还在慢慢整理，照片已经可以先看起来。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.bodyText.opacity(0.66))
                }

                Spacer(minLength: 0)
            }

            handwrittenSkeleton

            if showsProgress {
                progressBar
            }

            tipCard
        }
        .padding(compact ? 14 : 16)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.accent.opacity(0.12), lineWidth: 1)
        }
        .onAppear {
            startShimmer()
        }
        .onChange(of: reduceMotion) { _, _ in
            startShimmer()
        }
        .task {
            await rotateTipsIfNeeded()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusText)。\(tips[tipIndex])")
    }

    private var handwrittenSkeleton: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            ForEach(Array(lineWidths.enumerated()), id: \.offset) { _, width in
                ShimmeringHandwrittenLine(
                    widthRatio: width,
                    shimmerOffset: shimmerOffset,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var lineWidths: [CGFloat] {
        compact ? [0.68, 0.92, 0.76] : [0.54, 0.9, 0.82, 0.62]
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.bodyText.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.82),
                                Color(hex: 0xFFD59B)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    .animation(.easeOut(duration: 0.35), value: progress)
            }
        }
        .frame(height: 7)
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent.opacity(0.9))
                .padding(.top, 1)

            Text(tips[tipIndex])
                .font(.caption)
                .foregroundStyle(AppTheme.bodyText.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .id(tipIndex)
                .transition(.opacity.combined(with: .move(edge: .top)))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppTheme.notebookPaper.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func startShimmer() {
        guard !reduceMotion else {
            shimmerOffset = 0
            return
        }

        shimmerOffset = -1
        withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) {
            shimmerOffset = 1
        }
    }

    private func rotateTipsIfNeeded() async {
        guard !reduceMotion else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 3_400_000_000)
            } catch {
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.32)) {
                    tipIndex = (tipIndex + 1) % tips.count
                }
            }
        }
    }
}

private struct ShimmeringHandwrittenLine: View {
    let widthRatio: CGFloat
    let shimmerOffset: CGFloat
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * widthRatio

            Capsule()
                .fill(AppTheme.bodyText.opacity(0.12))
                .frame(width: width, height: 8)
                .overlay(alignment: .leading) {
                    if reduceMotion {
                        Capsule()
                            .fill(Color(hex: 0xFFD59B).opacity(0.18))
                            .frame(width: width, height: 8)
                    } else {
                        LinearGradient(
                            colors: [
                                .clear,
                                Color(hex: 0xFFD59B).opacity(0.14),
                                .white.opacity(0.78),
                                Color(hex: 0xFFD59B).opacity(0.18),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(width * 0.46, 44), height: 8)
                        .offset(x: shimmerOffset * (width + 50))
                        .mask(
                            Capsule()
                                .frame(width: width, height: 8)
                        )
                    }
                }
        }
        .frame(height: 8)
    }
}
