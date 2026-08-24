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
        if settings.representation == .cartoon {
            addCartoon(structure, settings: settings, selection: selection, to: parent)
            return
        }

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
            case .cartoon: radius = 0.22
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

    private struct CartoonResidue {
        let atom: Atom
        let kind: SecondaryStructureKind
    }

    private static func addCartoon(
        _ structure: MolecularStructure,
        settings: RenderSettings,
        selection: Set<Int>,
        to parent: SCNNode
    ) {
        let chains = cartoonChains(structure)
        for chain in chains {
            for fragment in contiguousFragments(chain) {
                addCartoonFragment(fragment, settings: settings, to: parent)
            }
        }
        addSelectionMarkers(structure: structure, selection: selection, to: parent)
    }

    private static func cartoonChains(_ structure: MolecularStructure) -> [[CartoonResidue]] {
        var chainOrder: [String] = []
        var chains: [String: [CartoonResidue]] = [:]
        var seenResidues = Set<String>()

        for atom in structure.atoms.prefix(200_000) {
            let atomName = atom.name.uppercased()
            guard atomName == "CA" || atomName == "P" else { continue }
            let residueKey = "\(atom.chainID):\(atom.residueNumber)"
            guard seenResidues.insert(residueKey).inserted else { continue }
            if chains[atom.chainID] == nil {
                chainOrder.append(atom.chainID)
                chains[atom.chainID] = []
            }
            chains[atom.chainID, default: []].append(CartoonResidue(
                atom: atom,
                kind: structure.secondaryStructureKind(
                    chainID: atom.chainID,
                    residueNumber: atom.residueNumber
                )
            ))
        }
        return chainOrder.compactMap { chains[$0] }
    }

    private static func contiguousFragments(_ residues: [CartoonResidue]) -> [[CartoonResidue]] {
        guard !residues.isEmpty else { return [] }
        var fragments: [[CartoonResidue]] = [[residues[0]]]
        for residue in residues.dropFirst() {
            guard let previous = fragments.last?.last else { continue }
            let residueGap = residue.atom.residueNumber - previous.atom.residueNumber
            let distance = (residue.atom.position - previous.atom.position).length
            if residueGap <= 0 || residueGap > 1 || distance > 7 {
                fragments.append([residue])
            } else {
                fragments[fragments.count - 1].append(residue)
            }
        }
        return fragments
    }

    private static func addCartoonFragment(
        _ residues: [CartoonResidue],
        settings: RenderSettings,
        to parent: SCNNode
    ) {
        guard !residues.isEmpty else { return }
        var runStart = 0
        while runStart < residues.count {
            var runEnd = runStart
            while runEnd + 1 < residues.count, residues[runEnd + 1].kind == residues[runStart].kind {
                runEnd += 1
            }

            let displayStart = max(0, runStart - 1)
            let displayEnd = min(residues.count - 1, runEnd + 1)
            let run = Array(residues[displayStart...displayEnd])
            let kind = residues[runStart].kind
            let color = cartoonColor(for: kind, atom: residues[runStart].atom, mode: settings.colorMode)
            let scale = Float(settings.atomScale)

            switch kind {
            case .helix:
                if let geometry = ribbonGeometry(
                    points: run.map(\.atom.position),
                    halfWidth: 0.62 * scale,
                    arrowhead: false,
                    color: color
                ) {
                    let node = SCNNode(geometry: geometry)
                    node.name = "atom:\(residues[(runStart + runEnd) / 2].atom.id)"
                    parent.addChildNode(node)
                }
            case .sheet:
                if let geometry = ribbonGeometry(
                    points: run.map(\.atom.position),
                    halfWidth: 0.82 * scale,
                    arrowhead: true,
                    color: color
                ) {
                    let node = SCNNode(geometry: geometry)
                    node.name = "atom:\(residues[(runStart + runEnd) / 2].atom.id)"
                    parent.addChildNode(node)
                }
            case .coil:
                addCoil(
                    points: run.map(\.atom.position),
                    atomID: residues[(runStart + runEnd) / 2].atom.id,
                    radius: CGFloat(0.16 * scale),
                    color: color,
                    to: parent
                )
            }
            runStart = runEnd + 1
        }
    }

    private static func addCoil(
        points: [Vector3],
        atomID: Int,
        radius: CGFloat,
        color: UIColor,
        to parent: SCNNode
    ) {
        let smoothed = smooth(points)
        if smoothed.count == 1, let point = smoothed.first {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 10
            sphere.materials = [cartoonMaterial(color: color)]
            let node = SCNNode(geometry: sphere)
            node.name = "atom:\(atomID)"
            node.simdPosition = point
            parent.addChildNode(node)
            return
        }
        for (index, pair) in zip(smoothed, smoothed.dropFirst()).enumerated() {
            let node = cylinder(
                from: vector3(pair.0),
                to: vector3(pair.1),
                radius: radius,
                color: color
            )
            node.name = index == smoothed.count / 2 ? "atom:\(atomID)" : "cartoon-coil"
            parent.addChildNode(node)
        }
    }

    private static func ribbonGeometry(
        points: [Vector3],
        halfWidth: Float,
        arrowhead: Bool,
        color: UIColor
    ) -> SCNGeometry? {
        let centers = smooth(points)
        guard centers.count >= 2 else { return nil }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var previousWidth = SIMD3<Float>(1, 0, 0)
        vertices.reserveCapacity(centers.count * 2)
        normals.reserveCapacity(centers.count * 2)

        for index in centers.indices {
            let previous = centers[max(0, index - 1)]
            let next = centers[min(centers.count - 1, index + 1)]
            var tangent = next - previous
            if simd_length_squared(tangent) < 0.000_001 { tangent = SIMD3<Float>(0, 0, 1) }
            tangent = simd_normalize(tangent)

            var width = previousWidth - tangent * simd_dot(previousWidth, tangent)
            if simd_length_squared(width) < 0.000_1 {
                let reference = abs(tangent.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                width = simd_cross(tangent, reference)
            }
            width = simd_normalize(width)
            if simd_dot(width, previousWidth) < 0 { width = -width }
            previousWidth = width

            let widthScale = ribbonWidthScale(index: index, count: centers.count, arrowhead: arrowhead)
            let offset = width * halfWidth * widthScale
            let normalVector = simd_normalize(simd_cross(tangent, width))
            vertices.append(SCNVector3(centers[index] - offset))
            vertices.append(SCNVector3(centers[index] + offset))
            let normal = SCNVector3(normalVector)
            normals.append(contentsOf: [normal, normal])
        }

        var indices: [Int32] = []
        indices.reserveCapacity((centers.count - 1) * 6)
        for index in 0..<(centers.count - 1) {
            let left = Int32(index * 2)
            indices.append(contentsOf: [left, left + 1, left + 2, left + 1, left + 3, left + 2])
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [cartoonMaterial(color: color)]
        return geometry
    }

    private static func ribbonWidthScale(index: Int, count: Int, arrowhead: Bool) -> Float {
        guard arrowhead, count > 2 else { return 1 }
        let progress = Float(index) / Float(count - 1)
        if progress < 0.68 { return 1 }
        if progress < 0.82 { return 1 + (progress - 0.68) / 0.14 * 0.55 }
        return max(0.025, (1 - progress) / 0.18 * 1.55)
    }

    private static func smooth(_ points: [Vector3], subdivisions: Int = 4) -> [SIMD3<Float>] {
        let vectors = points.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        guard vectors.count > 1 else { return vectors }
        var result: [SIMD3<Float>] = []
        result.reserveCapacity((vectors.count - 1) * subdivisions + 1)
        for index in 0..<(vectors.count - 1) {
            let p0 = vectors[max(0, index - 1)]
            let p1 = vectors[index]
            let p2 = vectors[index + 1]
            let p3 = vectors[min(vectors.count - 1, index + 2)]
            for step in 0..<subdivisions {
                let t = Float(step) / Float(subdivisions)
                let t2 = t * t
                let t3 = t2 * t
                let base = p1 * Float(2)
                let linear = (p2 - p0) * t
                var quadraticShape = p0 * Float(2)
                quadraticShape -= p1 * Float(5)
                quadraticShape += p2 * Float(4)
                quadraticShape -= p3
                let quadratic = quadraticShape * t2
                var cubicShape = -p0
                cubicShape += p1 * Float(3)
                cubicShape -= p2 * Float(3)
                cubicShape += p3
                let cubic = cubicShape * t3
                let firstHalf = base + linear
                let secondHalf = quadratic + cubic
                result.append((firstHalf + secondHalf) * Float(0.5))
            }
        }
        result.append(vectors[vectors.count - 1])
        return result
    }

    private static func addSelectionMarkers(
        structure: MolecularStructure,
        selection: Set<Int>,
        to parent: SCNNode
    ) {
        for atom in structure.atoms where selection.contains(atom.id) {
            let halo = SCNSphere(radius: 0.34)
            halo.segmentCount = 12
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.clear
            material.emission.contents = UIColor.systemYellow
            material.transparency = 0.9
            material.fillMode = .lines
            halo.materials = [material]
            let node = SCNNode(geometry: halo)
            node.name = "atom:\(atom.id)"
            node.position = SCNVector3(atom.position.x, atom.position.y, atom.position.z)
            parent.addChildNode(node)
        }
    }

    private static func cartoonColor(
        for kind: SecondaryStructureKind,
        atom: Atom,
        mode: AtomColorMode
    ) -> UIColor {
        guard mode == .element else { return color(for: atom, mode: mode) }
        switch kind {
        case .helix: return UIColor(red: 0.92, green: 0.28, blue: 0.38, alpha: 1)
        case .sheet: return UIColor(red: 0.96, green: 0.73, blue: 0.15, alpha: 1)
        case .coil: return UIColor(red: 0.22, green: 0.76, blue: 0.70, alpha: 1)
        }
    }

    private static func cartoonMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.36
        material.metalness.contents = 0.02
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        return material
    }

    private static func vector3(_ value: SIMD3<Float>) -> Vector3 {
        Vector3(x: value.x, y: value.y, z: value.z)
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
