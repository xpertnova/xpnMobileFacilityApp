import SwiftUI

/// How much room the app's window has.
///
/// The tier comes from the window size, not the device model, so an iPad mini,
/// a Split View pane and a small Stage Manager window all get `compact`, and a
/// new iPad size needs no code change.
enum FacilityLayoutTier: Equatable {
    case compact
    case regular
}

/// Sizes that change with the window.
///
/// The regular values are the layout the app was designed on (a 13-inch iPad),
/// so a large iPad keeps its look; the compact values only apply when the
/// window is smaller than an 11-inch iPad in landscape.
struct FacilityLayoutMetrics: Equatable {
    /// An 11-inch iPad in landscape is 1180 × 820 pt and still gets the regular
    /// layout; an iPad mini in landscape (1133 × 744 pt) does not.
    static let regularMinimumSize = CGSize(width: 1_180, height: 800)

    /// Used before the window has been measured, and outside a measured root.
    static let regular = FacilityLayoutMetrics(windowSize: .zero)

    /// The smallest window iPadOS may resize the app to. Every screen is laid
    /// out to work from this width up; below it the system stops shrinking.
    static let minimumWindowSize = CGSize(width: 700, height: 500)

    /// Reading width of a screen's content column on a wide window.
    static let pageMaxWidth: CGFloat = 1_280

    let windowSize: CGSize
    let tier: FacilityLayoutTier

    init(windowSize: CGSize) {
        self.windowSize = windowSize
        let isMeasured = windowSize.width > 0 && windowSize.height > 0
        let isSmallerThanRegular = windowSize.width < Self.regularMinimumSize.width
            || windowSize.height < Self.regularMinimumSize.height
        tier = isMeasured && isSmallerThanRegular ? .compact : .regular
    }

    var isCompact: Bool { tier == .compact }

    // MARK: Pages

    var pagePadding: CGFloat { isCompact ? 20 : 28 }
    var pageTitleSize: CGFloat { isCompact ? 25 : 29 }

    // MARK: Notifications

    /// The status filter (all / attention / draft) beside the notifications
    /// title.
    var notificationStatusFilterWidth: CGFloat { isCompact ? 280 : 330 }
    /// The structural filter button shows its title only on a regular window;
    /// on a compact one it keeps the icon and its count badge.
    var showsNotificationFilterTitle: Bool { !isCompact }

    // MARK: Shell

    var expandedSidebarWidth: CGFloat { isCompact ? 300 : 340 }
    var compactSidebarWidth: CGFloat { 72 }
    var sidebarHeaderSpacing: CGFloat { isCompact ? 14 : 28 }
    var sidebarRowSpacing: CGFloat { isCompact ? 2 : 4 }
    var sidebarRowMinHeight: CGFloat { isCompact ? 44 : 48 }
    var railSectionSpacing: CGFloat { isCompact ? 16 : 24 }
    var railItemSpacing: CGFloat { isCompact ? 8 : 12 }
    var railDividerPadding: CGFloat { isCompact ? 10 : 16 }

    /// Whether the full sidebar slides over the screen instead of pushing it
    /// aside, because beside it a narrow window would leave the screen less
    /// than 600 pt.
    var overlaysExpandedSidebar: Bool {
        windowSize.width > 0 && windowSize.width - expandedSidebarWidth < 600
    }

    // MARK: Dialogs

    /// Smallest gap between a centered dialog and the edges of the space it
    /// is shown in.
    var dialogMargin: CGFloat { isCompact ? 16 : 28 }

    /// Text area of the comment editor dialogs. On a compact window the
    /// keyboard leaves about 330 pt, which a 190 pt editor would overflow.
    var commentEditorHeight: CGFloat { isCompact ? 140 : 190 }

    /// Inner padding of a dialog card designed with `regular` padding.
    func dialogPadding(_ regular: CGFloat) -> CGFloat {
        isCompact ? min(regular, 22) : regular
    }
}

extension EnvironmentValues {
    @Entry var facilityLayout: FacilityLayoutMetrics = .regular
}

extension View {
    /// Measures the window and publishes `FacilityLayoutMetrics` to every view
    /// below, and keeps iPadOS from resizing the window below
    /// `FacilityLayoutMetrics.minimumWindowSize`. Apply it once, at the root.
    ///
    /// The measurement ignores every safe area, the keyboard included, so
    /// showing the keyboard never switches the tier while someone is typing.
    func facilityLayoutRoot() -> some View {
        modifier(FacilityLayoutRootModifier())
    }

    /// The padding and reading width of a top-level screen's content column.
    func facilityPageContent() -> some View {
        modifier(FacilityPageContentModifier())
    }

    /// The horizontal padding of a screen's pinned header or action bar, so
    /// it lines up with the page content scrolling beneath it.
    func facilityPageHorizontalPadding() -> some View {
        modifier(FacilityPageHorizontalPaddingModifier())
    }

    /// The bold page-title font, sized for the window.
    func facilityPageTitleFont(design: Font.Design = .default) -> some View {
        modifier(FacilityPageTitleFontModifier(design: design))
    }
}

private struct FacilityLayoutRootModifier: ViewModifier {
    @State private var windowSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .environment(\.facilityLayout, FacilityLayoutMetrics(windowSize: windowSize))
            .background {
                // The reading sits inside `ignoresSafeArea`, so it sees the
                // expanded, full-window frame.
                Color.clear
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        windowSize = size
                    }
                    .ignoresSafeArea()
            }
            .background {
                WindowSceneMinimumSize(size: FacilityLayoutMetrics.minimumWindowSize)
            }
    }
}

private struct FacilityPageHorizontalPaddingModifier: ViewModifier {
    @Environment(\.facilityLayout) private var layout

    func body(content: Content) -> some View {
        content.padding(.horizontal, layout.pagePadding)
    }
}

private struct FacilityPageTitleFontModifier: ViewModifier {
    let design: Font.Design
    @Environment(\.facilityLayout) private var layout

    func body(content: Content) -> some View {
        content.font(.system(size: layout.pageTitleSize, weight: .bold, design: design))
    }
}

private struct FacilityPageContentModifier: ViewModifier {
    @Environment(\.facilityLayout) private var layout

    func body(content: Content) -> some View {
        content
            .padding(layout.pagePadding)
            .frame(maxWidth: FacilityLayoutMetrics.pageMaxWidth, alignment: .leading)
    }
}

/// Applies a minimum size to the window scene the view is shown in. Where the
/// system does not allow resizing, the scene has no size restrictions and
/// this does nothing.
private struct WindowSceneMinimumSize: UIViewRepresentable {
    let size: CGSize

    func makeUIView(context: Context) -> RestrictingView {
        RestrictingView(minimumSize: size)
    }

    func updateUIView(_ view: RestrictingView, context: Context) {
        view.minimumSize = size
    }

    final class RestrictingView: UIView {
        var minimumSize: CGSize {
            didSet { applyRestriction() }
        }

        init(minimumSize: CGSize) {
            self.minimumSize = minimumSize
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyRestriction()
        }

        private func applyRestriction() {
            window?.windowScene?.sizeRestrictions?.minimumSize = minimumSize
        }
    }
}
