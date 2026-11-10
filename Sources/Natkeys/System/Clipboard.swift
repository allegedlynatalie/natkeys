import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Something Natkeys can paste, save, or drag: plain text or a PNG image.
enum Clip: Equatable {
    case text(String)
    /// PNG bytes for pasting. `source` is the image file it came from, if any, so weekly
    /// groups can keep the original file (a JPG stays a JPG).
    case image(Data, source: URL? = nil)

    var text: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    /// Short description for chips and tooltips.
    var preview: String {
        switch self {
        case .text(let s):
            let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
            return line.trimmingCharacters(in: .whitespaces)
        case .image(let data, _):
            if let rep = NSBitmapImageRep(data: data) {
                return "Image \(rep.pixelsWide)×\(rep.pixelsHigh)"
            }
            return "Image"
        }
    }
}

enum ImageFiles {
    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .pdf)
    }

    /// PNG bytes for an image file (PNG files are used as-is, others are converted).
    static func pngData(at url: URL?) -> Data? {
        guard let url, isImageFile(url) else { return nil }
        if url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url) {
            return data
        }
        return NSImage(contentsOf: url)?.pngData
    }

    /// The image file a piece of text points to: a path such as "/Users/me/Desktop/Graphic.jpg"
    /// (what dropping a file into a text box produces) or a file:// URL.
    static func imageFile(fromPath text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        let url: URL
        if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed), parsed.isFileURL {
            url = parsed
        } else if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else {
            return nil
        }
        guard isImageFile(url), FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    /// Pixel size and a small preview, read without decoding the whole image.
    static func thumbnail(at url: URL, maxPixels: Int = 240) -> (image: NSImage, pixelSize: CGSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? thumb.width
        var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? thumb.height
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            swap(&width, &height) // rotated 90°
        }
        let image = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
        return (image, CGSize(width: width, height: height))
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

enum Clipboard {
    /// Tells clipboard-history apps to ignore Natkeys' temporary clipboard writes (nspasteboard.org convention).
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("org.webmproject.webp"),
    ]

    // MARK: Snapshot / restore

    /// A deep copy of everything currently on the pasteboard.
    static func snapshot(_ pasteboard: NSPasteboard = .general) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        for item in items {
            item.setData(Data(), forType: transientType)
        }
        pasteboard.writeObjects(items)
    }

    // MARK: Write

    static func write(_ clip: Clip, to pasteboard: NSPasteboard = .general, transient: Bool) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        switch clip {
        case .text(let string):
            item.setString(string, forType: .string)
        case .image(let png, _):
            item.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        }
        if transient {
            item.setData(Data(), forType: transientType)
        }
        pasteboard.writeObjects([item])
    }

    // MARK: Read

    /// Reads text or an image from a pasteboard (the clipboard, or a drag).
    ///
    /// Images win when the pasteboard has image data and its text is empty or just a URL
    /// (browsers' "Copy Image" puts the image's address alongside it). Otherwise text wins,
    /// because apps like Word also put a picture of copied text on the pasteboard.
    static func read(_ pasteboard: NSPasteboard = .general) -> Clip? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls {
                if let png = ImageFiles.pngData(at: url) { return .image(png, source: url) }
            }
        }

        let string = pasteboard.string(forType: .string)
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasImage = pasteboard.availableType(from: imageTypes) != nil

        if hasImage, trimmed.isEmpty || looksLikeURL(trimmed) {
            if let png = pasteboard.data(forType: .png) {
                return .image(png)
            }
            if let image = NSImage(pasteboard: pasteboard), let png = image.pngData {
                return .image(png)
            }
        }
        if let string, !trimmed.isEmpty {
            return .text(string)
        }
        return nil
    }

    static func looksLikeURL(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "data"].contains(scheme)
    }
}
