import SwiftUI

/// 全屏 AI 识别动效，在拍照/选图后的菜谱分析期间展示。
struct ScanningOverlayView: View {
    let image: UIImage
    let statusText: String
    let currentStep: Int
    let totalSteps: Int
    let progressPercent: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scanProgress: CGFloat = 0
    @State private var glowPulse: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1

    private var progress: CGFloat {
        min(max(CGFloat(progressPercent) / 100, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let stageSize = fittedStageSize(
                maxWidth: min(geometry.size.width - 44, 392),
                maxHeight: geometry.size.height * 0.58
            )

            ZStack {
                ambientBackground

                VStack(spacing: 24) {
                    Spacer(minLength: 72)

                    scanStage(width: stageSize.width, height: stageSize.height)

                    statusPanel
                        .frame(maxWidth: min(geometry.size.width - 36, 372))

                    Spacer(minLength: 42)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func fittedStageSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let imageRatio = max(image.size.width, 1) / max(image.size.height, 1)
        let containerRatio = maxWidth / max(maxHeight, 1)

        if imageRatio > containerRatio {
            return CGSize(width: maxWidth, height: maxWidth / imageRatio)
        } else {
            return CGSize(width: maxHeight * imageRatio, height: maxHeight)
        }
    }

    private var ambientBackground: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 26)
                .scaleEffect(1.08)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.64),
                    Color(hex: 0x2B211C).opacity(0.72),
                    Color(hex: 0x5D3822).opacity(0.58),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xF4C37D).opacity(0.22 + glowPulse * 0.08),
                    Color(hex: 0xC06868).opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private func scanStage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: width + 18, height: height + 18)
                .blur(radius: 18)
                .opacity(0.58 + glowPulse * 0.22)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .frame(width: width, height: height)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.18),
                            Color.clear,
                            Color.black.opacity(0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(scanLight(width: width, height: height))
                .overlay(scanGrid.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.34), radius: 24, x: 0, y: 18)

            CornerBrackets()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color(hex: 0xF4C37D).opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: width - 22, height: height - 22)
                .shadow(color: Color(hex: 0xF4C37D).opacity(0.45), radius: 10)

            VStack {
                HStack {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.28), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        )
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
            .frame(width: width, height: height)
        }
    }

    private func scanLight(width: CGFloat, height: CGFloat) -> some View {
        let beamHeight = height * 0.26
        let yOffset = -height * 0.62 + scanProgress * height * 1.24

        return ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.06),
                            Color(hex: 0xF4C37D).opacity(0.28),
                            Color.white.opacity(0.18),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: beamHeight)
                .offset(y: yOffset)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.9),
                            Color(hex: 0xF4C37D).opacity(0.88),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.92, height: 2)
                .offset(y: yOffset - beamHeight * 0.08)
                .shadow(color: Color(hex: 0xF4C37D).opacity(0.75), radius: 12)
        }
    }

    private var scanGrid: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                Rectangle()
                    .fill(.white)
                    .frame(height: 1)
                    .offset(y: CGFloat(index - 3) * 42)
            }

            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(.white)
                    .frame(width: 1)
                    .offset(x: CGFloat(index - 2) * 54)
            }
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .contentTransition(.opacity)

                    Text("第 \(currentStep) / \(totalSteps) 步")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Text("\(progressPercent)%")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            progressTrack

            HStack(spacing: 7) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.white.opacity(0.86) : Color.white.opacity(0.22))
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            if step == currentStep {
                                Capsule()
                                    .fill(Color(hex: 0xF4C37D).opacity(0.95))
                                    .frame(width: max(12, 22 + shimmerOffset * 22))
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xF4C37D),
                                Color(hex: 0xE29A5E),
                                Color.white.opacity(0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * progress)
                    .animation(.easeOut(duration: 0.35), value: progressPercent)
            }
        }
        .frame(height: 7)
    }

    private func startAnimations() {
        if reduceMotion {
            scanProgress = progress
            glowPulse = 0.45
            shimmerOffset = 0.6
            return
        }

        scanProgress = 0
        shimmerOffset = -1

        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
            scanProgress = 1
        }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            glowPulse = 1
        }

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            shimmerOffset = 1
        }
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}
