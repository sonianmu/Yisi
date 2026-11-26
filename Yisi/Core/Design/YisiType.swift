import AppKit
import CoreText
import SwiftUI

/// Yisi's one typeface: Archivo, a touch narrower than normal, for Latin text and figures, and PingFang SC
/// for Chinese. Archivo ships in the bundle and is the wordmark's family; PingFang ships with macOS.
enum YisiType {
    private static let archivo: CTFontDescriptor? = {
        guard let url = Bundle.module.url(forResource: "Archivo", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return descriptors.first
    }()

    private static let lock = NSLock()
    private static var cache: [String: NSFont] = [:]

    /// Archivo at a given width (100 normal, 125 expanded) and weight on its variable axes.
    static func archivo(size: CGFloat, weight: CGFloat, width: CGFloat = 94) -> CTFont? {
        guard var descriptor = archivo else { return nil }
        descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x77647468), width)
        descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x77676874), weight)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func nsFont(size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        let axis = axisWeight(weight)
        let key = "\(size)-\(axis)"
        lock.lock()
        defer { lock.unlock() }
        if let font = cache[key] { return font }

        // PingFang's Light matches Archivo's text weight; nothing heavier than Regular is used.
        let chinese = axis >= 460 ? "PingFangSC-Regular" : "PingFangSC-Light"
        let font: NSFont
        if let latin = archivo(size: size, weight: axis) {
            // The system font first, so Cyrillic, Greek and the like keep their proportional forms;
            // it has no Han glyphs, so Chinese falls through to PingFang.
            let cascade = [NSFont.systemFont(ofSize: size, weight: weight.appKit).fontDescriptor as CTFontDescriptor,
                           CTFontDescriptorCreateWithNameAndSize(chinese as CFString, size)]
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(
                CTFontCopyFontDescriptor(latin), [kCTFontCascadeListAttribute: cascade] as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
        } else {
            font = .systemFont(ofSize: size, weight: weight.appKit)
        }
        cache[key] = font
        return font
    }

    private static func axisWeight(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight, .thin: return 250
        case .light: return 320
        case .medium: return 460
        case .semibold: return 540
        case .bold, .heavy, .black: return 640
        default: return 380
        }
    }
}

extension Font {
    static func yisi(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(YisiType.nsFont(size: size, weight: weight))
    }
}

private extension Font.Weight {
    var appKit: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
