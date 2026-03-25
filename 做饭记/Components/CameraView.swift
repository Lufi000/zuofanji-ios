import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Image Data Transferable

/// 用于从 PhotosPicker 可靠加载图片为 Data（系统对 Data.self 可能返回 nil）
private struct ImageDataTransfer: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImageDataTransfer(data: data)
        }
    }
}

// MARK: - Camera View

/// 全屏相机视图，包装 UIImagePickerController。
/// 默认打开相机拍照，底部提供「从相册选」入口。
struct CameraView: View {

    /// 拍照或选图完成后回调，传回图片 Data
    var onCapture: (Data) -> Void
    /// 用户取消
    var onCancel: () -> Void

    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ZStack {
            // 相机主体
            CameraRepresentable(
                onCapture: onCapture,
                onCancel: onCancel
            )
            .ignoresSafeArea()

            // 底部「从相册选」按钮，悬浮在相机界面上、与安全区对齐
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("从相册选", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .padding(.bottom, 28)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            loadPhoto(from: newItem)
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            if let transfer = try? await item.loadTransferable(type: ImageDataTransfer.self) {
                onCapture(transfer.data)
            }
        }
    }
}

// MARK: - UIImagePickerController Wrapper

/// UIKit 相机的 SwiftUI 包装
private struct CameraRepresentable: UIViewControllerRepresentable {

    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        // 隐藏系统相机的取消按钮文字，用我们自己的导航
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onCapture(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
