import AVFoundation
import UIKit

/// QR / barcode scanner that opens a decoded URL in the browser.
final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onURLFound: ((URL) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "magdy.qr-scanner.session", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var fired = false
    private var isStopped = false
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Scan QR Code"
        buildCloseButton()

        // Camera permission: request first, explain denial instead of a black screen.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, !self.isStopped else { return }
                    if granted {
                        self.startSession()
                    } else {
                        self.showUnavailable("Camera access denied — enable it in Settings")
                    }
                }
            }
        default:
            showUnavailable("Camera access denied — enable it in Settings")
        }
    }

    private func startSession() {
        guard !isStopped, !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showUnavailable("Camera unavailable")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showUnavailable("Camera unavailable")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .ean13, .code128]
        isConfigured = true

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        // Starting and stopping share a serial queue so a queued start cannot
        // restart the camera after the scanner has been closed.
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    /// Close button must exist in every state, including the error states.
    private func buildCloseButton() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close QR scanner"
        closeButton.accessibilityHint = "Stops the camera and closes the scanner"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func stopSession() {
        isStopped = true
        isConfigured = false
        sessionQueue.async { [session] in
            session.stopRunning()
            for output in session.outputs {
                (output as? AVCaptureMetadataOutput)?.setMetadataObjectsDelegate(nil, queue: nil)
                session.removeOutput(output)
            }
            for input in session.inputs {
                session.removeInput(input)
            }
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    private func showUnavailable(_ message: String = "Camera unavailable") {
        stopSession()
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func closeTapped() {
        stopSession()
        dismiss(animated: true)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isStopped, !fired,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              let url = URL(string: value),
              url.scheme == "http" || url.scheme == "https" else { return }
        fired = true
        stopSession()
        dismiss(animated: true) { [weak self] in
            self?.onURLFound?(url)
        }
    }

    deinit {
        stopSession()
    }
}
