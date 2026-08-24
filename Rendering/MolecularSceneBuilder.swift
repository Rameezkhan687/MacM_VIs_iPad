import SceneKit
import SwiftUI
import simd

@MainActor
enum MolecularSceneBuilder {
    static func configureScene(_ scene: SCNScene) {
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.05
        camera.zFar = 10_000
        camera.wantsHDR = true
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 35)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1_150
        key.castsShadow = false
        let keyNode = SCNNode()
        keyNode.eulerAngles = SCNVector3(-0.7, 0.8, 0)
        keyNode.light = key
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 430
        fill.color = UIColor(white: 0.72, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    static func rebuild(
        scene: SCNScene,
        structure: MolecularStructure?,
        volume: VolumeMap?,
        settings: RenderSettings,
        selection: [Int]
    ) {
        scene.rootNode.childNode(withName: "content", recursively: false)?.removeFromParentNode()
        let content = SCNNode()
        content.name = "content"
        scene.rootNode.addChildNode(content)

        if settings.showAtoms, let structure {
            addStructure(structure, settings: settings, selection: Set(selection), to: content)
        }
        if settings.showMap, let volume,
           let geometry = IsosurfaceBuilder.geometry(volume: volume, threshold: settings.mapThreshold) {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(settings.mapColor)
            material.emission.contents = UIColor(settings.mapColor).withAlphaComponent(0.06)
            material.transparency = settings.mapOpacity
            material.isDoubleSided = true
            material.lightingModel = .physicallyBased
            material.fillMode = settings.mapWireframe ? .lines : .fill
            geometry.materials = [material]
            let mapNode = SCNNode(geometry: geometry)
            mapNode.name = "density-map"
            content.addChildNode(mapNode)
        }
        if selection.count == 2, let structure,
           let first = structure.atoms.first(where: { $0.id == selection[0] }),
           let second = structure.atoms.first(where: { $0.id == selection[1] }) {
            let measurement = cylinder(from: first.position, to: second.position, radius: 0.035, color: .systemYellow)
            measurement.name = "measurement"
            content.addChildNode(measurement)
        }
    }

    static func fitCamera(scene: SCNScene, structure: MolecularStructure?, volume: VolumeMap?) {
        guard let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }
        var center = structure?.center ?? .zero
        var radius = structure?.radius ?? 5
        if structure == nil, let volume {
            center = Vector3(
                x: volume.origin.x + Float(volume.dimensions.x - 1) * volume.spacing.x / 2,
                y: volume.origin.y + Float(volume.dimensions.y - 1) * volume.spacing.y / 2,
                z: volume.origin.z + Float(volume.dimensions.z - 1) * volume.spacing.z / 2
            )
            radius = max(
                Float(volume.dimensions.x) * volume.spacing.x,
                Float(volume.dimensions.y) * volume.spacing.y,
                Float(volume.dimensions.z) * volume.spacing.z
            ) / 2
        }
        cameraNode.position = SCNVector3(center.x, center.y, center.z + max(8, radius * 3.1))
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        cameraNode.camera?.zNear = Double(max(0.01, radius * 0.01))
        cameraNode.camera?.zFar = Double(max(1_000, radius * 20))
    }

    private static func addStructure(
        _ structure: MolecularStructure,
        settings: RenderSettings,
        selection: Set<Int>,
        to parent: SCNNode
    ) {
        let atoms: [Atom]
        if settings.representation == .backbone {
            atoms = structure.atoms.filter { $0.name.uppercased() == "CA" || $0.name.uppercased() == "P" }
        } else {
            atoms = Array(structure.atoms.prefix(40_000))
        }
        let visibleIDs = Set(atoms.map(\.id))

        if settings.representation != .spacefill {
            let bonds: [Bond]
            if settings.representation == .backbone {
                bonds = zip(atoms, atoms.dropFirst()).compactMap { a, b in
                    guard a.chainID == b.chainID, abs(a.residueNumber - b.residueNumber) <= 1 else { return nil }
                    return Bond(atom1: a.id, atom2: b.id)
                }
            } else {
                bonds = structure.bonds.filter { visibleIDs.contains($0.atom1) && visibleIDs.contains($0.atom2) }
            }
            let atomByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
            for bond in bonds.prefix(80_000) {
                guard let a = atomByID[bond.atom1], let b = atomByID[bond.atom2] else { continue }
                let color = blendedColor(color(for: a, mode: settings.colorMode), color(for: b, mode: settings.colorMode))
                let radius: CGFloat = settings.representation == .sticks ? 0.16 : (settings.representation == .backbone ? 0.13 : 0.09)
                parent.addChildNode(cylinder(
                    from: a.position,
                    to: b.position,
                    radius: radius * CGFloat(settings.bondScale),
                    color: color
                ))
            }
        }

        for atom in atoms {
            let radius: CGFloat
            switch settings.representation {
            case .spacefill: radius = CGFloat(ElementTable.vanDerWaalsRadius(for: atom.element)) * 0.62
            case .sticks: radius = 0.18
            case .backbone: radius = 0.22
            case .ballAndStick: radius = CGFloat(ElementTable.covalentRadius(for: atom.element)) * 0.48
            }
            let sphere = SCNSphere(radius: radius * CGFloat(settings.atomScale))
            sphere.segmentCount = structure.atoms.count > 8_000 ? 8 : 16
            let material = SCNMaterial()
            material.diffuse.contents = color(for: atom, mode: settings.colorMode)
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.3
            material.metalness.contents = 0.03
            sphere.materials = [material]
            let node = SCNNode(geometry: sphere)
            node.name = "atom:\(atom.id)"
            node.position = SCNVector3(atom.position.x, atom.position.y, atom.position.z)
            parent.addChildNode(node)

            if selection.contains(atom.id) {
                let halo = SCNSphere(radius: radius * CGFloat(settings.atomScale) + 0.12)
                let haloMaterial = SCNMaterial()
                haloMaterial.diffuse.contents = UIColor.clear
                haloMaterial.emission.contents = UIColor.systemYellow
                haloMaterial.transparency = 0.78
                haloMaterial.fillMode = .lines
                halo.materials = [haloMaterial]
                node.addChildNode(SCNNode(geometry: halo))
            }
        }
    }

    private static func cylinder(from a: Vector3, to b: Vector3, radius: CGFloat, color: UIColor) -> SCNNode {
        let start = SIMD3<Float>(a.x, a.y, a.z)
        let end = SIMD3<Float>(b.x, b.y, b.z)
        let delta = end - start
        let length = simd_length(delta)
        let geometry = SCNCylinder(radius: radius, height: CGFloat(length))
        geometry.radialSegmentCount = 10
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.simdPosition = (start + end) / 2
        if length > 0.0001 {
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: delta / length)
        }
        return node
    }

    private static func color(for atom: Atom, mode: AtomColorMode) -> UIColor {
        switch mode {
        case .element:
            switch ElementTable.normalized(atom.element) {
            case "H": return UIColor(white: 0.92, alpha: 1)
            case "C": return UIColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1)
            case "N": return UIColor(red: 0.19, green: 0.42, blue: 0.96, alpha: 1)
            case "O": return UIColor(red: 0.95, green: 0.22, blue: 0.26, alpha: 1)
            case "S": return UIColor(red: 0.98, green: 0.79, blue: 0.12, alpha: 1)
            case "P": return UIColor(red: 1.0, green: 0.47, blue: 0.08, alpha: 1)
            default: return UIColor(red: 0.18, green: 0.78, blue: 0.67, alpha: 1)
            }
        case .chain:
            return palette(index: abs(atom.chainID.hashValue))
        case .residue:
            return palette(index: abs(atom.residueName.hashValue))
        case .monochrome:
            return UIColor(red: 0.20, green: 0.72, blue: 0.91, alpha: 1)
        }
    }

    private static func palette(index: Int) -> UIColor {
        let colors: [UIColor] = [
            .systemTeal, .systemOrange, .systemIndigo, .systemPink,
            .systemGreen, .systemPurple, .systemCyan, .systemYellow
        ]
        return colors[index % colors.count]
    }

    private static func blendedColor(_ a: UIColor, _ b: UIColor) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: (ar + br) / 2, green: (ag + bg) / 2, blue: (ab + bb) / 2, alpha: 1)
    }
}
