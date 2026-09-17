import AVFoundation
import SwiftUI

enum QRCodeScannerFailure: Equatable {
    case permissionDenied
    case unavailable
    case configurationFailed
}

struct QRCodeCameraView: UIViewControllerRepresentable {
    let isActive: Bool
    let onPreparing: () -> Void
    let onReady: () -> Void
    let onCode: (String) -> Void
    let onFailure: (QRCodeScannerFailure) -> Void

    func makeUIViewController(context: Context) -> QRCodeCameraViewController {
        QRCodeCameraViewController(
            onReady: onReady,
            onPreparing: onPreparing,
            onCode: onCode,
            onFailure: onFailure
        )
    }

    func updateUIViewController(
        _ uiViewController: QRCodeCameraViewController,
        context: Context
    ) {
        uiViewController.setActive(isActive)
    }

    static func dismantleUIViewController(
        _ uiViewController: QRCodeCameraViewController,
        coordinator: Void
    ) {
        uiViewController.setActive(false)
    }
}

final class QRCodeCameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue = DispatchQueue(label: "mobile-facility.qr.capture")
    private let onReady: () -> Void
    private let onPreparing: () -> Void
    private let onCode: (String) -> Void
    private let onFailure: (QRCodeScannerFailure) -> Void

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var isConfigured = false
    private var isConfigurationInProgress = false
    private var shouldBeActive = false
    private var hasAcceptedCode = false

    init(
        onReady: @escaping () -> Void,
        onPreparing: @escaping () -> Void,
        onCode: @escaping (String) -> Void,
        onFailure: @escaping (QRCodeScannerFailure) -> Void
    ) {
        self.onReady = onReady
        self.onPreparing = onPreparing
        self.onCode = onCode
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.masksToBounds = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        applyRotation()
    }

    func setActive(_ active: Bool) {
        guard active != shouldBeActive else { return }
        shouldBeActive = active
        guard active else {
            stopSession()
            return
        }
        hasAcceptedCode = false
        if isConfigured {
            startSession()
        } else {
            authorizeAndConfigure()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            shouldBeActive,
            !hasAcceptedCode,
            let object = metadataObjects.first(where: { $0.type == .qr }) as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue
        else { return }

        hasAcceptedCode = true
        shouldBeActive = false
        stopSession()
        onCode(value)
    }

    private func authorizeAndConfigure() {
        guard !isConfigurationInProgress else { return }
        isConfigurationInProgress = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            onPreparing()
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    DispatchQueue.main.async { [weak self] in self?.onPreparing() }
                    self.configureSession()
                } else {
                    self.finishWithFailure(.permissionDenied)
                }
            }
        case .denied, .restricted:
            finishWithFailure(.permissionDenied)
        @unknown default:
            finishWithFailure(.unavailable)
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.shouldBeActive else {
                self.isConfigurationInProgress = false
                return
            }
            guard let camera = Self.preferredCamera() else {
                self.finishWithFailure(.unavailable)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                self.session.beginConfiguration()

                guard self.session.canAddInput(input), self.session.canAddOutput(self.metadataOutput) else {
                    self.session.commitConfiguration()
                    self.finishWithFailure(.configurationFailed)
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                self.metadataOutput.metadataObjectTypes = [.qr]
                Self.configureFocus(camera)
                self.session.commitConfiguration()

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let layer = AVCaptureVideoPreviewLayer(session: self.session)
                    layer.videoGravity = .resizeAspectFill
                    layer.frame = self.view.bounds
                    self.view.layer.insertSublayer(layer, at: 0)
                    self.previewLayer = layer
                    self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                        device: camera,
                        previewLayer: layer
                    )
                    self.applyRotation()
                }

                self.isConfigured = true
                self.isConfigurationInProgress = false
                guard self.shouldBeActive else { return }
                self.session.startRunning()
                DispatchQueue.main.async { [weak self] in self?.onReady() }
            } catch {
                self.finishWithFailure(.configurationFailed)
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.shouldBeActive, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { [weak self] in self?.onReady() }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func applyRotation() {
        guard let rotationCoordinator else { return }
        if let connection = previewLayer?.connection {
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        if let connection = metadataOutput.connection(with: .video) {
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    private func finishWithFailure(_ failure: QRCodeScannerFailure) {
        isConfigurationInProgress = false
        shouldBeActive = false
        DispatchQueue.main.async { [weak self] in self?.onFailure(failure) }
    }

    private static func preferredCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private static func configureFocus(_ camera: AVCaptureDevice) {
        guard (try? camera.lockForConfiguration()) != nil else { return }
        defer { camera.unlockForConfiguration() }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }
    }
}
