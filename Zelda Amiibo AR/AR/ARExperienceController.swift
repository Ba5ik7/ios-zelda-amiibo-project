import ARKit
import AVFoundation
import Observation
import RealityKit
import UIKit
import ImageIO

@MainActor
@Observable
final class ARExperienceController: NSObject, @preconcurrency ARSessionDelegate {
    enum CameraAccess { case checking, allowed, denied, unsupported }

    let catalog: AmiiboCatalog
    private(set) var selectedFigure: Amiibo
    private(set) var cameraAccess = CameraAccess.checking
    private(set) var guidance = "Move your phone slowly to find a table or floor."
    private(set) var notice: String?
    private(set) var loadError: String?
    private(set) var sessionError: String?
    private(set) var isLoading = false
    private(set) var isPlaced = false
    private(set) var canPlace = false
    private(set) var scanning = false
    private(set) var size: Float = 1

    @ObservationIgnored private weak var arView: ARView?
    @ObservationIgnored private let library = ModelLibrary()
    @ObservationIgnored private let scanner = QRScanner()
    @ObservationIgnored private var preparedModel: Entity?
    @ObservationIgnored private var placedModel: Entity?
    @ObservationIgnored private var placedAnchor: AnchorEntity?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var wantsActive = false
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var lastScanTime: TimeInterval = 0
    @ObservationIgnored private var lastGuidanceTime: TimeInterval = 0
    @ObservationIgnored private var scanGeneration = UUID()

    init(catalog: AmiiboCatalog, initialFigure: Amiibo) {
        self.catalog = catalog
        self.selectedFigure = initialFigure
        super.init()
    }

    func attach(_ view: ARView) {
        arView = view
        view.session.delegateQueue = .main
        view.session.delegate = self
        startSession()
    }

    func activate() async {
        wantsActive = true
        #if targetEnvironment(simulator)
        cameraAccess = .unsupported
        return
        #else
        guard ARWorldTrackingConfiguration.isSupported else {
            cameraAccess = .unsupported
            return
        }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard wantsActive, !Task.isCancelled else { return }
        cameraAccess = authorized ? .allowed : .denied
        guard authorized else { return }
        startSession()
        if preparedModel == nil && !isLoading { select(selectedFigure) }
        #endif
    }

    func suspend() {
        wantsActive = false
        arView?.session.pause()
        isRunning = false
        canPlace = false
        stopScanning()
    }

    func detach() {
        suspend()
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        arView?.session.delegate = nil
        removePlacement()
        arView = nil
    }

    private func startSession(reset: Bool = false) {
        guard wantsActive, cameraAccess == .allowed, let arView,
              !isRunning || reset else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        sessionError = nil
        isRunning = true
        canPlace = false
        guidance = "Move your phone slowly to find a table or floor."
    }

    func restart() {
        removePlacement()
        notice = nil
        stopScanning()
        startSession(reset: true)
        if preparedModel == nil { select(selectedFigure) }
    }

    func select(_ figure: Amiibo) {
        loadTask?.cancel()
        removePlacement()
        selectedFigure = figure
        preparedModel = nil
        loadError = nil
        size = 1
        guard let asset = figure.model else {
            isLoading = false
            loadError = "This figure is in the catalog, but its 3D model isn’t available yet."
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let entity = try await library.entity(for: asset)
                guard !Task.isCancelled, selectedFigure.id == figure.id else { return }
                preparedModel = entity
                isLoading = false
            } catch {
                guard !Task.isCancelled, selectedFigure.id == figure.id else { return }
                isLoading = false
                loadError = error.localizedDescription
            }
        }
    }

    func retryLoad() { select(selectedFigure) }

    func placeAtCenter() {
        guard let view = arView else { return }
        place(at: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }

    func place(at point: CGPoint) {
        guard isRunning, sessionError == nil, !scanning, let view = arView,
              let frame = view.session.currentFrame,
              case .normal = frame.camera.trackingState, let preparedModel else { return }
        guard let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first else {
            notice = "No surface there yet. Move slowly and try a well-lit table or floor."
            return
        }
        removePlacement()
        let anchor = AnchorEntity(world: hit.worldTransform)
        let model = preparedModel.clone(recursive: true)
        model.scale = SIMD3<Float>(repeating: size)
        anchor.addChild(model)
        view.scene.addAnchor(anchor)
        placedAnchor = anchor
        placedModel = model
        isPlaced = true
        notice = nil
    }

    private func removePlacement() {
        if let placedAnchor { arView?.scene.removeAnchor(placedAnchor) }
        placedAnchor = nil
        placedModel = nil
        isPlaced = false
    }

    func resize(to value: Float) {
        size = min(max(value, 0.5), 2)
        placedModel?.scale = SIMD3<Float>(repeating: size)
    }

    func rotate() {
        placedModel?.orientation *= simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
    }

    func toggleScanning() {
        if scanning { stopScanning() }
        else {
            notice = "Point at an Amiibo QR code. The code selects a figure; tap a surface afterward to place it."
            scanning = true
            scanGeneration = UUID()
            lastScanTime = 0
        }
    }

    private func stopScanning() {
        scanning = false
        scanGeneration = UUID()
        // Keep the task reference until Vision finishes so rapid toggles cannot queue frames.
        scanTask?.cancel()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, wantsActive else { return }
        if frame.timestamp - lastGuidanceTime > 0.25 {
            lastGuidanceTime = frame.timestamp
            updateGuidance(frame)
        }
        guard scanning, scanTask == nil, frame.timestamp - lastScanTime > 0.6 else { return }
        lastScanTime = frame.timestamp
        let image = CameraImage(pixelBuffer: frame.capturedImage, orientation: imageOrientation)
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { scanTask = nil }
            do {
                let payloads = try await scanner.payloads(in: image)
                guard !Task.isCancelled, scanning, wantsActive, generation == scanGeneration else { return }
                guard !payloads.isEmpty else { return }
                guard let figure = payloads.compactMap({ self.catalog.figure(for: $0) }).first else {
                    notice = "That QR code isn’t in this collection. Try one of the Amiibo QR cards."
                    return
                }
                stopScanning()
                select(figure)
                notice = "Selected \(figure.name). Find a surface and tap to place."
            } catch {
                guard !Task.isCancelled, generation == scanGeneration else { return }
                stopScanning()
                notice = "QR scanning couldn’t continue. Tap Scan QR to try again."
            }
        }
    }

    private func updateGuidance(_ frame: ARFrame) {
        canPlace = false
        switch frame.camera.trackingState {
        case .normal:
            if let view = arView {
                let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                canPlace = !view.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal).isEmpty
            }
            guidance = isPlaced ? "Walk around your figure. Tap another surface to move it." :
                (canPlace ? "Surface found. Tap to place your figure." : "Aim at a table or floor and move slowly to find a surface.")
        case .limited(let reason):
            switch reason {
            case .excessiveMotion: guidance = "Slow down a little so the camera can track the room."
            case .insufficientFeatures: guidance = "Try a brighter area with a textured surface."
            case .relocalizing: guidance = "Look around the same area to recover tracking, or restart."
            default: guidance = "Move your phone slowly while AR starts."
            }
        case .notAvailable: guidance = "Tracking isn’t available. Try restarting AR."
        }
    }

    private var imageOrientation: CGImagePropertyOrientation {
        switch arView?.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: .down
        case .landscapeRight: .up
        case .portraitUpsideDown: .left
        default: .right
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        isRunning = false
        canPlace = false
        stopScanning()
        sessionError = "AR stopped: \(error.localizedDescription)"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        isRunning = false
        canPlace = false
        stopScanning()
        guidance = "AR was interrupted. Return to the camera to continue."
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // The old world origin may no longer be valid after an interruption.
        restart()
    }
}
