import AppKit
import Carbon.HIToolbox
import Testing
@testable import Snapline

@Suite("Keyboard layout notifications", .serialized)
struct ShortcutLabelsTests {
    @Test("Layout changes arrive while distributed notifications are suspended")
    @MainActor
    func layoutChangesWhileInactive() async throws {
        ShortcutLabels.start()
        let center = DistributedNotificationCenter.default()
        let wasSuspended = center.suspended
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: ShortcutLabels.didChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { received = true }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            center.suspended = wasSuspended
        }

        // AppKit suspends this center when a menu-bar app is inactive.
        center.suspended = true
        center.postNotificationName(
            Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, userInfo: nil, deliverImmediately: false)

        // Yield the main run loop for the distributed notification round trip.
        // The sender must not force immediate delivery: that would hide the bug.
        for _ in 0..<100 {
            if received { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(received, "Layout changes must arrive before the app becomes active again")
    }
}
