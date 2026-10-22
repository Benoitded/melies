import XCTest
import AppKit
@testable import Melies

@MainActor
final class ToastTests: XCTestCase {
    func testToastCanBeShownRepeatedly() async throws {
        _ = NSApplication.shared
        for key in ["toast.noclicks", "zoom.auto.none"] {
            Toast.show(L(key))
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        Toast.show(L("zoom.auto.done", 3, 7))
        try await Task.sleep(nanoseconds: 300_000_000)
    }
}

