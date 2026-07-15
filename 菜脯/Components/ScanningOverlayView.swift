import SwiftUI

/// 拍照/选图后的单一分析视图：固定图片、单进度条、分阶段状态。
struct ScanningOverlayView: View {
    let image: UIImage
    let statusText: String
    let currentStep: Int
    let totalSteps: Int
    let progressPercent: Int
    let tracingContourImage: UIImage?

    private var progress: CGFloat {
        min(max(CGFloat(progressPercent) / 100, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = min(geometry.size.width - 40, 420)
            let imageHeight = min(geometry.size.height * 0.56, 520)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0x1F1A17),
                        Color(hex: 0x33261F),
                        Color(hex: 0x1F1A17)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 26) {
                    Spacer(minLength: 82)

                    analysisImage(width: imageWidth, height: imageHeight)

                    AIGenerationLoadingView(
                        statusText: statusText,
                        showsProgress: true,
                        progress: progress,
                        compact: false
                    )
                        .frame(maxWidth: min(geometry.size.width - 40, 420))

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func analysisImage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)

            if let tracingContourImage {
                EdgeTracingOverlayView(
                    contourImage: tracingContourImage,
                    width: width,
                    height: height
                )
            } else {
                waitingEdgeGlow(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }

    private func waitingEdgeGlow(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.28),
                        Color(hex: 0xFFD59B).opacity(0.18),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .frame(width: width, height: height)
            .shadow(color: Color(hex: 0xFFD59B).opacity(0.18), radius: 12)
        .allowsHitTesting(false)
    }

}

private struct EdgeTracingOverlayView: View {
    let contourImage: UIImage
    let width: CGFloat
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var highlightRotation = 0.0

    var body: some View {
        ZStack {
            contourLayer(color: Color(hex: 0xFFD59B), opacity: 0.36)
                .blur(radius: 0.6)

            contourLayer(color: Color(hex: 0xFFD59B), opacity: 0.2)
                .blur(radius: 5)

            if reduceMotion {
                contourLayer(color: .white, opacity: 0.72)
                    .blur(radius: 0.4)
            } else {
                movingHighlight
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .onAppear {
            startHighlightAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            startHighlightAnimation()
        }
    }

    private var movingHighlight: some View {
        AngularGradient(
            colors: [
                .clear,
                .clear,
                Color(hex: 0xFFD59B).opacity(0.12),
                .white.opacity(0.95),
                Color(hex: 0xFFD59B).opacity(0.75),
                .clear,
                .clear
            ],
            center: .center,
            angle: .degrees(highlightRotation)
        )
        .frame(width: width, height: height)
        .mask(contourMask)
        .shadow(color: Color(hex: 0xFFD59B).opacity(0.7), radius: 8)
    }

    private var contourMask: some View {
        Image(uiImage: contourImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }

    private func contourLayer(color: Color, opacity: Double) -> some View {
        Image(uiImage: contourImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .colorMultiply(color)
            .opacity(opacity)
    }

    private func startHighlightAnimation() {
        guard !reduceMotion else {
            highlightRotation = 0
            return
        }

        highlightRotation = 0
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            highlightRotation = 360
        }
    }
}
