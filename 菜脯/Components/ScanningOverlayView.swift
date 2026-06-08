import SwiftUI

/// 拍照/选图后的单一分析视图：固定图片、单进度条、分阶段状态。
struct ScanningOverlayView: View {
    let image: UIImage
    let statusText: String
    let currentStep: Int
    let totalSteps: Int
    let progressPercent: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanPosition: CGFloat = -0.25

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

                VStack(spacing: 28) {
                    Spacer(minLength: 82)

                    analysisImage(width: imageWidth, height: imageHeight)

                    statusArea
                        .frame(maxWidth: min(geometry.size.width - 40, 420))

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            startScanAnimation()
        }
    }

    private func analysisImage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)

            analysisSweep(width: width, height: height)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }

    private func analysisSweep(width: CGFloat, height: CGFloat) -> some View {
        let yOffset = scanPosition * height

        return ZStack {
            LinearGradient(
                colors: [
                    Color.clear,
                    AppTheme.accent.opacity(0.12),
                    Color.white.opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height * 0.22)
            .offset(y: yOffset)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(hex: 0xFFD59B),
                            Color.white,
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.9, height: 2)
                .offset(y: yOffset)
                .shadow(color: AppTheme.accent, radius: 8)
        }
        .allowsHitTesting(false)
    }

    private var statusArea: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)

                    Text(
                        AppLocalization.format(
                            "第 %lld / %lld 步",
                            Int64(currentStep),
                            Int64(totalSteps)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Text("\(progressPercent)%")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent,
                                    Color(hex: 0xFFD59B)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * progress)
                        .animation(.easeOut(duration: 0.35), value: progressPercent)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 4)
    }

    private func startScanAnimation() {
        guard !reduceMotion else {
            scanPosition = 0
            return
        }

        scanPosition = -0.55
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            scanPosition = 0.55
        }
    }
}
