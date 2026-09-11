import SwiftUI
import UIKit
import AVFoundation

enum CameraCaptureAvailability {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

enum JPEGPhotoEncoder {
    static func encode(_ data: Data, compressionQuality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return encode(image, compressionQuality: compressionQuality)
    }

    static func encode(_ image: UIImage, compressionQuality: CGFloat = 0.82) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalized.jpegData(compressionQuality: compressionQuality)
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    var compressionQuality: CGFloat = 0.82
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = JPEGPhotoEncoder.encode(
                    image, compressionQuality: parent.compressionQuality
                  ) else {
                parent.onCancel()
                return
            }
            parent.onCapture(data)
        }
    }
}

struct JPEGThumbnailView: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}
