import AppKit

/// Reads text or an image from something dragged onto the panel:
/// image files from Finder, pictures from web pages, or selected text.
@MainActor
enum DropReader {
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string] + Clipboard.imageTypes
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    static func read(_ pasteboard: NSPasteboard, completion: @escaping @MainActor (Clip?) -> Void) {
        let direct = Clipboard.read(pasteboard)
        if let direct, direct.isImage {
            completion(direct)
            return
        }

        // Some browsers drag images as "file promises" that must be written out first.
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           let receiver = receivers.first,
           receiver.fileTypes.contains(where: { UTTypeConformsToImage($0) }) || direct == nil {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("NatkeysDrop-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var delivered = false
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { url, error in
                MainActor.assumeIsolated {
                    guard !delivered else { return }
                    delivered = true
                    if let png = ImageFiles.pngData(at: error == nil ? url : nil) {
                        completion(.image(png))
                    } else {
                        completion(direct)
                    }
                }
            }
            return
        }

        // A bare link to an image (e.g. dragged from a web page): download it.
        if case .text(let text)? = direct,
           let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           ImageFiles.isImageFile(url) {
            Task { @MainActor in
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let png = NSImage(data: data)?.pngData {
                    completion(.image(png))
                } else {
                    completion(direct)
                }
            }
            return
        }

        completion(direct)
    }

    private static func UTTypeConformsToImage(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .image)
    }
}

import UniformTypeIdentifiers
