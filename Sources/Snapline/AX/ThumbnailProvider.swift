import AppKit
import ScreenCaptureKit

/// Live window previews for Snap Assist – adapted from Tappi's ThumbnailProvider.
///
/// Same principle: never make the user wait for pixels. Cards appear immediately
/// with the app icon; a thumbnail is captured off the main thread and faded in
/// when it arrives.
@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [CGWindowID: (image: NSImage, at: CFTimeInterval)] = [:]
    private var windowsByID: [CGWindowID: SCWindow] = [:]
    private var inFlight: Set<CGWindowID> = []
    private var catalogueFetchedAt: CFTimeInterval = 0
    private var catalogueInFlight = false
    private var pendingAfterFetch: [() -> Void] = []

    /// How long a captured preview counts as current.
    private let ttl: CFTimeInterval = 4
    /// How long the list of capturable windows stays valid.
    private let catalogueTTL: CFTimeInterval = 1.5

    /// `CGPreflightScreenCaptureAccess()` is a synchronous trip to the TCC daemon,
    /// so it is cached rather than asked per window.
    private(set) var isGranted = false
    /// ScreenCaptureKit only sees a fresh grant after a restart.
    private var grantedAtLaunch: Bool?

    private init() {}

    var isAvailable: Bool { Settings.livePreviews && isGranted }
    var needsRestart: Bool { isGranted && grantedAtLaunch == false }

    @discardableResult
    func refreshPermission() -> Bool {
        isGranted = CGPreflightScreenCaptureAccess()
        if grantedAtLaunch == nil { grantedAtLaunch = isGranted }
        return isGranted
    }

    /// Shows the system prompt once, if previews are on and access is missing.
    /// `CGRequestScreenCaptureAccess()` blocks while its dialog is up, so it runs
    /// off the main thread.
    func requestAccessIfNeeded() {
        refreshPermission()
        guard Settings.livePreviews, !isGranted else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ThumbnailProvider.shared.isGranted = granted }
            }
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Refreshes the catalogue of capturable windows; `then` runs once it is usable.
    func prepare(then: (() -> Void)? = nil) {
        guard isAvailable else { return }
        if !windowsByID.isEmpty, CACurrentMediaTime() - catalogueFetchedAt <= catalogueTTL {
            then?()
            return
        }
        if let then { pendingAfterFetch.append(then) }
        guard !catalogueInFlight else { return }
        catalogueInFlight = true
        Task.detached(priority: .userInitiated) {
            let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content?.windows ?? []
            await MainActor.run {
                let provider = ThumbnailProvider.shared
                provider.windowsByID = Dictionary(windows.map { (CGWindowID($0.windowID), $0) },
                                                  uniquingKeysWith: { first, _ in first })
                provider.catalogueFetchedAt = CACurrentMediaTime()
                provider.catalogueInFlight = false
                let callbacks = provider.pendingAfterFetch
                provider.pendingAfterFetch = []
                callbacks.forEach { $0() }
            }
        }
    }

    func cached(for id: CGWindowID) -> NSImage? { cache[id]?.image }

    /// Captures a preview if the cached one is missing or stale.
    func request(_ id: CGWindowID, size: CGSize, completion: @escaping (NSImage) -> Void) {
        guard isAvailable else { return }
        if let hit = cache[id], CACurrentMediaTime() - hit.at < ttl {
            completion(hit.image)
            return
        }
        guard !inFlight.contains(id), let window = windowsByID[id] else { return }
        inFlight.insert(id)

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.showsCursor = false
        configuration.scalesToFit = true

        Task.detached(priority: .userInitiated) {
            let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            await MainActor.run {
                let provider = ThumbnailProvider.shared
                provider.inFlight.remove(id)
                guard let cgImage else { return }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale,
                                                                   height: CGFloat(cgImage.height) / scale))
                provider.cache[id] = (image, CACurrentMediaTime())
                completion(image)
            }
        }
    }
}
