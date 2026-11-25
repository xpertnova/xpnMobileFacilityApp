import CoreGraphics
import XCTest
@testable import mobileFacilityApp

final class KeyboardOverlapReaderTests: XCTestCase {
    /// iPad mini in landscape, below the 24 pt status bar and above the
    /// 20 pt home indicator.
    private let window = CGRect(x: 0, y: 0, width: 1_133, height: 744)
    private let loginView = CGRect(x: 0, y: 24, width: 1_133, height: 700)

    func testDockedKeyboardCoversTheBottomOfTheView() {
        let keyboard = CGRect(x: 0, y: 309, width: 1_133, height: 435)

        XCTAssertEqual(
            KeyboardOverlapReader.overlap(keyboardFrame: keyboard, viewFrame: loginView, windowBounds: window),
            415
        )
    }

    func testHiddenKeyboardBelowTheWindowCoversNothing() {
        let keyboard = CGRect(x: 0, y: 744, width: 1_133, height: 435)

        XCTAssertEqual(
            KeyboardOverlapReader.overlap(keyboardFrame: keyboard, viewFrame: loginView, windowBounds: window),
            0
        )
    }

    func testFloatingKeyboardCoversNothing() {
        let keyboard = CGRect(x: 400, y: 300, width: 320, height: 260)

        XCTAssertEqual(
            KeyboardOverlapReader.overlap(keyboardFrame: keyboard, viewFrame: loginView, windowBounds: window),
            0
        )
    }

    func testHardwareKeyboardShortcutBarCoversOnlyItsHeight() {
        let shortcutBar = CGRect(x: 0, y: 689, width: 1_133, height: 55)

        XCTAssertEqual(
            KeyboardOverlapReader.overlap(keyboardFrame: shortcutBar, viewFrame: loginView, windowBounds: window),
            35
        )
    }

    func testEmptyKeyboardFrameCoversNothing() {
        XCTAssertEqual(
            KeyboardOverlapReader.overlap(keyboardFrame: .zero, viewFrame: loginView, windowBounds: window),
            0
        )
    }
}
