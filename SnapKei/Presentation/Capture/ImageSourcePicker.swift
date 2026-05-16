import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

public struct ImageSourcePicker: View {
    public enum Source: Identifiable {
        case camera
        case album
        case pdf

        public var id: String {
            switch self {
            case .camera: "camera"
            case .album: "album"
            case .pdf: "pdf"
            }
        }
    }

    @Binding private var sheetSource: Source?
    private let onImagePicked: (UIImage) -> Void
    private let onPDFPicked: (URL) -> Void

    public init(sheetSource: Binding<Source?>, onImagePicked: @escaping (UIImage) -> Void, onPDFPicked: @escaping (URL) -> Void) {
        self._sheetSource = sheetSource
        self.onImagePicked = onImagePicked
        self.onPDFPicked = onPDFPicked
    }

    public var body: some View {
        VStack(spacing: 12) {
            Button { sheetSource = .camera } label: {
                Label("撮影", systemImage: "camera").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button { sheetSource = .album } label: {
                Label("アルバム", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { sheetSource = .pdf } label: {
                Label("PDF をインポート", systemImage: "doc.richtext").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .sheet(item: $sheetSource) { source in
            switch source {
            case .camera:
                CameraPicker { onImagePicked($0); sheetSource = nil }
            case .album:
                PhotoLibraryPicker { onImagePicked($0); sheetSource = nil }
            case .pdf:
                DocumentPicker(contentTypes: [.pdf]) { onPDFPicked($0); sheetSource = nil }
            }
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onPicked(image) }
            picker.dismiss(animated: true)
        }
    }
}

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { self.onPicked(image) }
            }
        }
    }
}

private struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPicked(url)
        }
    }
}
