import SwiftUI
import UIKit

/// Custom popover background view that gives popovers crisp, right-angled corners
/// (12pt continuous corner radius) matching the app's typical input fields.
public final class FacilityPopoverBackgroundView: UIPopoverBackgroundView {
    public static let cornerRadiusValue: CGFloat = 12.0
    public static let arrowBaseWidth: CGFloat = 18.0
    public static let arrowHeightValue: CGFloat = 9.0

    private var _arrowOffset: CGFloat = 0
    private var _arrowDirection: UIPopoverArrowDirection = .up
    private let backgroundShapeLayer = CAShapeLayer()
    private let borderShapeLayer = CAShapeLayer()

    public override var arrowOffset: CGFloat {
        get { _arrowOffset }
        set {
            _arrowOffset = newValue
            setNeedsLayout()
        }
    }

    public override var arrowDirection: UIPopoverArrowDirection {
        get { _arrowDirection }
        set {
            _arrowDirection = newValue
            setNeedsLayout()
        }
    }

    public override class func arrowBase() -> CGFloat {
        arrowBaseWidth
    }

    public override class func arrowHeight() -> CGFloat {
        arrowHeightValue
    }

    public override class func contentViewInsets() -> UIEdgeInsets {
        .zero
    }

    public override class var wantsDefaultContentAppearance: Bool {
        false
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        layer.addSublayer(backgroundShapeLayer)
        layer.addSublayer(borderShapeLayer)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        borderShapeLayer.lineWidth = 1.0
        borderShapeLayer.fillColor = UIColor.clear.cgColor

        updateColors()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateShapePath()
        clipContainerContent()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        backgroundShapeLayer.fillColor = UIColor.systemBackground.cgColor
        borderShapeLayer.strokeColor = UIColor.black.withAlphaComponent(0.09).cgColor
    }

    private func clipContainerContent() {
        if let container = superview {
            for subview in container.subviews where subview !== self {
                subview.layer.cornerRadius = Self.cornerRadiusValue
                subview.layer.cornerCurve = .continuous
                subview.layer.masksToBounds = true
            }
        }
    }

    private func updateShapePath() {
        let path = Self.bezierPath(
            bounds: bounds,
            arrowDirection: arrowDirection,
            arrowOffset: arrowOffset
        )
        backgroundShapeLayer.path = path.cgPath
        borderShapeLayer.path = path.cgPath
        layer.shadowPath = path.cgPath
    }

    static func bezierPath(
        bounds: CGRect,
        arrowDirection: UIPopoverArrowDirection,
        arrowOffset: CGFloat
    ) -> UIBezierPath {
        guard bounds.width > 0, bounds.height > 0 else { return UIBezierPath() }
        let cornerRadius = cornerRadiusValue
        let arrowHeight = arrowHeightValue
        let arrowBase = arrowBaseWidth

        let path = UIBezierPath()

        if arrowDirection.contains(.up) {
            let bodyRect = CGRect(
                x: bounds.minX,
                y: bounds.minY + arrowHeight,
                width: bounds.width,
                height: max(0, bounds.height - arrowHeight)
            )
            let minCenterX = bodyRect.minX + cornerRadius + arrowBase / 2
            let maxCenterX = bodyRect.maxX - cornerRadius - arrowBase / 2
            let centerX = min(max(bounds.midX + arrowOffset, minCenterX), maxCenterX)

            let arrowLeft = centerX - arrowBase / 2
            let arrowRight = centerX + arrowBase / 2

            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: arrowLeft, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: centerX, y: bounds.minY))
            path.addLine(to: CGPoint(x: arrowRight, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))

            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: -CGFloat.pi / 2,
                endAngle: 0,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: CGFloat.pi / 2,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi / 2,
                endAngle: CGFloat.pi,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi,
                endAngle: -CGFloat.pi / 2,
                clockwise: true
            )
            path.close()
            return path
        } else if arrowDirection.contains(.down) {
            let bodyRect = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: max(0, bounds.height - arrowHeight)
            )
            let minCenterX = bodyRect.minX + cornerRadius + arrowBase / 2
            let maxCenterX = bodyRect.maxX - cornerRadius - arrowBase / 2
            let centerX = min(max(bounds.midX + arrowOffset, minCenterX), maxCenterX)

            let arrowLeft = centerX - arrowBase / 2
            let arrowRight = centerX + arrowBase / 2

            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: -CGFloat.pi / 2,
                endAngle: 0,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: CGFloat.pi / 2,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: arrowRight, y: bodyRect.maxY))
            path.addLine(to: CGPoint(x: centerX, y: bounds.maxY))
            path.addLine(to: CGPoint(x: arrowLeft, y: bodyRect.maxY))
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi / 2,
                endAngle: CGFloat.pi,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi,
                endAngle: -CGFloat.pi / 2,
                clockwise: true
            )
            path.close()
            return path
        } else if arrowDirection.contains(.left) {
            let bodyRect = CGRect(
                x: bounds.minX + arrowHeight,
                y: bounds.minY,
                width: max(0, bounds.width - arrowHeight),
                height: bounds.height
            )
            let minCenterY = bodyRect.minY + cornerRadius + arrowBase / 2
            let maxCenterY = bodyRect.maxY - cornerRadius - arrowBase / 2
            let centerY = min(max(bounds.midY + arrowOffset, minCenterY), maxCenterY)

            let arrowTop = centerY - arrowBase / 2
            let arrowBottom = centerY + arrowBase / 2

            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: -CGFloat.pi / 2,
                endAngle: 0,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: CGFloat.pi / 2,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi / 2,
                endAngle: CGFloat.pi,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX, y: arrowBottom))
            path.addLine(to: CGPoint(x: bounds.minX, y: centerY))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: arrowTop))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi,
                endAngle: -CGFloat.pi / 2,
                clockwise: true
            )
            path.close()
            return path
        } else if arrowDirection.contains(.right) {
            let bodyRect = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: max(0, bounds.width - arrowHeight),
                height: bounds.height
            )
            let minCenterY = bodyRect.minY + cornerRadius + arrowBase / 2
            let maxCenterY = bodyRect.maxY - cornerRadius - arrowBase / 2
            let centerY = min(max(bounds.midY + arrowOffset, minCenterY), maxCenterY)

            let arrowTop = centerY - arrowBase / 2
            let arrowBottom = centerY + arrowBase / 2

            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: -CGFloat.pi / 2,
                endAngle: 0,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: arrowTop))
            path.addLine(to: CGPoint(x: bounds.maxX, y: centerY))
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: arrowBottom))
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: 0,
                endAngle: CGFloat.pi / 2,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi / 2,
                endAngle: CGFloat.pi,
                clockwise: true
            )
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(
                withCenter: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: CGFloat.pi,
                endAngle: -CGFloat.pi / 2,
                clockwise: true
            )
            path.close()
            return path
        } else {
            return UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        }
    }
}

private struct FacilityPopoverPresenter<PopoverContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var arrowEdge: Edge = .top
    @ViewBuilder var popoverContent: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self

        if isPresented {
            if let presented = context.coordinator.presentedController as? UIHostingController<PopoverContent> {
                presented.rootView = popoverContent()
                let targetSize = presented.sizeThatFits(in: CGSize(width: 380, height: 600))
                if targetSize.width > 0 && targetSize.height > 0 {
                    presented.preferredContentSize = targetSize
                }
            } else if context.coordinator.presentedController == nil && !context.coordinator.isPresenting {
                guard uiViewController.view.window != nil else { return }

                let content = popoverContent()
                let hostingController = UIHostingController(rootView: content)
                hostingController.modalPresentationStyle = .popover
                hostingController.view.backgroundColor = .clear
                if #available(iOS 16.0, *) {
                    hostingController.sizingOptions = .preferredContentSize
                }

                let targetSize = hostingController.sizeThatFits(in: CGSize(width: 380, height: 600))
                if targetSize.width > 0 && targetSize.height > 0 {
                    hostingController.preferredContentSize = targetSize
                }

                if let popover = hostingController.popoverPresentationController {
                    popover.delegate = context.coordinator
                    popover.sourceView = uiViewController.view
                    popover.sourceRect = uiViewController.view.bounds
                    popover.permittedArrowDirections = arrowDirection(for: arrowEdge)
                    popover.popoverBackgroundViewClass = FacilityPopoverBackgroundView.self
                }

                presentPopover(
                    hostingController: hostingController,
                    from: uiViewController,
                    context: context
                )
            }
        } else {
            context.coordinator.isPresenting = false
            if let presented = context.coordinator.presentedController {
                context.coordinator.presentedController = nil
                if !presented.isBeingDismissed {
                    presented.dismiss(animated: true)
                }
            }
        }
    }

    private func presentPopover(
        hostingController: UIViewController,
        from uiViewController: UIViewController,
        context: Context
    ) {
        if let currentPresented = uiViewController.presentedViewController {
            if currentPresented.isBeingDismissed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard context.coordinator.parent.isPresented,
                          context.coordinator.presentedController == nil,
                          !context.coordinator.isPresenting,
                          uiViewController.view.window != nil else { return }
                    self.presentPopover(hostingController: hostingController, from: uiViewController, context: context)
                }
                return
            } else if currentPresented !== hostingController {
                currentPresented.dismiss(animated: true) {
                    guard context.coordinator.parent.isPresented,
                          context.coordinator.presentedController == nil,
                          !context.coordinator.isPresenting,
                          uiViewController.view.window != nil else { return }
                    self.presentPopover(hostingController: hostingController, from: uiViewController, context: context)
                }
                return
            }
        }

        context.coordinator.isPresenting = true
        context.coordinator.presentedController = hostingController
        uiViewController.present(hostingController, animated: true) {
            context.coordinator.isPresenting = false
            if !context.coordinator.parent.isPresented {
                context.coordinator.presentedController = nil
                hostingController.dismiss(animated: true)
            }
        }
    }

    private func arrowDirection(for edge: Edge) -> UIPopoverArrowDirection {
        switch edge {
        case .top:
            // The arrow points UP towards the bottom of the anchor,
            // strictly placing the dropdown frame UNDER the input field.
            return .up
        case .bottom:
            return .down
        case .leading:
            return .left
        case .trailing:
            return .right
        }
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var parent: FacilityPopoverPresenter
        weak var presentedController: UIViewController?
        var isPresenting: Bool = false

        init(_ parent: FacilityPopoverPresenter) {
            self.parent = parent
        }

        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
            .none
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedController = nil
            isPresenting = false
            if parent.isPresented {
                parent.isPresented = false
            }
        }
    }
}

public struct FacilityPopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var arrowEdge: Edge = .top
    @ViewBuilder var popoverContent: () -> PopoverContent

    public func body(content: Content) -> some View {
        content
            .background {
                FacilityPopoverPresenter(
                    isPresented: $isPresented,
                    arrowEdge: arrowEdge,
                    popoverContent: popoverContent
                )
            }
    }
}

public extension View {
    /// Presents a popover with the app's standard 12pt continuous corner radius,
    /// matching the right-angle styling of typical input fields.
    func facilityPopover<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(FacilityPopoverModifier(
            isPresented: isPresented,
            arrowEdge: arrowEdge,
            popoverContent: content
        ))
    }
}
