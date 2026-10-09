import SwiftUI
import UIKit

/// The app's shared motion vocabulary.
///
/// Every animation picks the role it plays instead of its own curve, so the
/// same kind of change moves the same way on every screen. Under Reduce
/// Motion all of them are off: use `facilityAnimation(_:value:)` and
/// `withFacilityAnimation(_:_:)` rather than the plain SwiftUI calls.
enum FacilityMotion {
    /// Moving between screens: list → detail, the photo workspace, the
    /// sidebar, a form opening over its list.
    static let navigation = Animation.snappy(duration: 0.32, extraBounce: 0)
    /// In-place changes: selection, expanding rows, filters, menus, status
    /// labels, list contents, scrolling to a field.
    static let standard = Animation.snappy(duration: 0.22, extraBounce: 0)
    /// Dialogs, pickers and blocking overlays. They fade in together with
    /// their backdrop (`.transition(.opacity)`).
    static let overlay = Animation.easeOut(duration: 0.18)
    /// The pressed state of buttons and rows.
    static let press = Animation.easeOut(duration: 0.12)
    /// The scanner's repeating sweep.
    static let pulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)

    /// A detail screen sliding in over its list.
    static let push = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    /// An inline row or banner appearing below its control.
    static let reveal = AnyTransition.opacity.combined(with: .move(edge: .top))

    /// A menu, dropdown, card or small control growing out of its anchor.
    static func pop(from anchor: UnitPoint = .center) -> AnyTransition {
        .scale(scale: 0.95, anchor: anchor).combined(with: .opacity)
    }
}

extension View {
    /// `animation(_:value:)` that is off under Reduce Motion.
    func facilityAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(FacilityAnimationModifier(animation: animation, value: value))
    }
}

private struct FacilityAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content.animation(accessibilityReduceMotion ? nil : animation, value: value)
    }
}

/// `withAnimation` that changes the state without animation under Reduce
/// Motion.
@MainActor
@discardableResult
func withFacilityAnimation<Result>(
    _ animation: Animation? = FacilityMotion.standard,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : animation, body)
}
