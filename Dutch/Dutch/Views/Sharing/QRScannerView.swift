/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AVFoundation
import SwiftUI

/// Camera QR scanner.
///
/// The session is owned by the view controller and stopped on teardown. The
/// previous version pinned it to the controller with an associated object,
/// which left the camera running after the sheet was dismissed.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called with the decoded payload. Delivered at most once.
    let onScanned: (String) -> Void
    var onError: ((Error) -> Void)?
    /// Side of the centred square the scanner reads inside, in points.
    ///
    /// Must match the aiming frame the UI draws over this view, or the app
    /// would claim to be looking somewhere it isn't.
    var aimingSide: CGFloat = QRScannerView.defaultAimingSide

    static let defaultAimingSide: CGFloat = 240

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.coordinator = context.coordinator
        controller.aimingSide = aimingSide
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: ScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stop()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScanned: (String) -> Void
        private let onError: ((Error) -> Void)?
        /// Guards against the delegate firing repeatedly for the same code
        /// while the join is still in flight.
        private var hasDelivered = false

        init(onScanned: @escaping (String) -> Void, onError: ((Error) -> Void)?) {
            self.onScanned = onScanned
            self.onError = onError
        }

        func report(_ error: Error) {
            onError?(error)
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasDelivered,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue
            else { return }

            hasDelivered = true
            // Confirmation is a `.sensoryFeedback(.success)` on the SwiftUI
            // side. The legacy `kSystemSoundID_Vibrate` that used to fire here
            // is the blunt motor buzz, which ignores the user's haptic settings
            // and feels nothing like the Camera app's scan.
            onScanned(value)
        }
    }
}

// MARK: - Scanner View Controller

final class ScannerViewController: UIViewController {
    weak var coordinator: QRScannerView.Coordinator?
    var aimingSide: CGFloat = QRScannerView.defaultAimingSide

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private let sessionQueue = DispatchQueue(label: "app.dutch.scanner.session")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateRegionOfInterest()
    }

    /// Restricts decoding to the square the UI draws its aiming frame around.
    ///
    /// `rectOfInterest` is expressed in the capture device's coordinate space
    /// rather than the view's, so it has to be converted through the preview
    /// layer — and only once that layer has a real frame, which is why this
    /// runs from layout rather than from `configureSession`.
    private func updateRegionOfInterest() {
        guard let preview = previewLayer,
              let output = metadataOutput,
              view.bounds.width > 0,
              view.bounds.height > 0
        else { return }

        let side = min(aimingSide, min(view.bounds.width, view.bounds.height))
        let square = CGRect(
            x: view.bounds.midX - side / 2,
            y: view.bounds.midY - side / 2,
            width: side,
            height: side
        )

        let converted = preview.metadataOutputRectConverted(fromLayerRect: square)
        guard !converted.isNull, !converted.isEmpty else { return }
        output.rectOfInterest = converted
    }

    /// Asking first is not optional: opening a capture device without an
    /// authorised session and an `NSCameraUsageDescription` terminates the app.
    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()

        case .notDetermined:
            // `UIViewController` is `@MainActor`, so this `Task` inherits that
            // isolation and the hop the closure-based API needed is gone with
            // it — the continuation resumes where the session has to be
            // configured anyway.
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted {
                    configureSession()
                } else {
                    coordinator?.report(QRScannerError.permissionDenied)
                }
            }

        case .denied, .restricted:
            coordinator?.report(QRScannerError.permissionDenied)

        @unknown default:
            coordinator?.report(QRScannerError.cameraUnavailable)
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            coordinator?.report(QRScannerError.cameraUnavailable)
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            coordinator?.report(QRScannerError.cameraUnavailable)
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(coordinator, queue: .main)
        // Must be assigned *after* the output joins the session, or it is empty.
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        metadataOutput = output

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        // Permission can resolve after layout has already run, so claim the
        // region here as well as from `viewDidLayoutSubviews`.
        updateRegionOfInterest()
        start()
    }

    private func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    deinit {
        stop()
    }
}

// MARK: - Errors

enum QRScannerError: LocalizedError {
    case cameraUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "No camera is available on this device."
        case .permissionDenied:
            "Dutch needs camera access to scan a group's QR code. You can grant it in Settings."
        }
    }
}
