//
//  StickerImageView.swift
//  菜脯
//
//  Displays a cutout image with sticker-style white border.
//  Ported from CountCals FoodCameraView.
//

import SwiftUI

/// 展示抠图结果（透明背景）+ 白色描边贴纸效果。
/// - `outlineImage`：由 ImageCutoutService.generateStickerOutline 预生成的白色轮廓图（可选）。
///   有则高质量描边，无则降级用 SwiftUI blur 模拟。
struct StickerImageView: View {
    let cutoutImage: UIImage
    let outlineImage: UIImage?
    var effectStyle: StickerEffectStyle = .whiteOutline
    var maxWidth: CGFloat = 600
    var maxHeight: CGFloat = 700

    var body: some View {
        ZStack {
            effectLayer

            Image(uiImage: cutoutImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    @ViewBuilder
    private var effectLayer: some View {
        switch effectStyle {
        case .plainCutout:
            EmptyView()
        case .whiteOutline:
            outlineLayer(color: .white, blur: outlineImage == nil ? 3 : 0, scale: outlineImage == nil ? 1.04 : 1)
        case .childhood:
            ChildhoodStickerDecorations()
                .frame(maxWidth: maxWidth * 1.28, maxHeight: maxHeight * 1.18)
                .allowsHitTesting(false)

            outlineLayer(color: Color(hex: 0xF1C84B), blur: 0.4, scale: 1.035)
                .offset(x: 5, y: -4)
            outlineLayer(color: Color(hex: 0x2F7EAA), blur: 0.25, scale: 1.025)
                .offset(x: -4, y: 3)
            outlineLayer(color: Color(hex: 0xC94A3A), blur: 0.2, scale: 1.015)
                .offset(x: 3, y: 4)
            outlineLayer(color: .white, blur: 0, scale: 1)
        }
    }

    private func outlineLayer(color: Color, blur: CGFloat, scale: CGFloat) -> some View {
        Group {
            if let outline = outlineImage {
                Image(uiImage: outline)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(uiImage: cutoutImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(color)
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .blur(radius: blur)
        .scaleEffect(scale)
    }

    private var shadowOpacity: Double {
        switch effectStyle {
        case .plainCutout:
            0.12
        case .whiteOutline:
            0.15
        case .childhood:
            0.13
        }
    }

    private var shadowRadius: CGFloat {
        effectStyle == .childhood ? 8 : 10
    }

    private var shadowY: CGFloat {
        effectStyle == .childhood ? 4 : 5
    }
}

private struct ChildhoodStickerDecorations: View {
    private let colors: [Color] = [
        Color(hex: 0xC94A3A),
        Color(hex: 0xF1C84B),
        Color(hex: 0x2F7EAA)
    ]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawFirework(in: &context, size: size, center: CGPoint(x: size.width * 0.17, y: size.height * 0.25), radius: size.width * 0.055)
                drawFirework(in: &context, size: size, center: CGPoint(x: size.width * 0.82, y: size.height * 0.18), radius: size.width * 0.048)
                drawFirework(in: &context, size: size, center: CGPoint(x: size.width * 0.16, y: size.height * 0.78), radius: size.width * 0.052)
                drawFirework(in: &context, size: size, center: CGPoint(x: size.width * 0.83, y: size.height * 0.72), radius: size.width * 0.046)
                drawConfetti(in: &context, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func drawFirework(in context: inout GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat) {
        for index in 0..<9 {
            let angle = CGFloat(index) / 9 * .pi * 2
            let start = CGPoint(
                x: center.x + cos(angle) * radius * 0.42,
                y: center.y + sin(angle) * radius * 0.42
            )
            let end = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(
                to: end,
                control: CGPoint(
                    x: center.x + cos(angle + 0.22) * radius * 0.7,
                    y: center.y + sin(angle + 0.22) * radius * 0.7
                )
            )
            context.stroke(path, with: .color(colors[index % colors.count]), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
    }

    private func drawConfetti(in context: inout GraphicsContext, size: CGSize) {
        let pieces: [(CGFloat, CGFloat, CGFloat, Int)] = [
            (0.12, 0.13, -18, 2), (0.28, 0.09, 14, 1), (0.69, 0.08, 42, 0),
            (0.84, 0.12, -24, 1), (0.09, 0.44, 18, 1), (0.91, 0.42, -15, 2),
            (0.12, 0.68, -28, 0), (0.78, 0.58, 32, 2), (0.88, 0.84, 8, 1),
            (0.25, 0.87, 21, 0), (0.73, 0.86, -18, 1)
        ]

        for piece in pieces {
            let rect = CGRect(
                x: size.width * piece.0,
                y: size.height * piece.1,
                width: 9,
                height: 6
            )
            var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            transform = transform.rotated(by: piece.2 * .pi / 180)
            transform = transform.translatedBy(x: -rect.midX, y: -rect.midY)

            var path = Path(roundedRect: rect, cornerRadius: 1)
            path = path.applying(transform)
            context.fill(path, with: .color(colors[piece.3 % colors.count]))
        }
    }
}
