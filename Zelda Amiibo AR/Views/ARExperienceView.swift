import SwiftUI
import RealityKit
import UIKit

struct ARExperienceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: ARExperienceController

    init(catalog: AmiiboCatalog, initialFigure: Amiibo) {
        _controller = State(initialValue: ARExperienceController(catalog: catalog, initialFigure: initialFigure))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if controller.cameraAccess == .allowed {
                ARCameraView(controller: controller).ignoresSafeArea()
                if !controller.scanning {
                    Image(systemName: "scope")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(controller.canPlace ? .green : .white)
                        .shadow(radius: 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            } else {
                cameraPlaceholder
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("Done", systemImage: "xmark") { dismiss() }
                Spacer()
                if controller.cameraAccess == .allowed {
                    Button("Restart", systemImage: "arrow.counterclockwise") { controller.restart() }
                }
            }
            .buttonStyle(.bordered).tint(.white)
            .padding().background(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom) {
            if controller.cameraAccess == .allowed { controls }
        }
        .preferredColorScheme(.dark)
        .task { await controller.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await controller.activate() }
            } else { controller.suspend() }
        }
        .onDisappear { controller.detach() }
    }

    @ViewBuilder
    private var cameraPlaceholder: some View {
        switch controller.cameraAccess {
        case .checking:
            ProgressView("Preparing the camera…").tint(.white)
        case .denied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "camera")
            } description: {
                Text("Allow camera access in Settings to scan QR codes and place figures in your room.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.buttonStyle(.borderedProminent)
            }
        case .unsupported:
            ContentUnavailableView("AR needs a supported iPhone or iPad", systemImage: "iphone",
                                   description: Text("You can browse the collection here. Open the app on a real AR-capable device to place figures and scan QR codes."))
        case .allowed: EmptyView()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.selectedFigure.name).font(.headline)
                    Text(controller.scanning ? "Scanning QR codes…" : controller.guidance)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if controller.isLoading { ProgressView().accessibilityLabel("Loading model") }
            }
            if let sessionError = controller.sessionError {
                Text(sessionError).font(.caption).foregroundStyle(.orange)
            }
            if let loadError = controller.loadError {
                Text(loadError).font(.caption).foregroundStyle(.orange)
                if controller.selectedFigure.model != nil {
                    Button("Retry model loading") { controller.retryLoad() }
                }
            }
            if let notice = controller.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if controller.isPlaced {
                HStack {
                    Text("Size").font(.caption)
                    Slider(value: Binding(get: { controller.size }, set: { controller.resize(to: $0) }), in: 0.5...2)
                        .accessibilityLabel("Figure size")
                    Button("Rotate", systemImage: "rotate.right") { controller.rotate() }
                        .labelStyle(.iconOnly)
                }
            }
            HStack {
                Button(controller.scanning ? "Cancel scan" : "Scan QR",
                       systemImage: controller.scanning ? "xmark" : "qrcode.viewfinder") {
                    controller.toggleScanning()
                }
                .buttonStyle(.bordered)
                .disabled(controller.sessionError != nil)
                Spacer()
                Button(controller.isPlaced ? "Move here" : "Place here", systemImage: "arkit") {
                    controller.placeAtCenter()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canPlace || controller.isLoading || controller.loadError != nil ||
                          controller.scanning || controller.sessionError != nil)
            }
        }
        .padding().background(.regularMaterial)
        .tint(.mint)
    }
}

private struct ARCameraView: UIViewRepresentable {
    let controller: ARExperienceController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        controller.attach(view)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        view.accessibilityLabel = "AR camera. Use Place here to place the figure at the center."
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.controller.detach()
    }

    final class Coordinator: NSObject {
        let controller: ARExperienceController
        init(controller: ARExperienceController) { self.controller = controller }
        @objc func tap(_ gesture: UITapGestureRecognizer) {
            controller.place(at: gesture.location(in: gesture.view))
        }
    }
}
