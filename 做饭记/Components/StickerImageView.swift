//
//  StickerImageView.swift
//  做饭记
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
    var maxWidth: CGFloat = 600
    var maxHeight: CGFloat = 700

    var body: some View {
        ZStack {
            if let outline = outlineImage {
                Image(uiImage: outline)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
            } else {
                // 降级方案：SwiftUI 模拟描边（质量略低）
                Image(uiImage: cutoutImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .colorMultiply(.white)
                    .blur(radius: 3)
                    .scaleEffect(1.04)
            }

            Image(uiImage: cutoutImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}
