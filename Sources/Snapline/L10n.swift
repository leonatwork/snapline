import Foundation
import SnaplineCore

/// Localized UI text. The strings live in `Resources/<lang>.lproj/Localizable.strings`
/// with semantic keys; English is the development language. The app follows the
/// macOS language, there is no in-app language picker.
/// `scripts/check-localizations.sh` verifies that every language has every key.
enum L10n {
    /// Looks up `key` and, if arguments are given, uses the result as a format string.
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
    }

    /// Built-in layouts have a translated name keyed by their id; user layouts keep theirs.
    static func layoutName(_ layout: Layout) -> String {
        guard !layout.isCustom else { return layout.name }
        return NSLocalizedString("layout.\(layout.id)", bundle: bundle, value: layout.name, comment: "")
    }

    /// The app bundle. Under `swift run` there is none, so fall back to the
    /// repository's `Resources` folder when started from the repository root.
    private static let bundle: Bundle = {
        if Bundle.main.url(forResource: "Localizable", withExtension: "strings") != nil { return .main }
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        if let dev = Bundle(url: resources), dev.url(forResource: "Localizable", withExtension: "strings") != nil {
            return dev
        }
        return .main
    }()
}

extension Layout {
    /// The name shown in menus, the flyout and the editor.
    var displayName: String { L10n.layoutName(self) }
}

/// The other tools of the "I love macOS, but I miss some Windows features" package.
enum PackageApps {
    struct App {
        let name: String
        let descriptionKey: String
        let url: URL
    }

    static let others: [App] = [
        App(name: "Tappi", descriptionKey: "moreApps.tappi", url: URL(string: "https://github.com/leonatwork/Tappi")!),
        App(name: "Klemmi", descriptionKey: "moreApps.klemmi", url: URL(string: "https://github.com/leonatwork/Klemmi")!),
        App(name: "Snapboard", descriptionKey: "moreApps.snapboard", url: URL(string: "https://github.com/leonatwork/snapboard")!),
    ]

    static let packageURL = URL(string: "https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories")!
}
