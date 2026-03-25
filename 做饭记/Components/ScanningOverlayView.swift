import SwiftUI

/// 全屏扫描动画，在 AI 识别菜品期间展示。
/// 移植自 CountCals ScanningOverlayView，配色调整为暖色调与 App 主题一致。
struct ScanningOverlayView: View {
    let image: UIImage

    @State private var scanProgress: CGFloat = 0
    @State private var pulseOpacity: CGFloat = 0.3
    @State private var ringScales: [CGFloat] = [0, 0, 0]

    var body: some View {
        ZStack {
            // 背景：拍摄的照片（压暗）
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.55))

            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let maxRadius = max(geometry.size.width, geometry.size.height)

                ZStack {
                    // 扩散圆环（3 层交错）
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.55, blue: 0.25).opacity(0.8),
                                        Color(red: 0.75, green: 0.40, blue: 0.20).opacity(0.5),
                                        Color(red: 0.60, green: 0.30, blue: 0.15).opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .scaleEffect(ringScales[index])
                            .opacity(max(0, 1 - Double(ringScales[index])))
                            .position(center)
                            .frame(width: maxRadius, height: maxRadius)
                    }

                    // 中心脉冲光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(pulseOpacity),
                                    Color(red: 0.85, green: 0.55, blue: 0.25).opacity(pulseOpacity * 0.4),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .position(center)

                    // 横向扫描线（从上到下循环）
                    ScanLine(progress: scanProgress)
                        .stroke(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.75), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }

            // 底部状态文字
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("正在识别菜品…")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 80)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            scanProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.75
        }
        for i in 0..<3 {
            let delay = Double(i) * 0.6
            withAnimation(
                .easeOut(duration: 1.8)
                .repeatForever(autoreverses: false)
                .delay(delay)
            ) {
                ringScales[i] = 1.5
            }
        }
    }
}

// MARK: - Scan Line Shape

private struct ScanLine: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.height * progress
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: rect.width, y: y))
        return path
    }
}
