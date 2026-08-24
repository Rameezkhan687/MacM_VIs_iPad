import SceneKit
import SwiftUI

struct MolecularSceneView: UIViewRepresentable {
    let structure: MolecularStructure?
    let volume: VolumeMap?
    let settings: RenderSettings
    let selectedAtomIDs: [Int]
    let revision: Int
    let onSelectAtom: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelectAtom: onSelectAtom) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        MolecularSceneBuilder.configureScene(scene)
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor(settings.backgroundColor)
        view.accessibilityLabel = "Interactive molecular viewport"

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSelectAtom = onSelectAtom
        view.backgroundColor = UIColor(settings.backgroundColor)
        let contentID = "\(structure?.id.uuidString ?? "none"):\(volume?.id.uuidString ?? "none")"
        let requiresFit = context.coordinator.contentID != contentID
        if context.coordinator.revision != revision || context.coordinator.settings != settings || requiresFit {
            guard let scene = view.scene else { return }
            MolecularSceneBuilder.rebuild(
                scene: scene,
                structure: structure,
                volume: volume,
                settings: settings,
                selection: selectedAtomIDs
            )
            if requiresFit {
                MolecularSceneBuilder.fitCamera(scene: scene, structure: structure, volume: volume)
                view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
            }
            context.coordinator.revision = revision
            context.coordinator.settings = settings
            context.coordinator.contentID = contentID
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: SCNView?
        var onSelectAtom: (Int) -> Void
        var revision = -1
        var settings: RenderSettings?
        var contentID = ""

        init(onSelectAtom: @escaping (Int) -> Void) {
            self.onSelectAtom = onSelectAtom
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            let point = recognizer.location(in: view)
            let hit = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true
            ]).first
            var node = hit?.node
            while let current = node {
                if let name = current.name, name.hasPrefix("atom:"), let id = Int(name.dropFirst(5)) {
                    onSelectAtom(id)
                    return
                }
                node = current.parent
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
