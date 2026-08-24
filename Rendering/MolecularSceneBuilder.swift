import SceneKit
import SwiftUI
import simd

@MainActor
enum MolecularSceneBuilder {
    private struct SpatialCell: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }
    private struct SurfaceCacheKey: Hashable {
        let structureID: UUID
        let atomCount: Int
        let probeHundredths: Int
        let style: MolecularSurfaceStyle
    }

    private static var molecularSurfaceCache: [SurfaceCacheKey: SCNGeometry] = [:]

    static func exportScene(
        structure: MolecularStructure?,
        volume: VolumeMap?,
        settings: RenderSettings,
        selection: [Int],
        interactions: [MolecularInteraction],
        cavities: [MolecularCavity],
        customPseudobonds: [CustomPseudobond] = []
    ) -> SCNScene {
        let scene = SCNScene()
        configureScene(scene)
        rebuild(
            scene: scene, structure: structure, volume: volume, settings: settings,
            selection: selection, interactions: interactions, cavities: cavities,
            customPseudobonds: customPseudobonds
        )
        fitCamera(scene: scene, structure: structure, volume: volume, direction: settings.viewDirection)
        scene.background.contents = UIColor(settings.backgroundColor)
        return scene
    }

    static func snapshot(
        structure: MolecularStructure?,
        volume: VolumeMap?,
        settings: RenderSettings,
        selection: [Int],
        interactions: [MolecularInteraction],
        cavities: [MolecularCavity],
        customPseudobonds: [CustomPseudobond] = [],
        size: CGSize = CGSize(width: 2048, height: 2048)
    ) -> UIImage {
        let scene = exportScene(
            structure: structure, volume: volume, settings: settings,
            selection: selection, interactions: interactions, cavities: cavities,
            customPseudobonds: customPseudobonds
        )
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

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
        keyNode.name = "key-light"
        keyNode.eulerAngles = SCNVector3(-0.7, 0.8, 0)
        keyNode.light = key
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 430
        fill.color = UIColor(white: 0.72, alpha: 1)
        let fillNode = SCNNode()
        fillNode.name = "fill-light"
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
    }

    static func rebuild(
        scene: SCNScene,
        structure: MolecularStructure?,
        volume: VolumeMap?,
        settings: RenderSettings,
        selection: [Int],
        interactions: [MolecularInteraction] = [],
        cavities: [MolecularCavity] = [],
        customPseudobonds: [CustomPseudobond] = []
    ) {
        scene.rootNode.childNode(withName: "content", recursively: false)?.removeFromParentNode()
        let content = SCNNode()
        content.name = "content"
        scene.rootNode.addChildNode(content)
        updateEnvironment(scene: scene, settings: settings)

        if settings.showAtoms, let structure {
            addStructure(structure, settings: settings, selection: Set(selection.prefix(2_000)), to: content)
        }
        if settings.showMolecularSurface, let structure,
           let baseGeometry = molecularSurfaceGeometry(
               for: structure,
               probeRadius: settings.molecularSurfaceProbeRadius,
               style: settings.molecularSurfaceStyle
           ) {
            let geometry = settings.molecularSurfaceColorMode == .uniform
                ? baseGeometry
                : propertyColoredSurface(baseGeometry, structure: structure, mode: settings.molecularSurfaceColorMode)
            let material = SCNMaterial()
            material.diffuse.contents = settings.molecularSurfaceColorMode == .uniform
                ? UIColor(settings.molecularSurfaceColor)
                : UIColor.white
            material.emission.contents = UIColor(settings.molecularSurfaceColor).withAlphaComponent(0.04)
            material.transparency = settings.molecularSurfaceOpacity
            material.isDoubleSided = true
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.44
            material.metalness.contents = 0.02
            material.fillMode = settings.molecularSurfaceStyle == .mesh ? .lines : .fill
            if settings.molecularSurfaceStyle == .dots {
                material.lightingModel = .constant
                material.writesToDepthBuffer = true
                material.readsFromDepthBuffer = true
            }
            geometry.materials = [material]
            let surfaceNode = SCNNode(geometry: geometry)
            surfaceNode.name = "molecular-surface"
            content.addChildNode(surfaceNode)
        }
        if settings.showMap, let volume {
            let geometry: SCNGeometry?
            switch settings.volumeDisplayStyle {
            case .surface:
                geometry = IsosurfaceBuilder.geometry(volume: volume, threshold: settings.mapThreshold)
            case .volume:
                geometry = volumePointGeometry(volume, threshold: settings.mapThreshold, slices: nil)
            case .slices:
                geometry = volumePointGeometry(
                    volume,
                    threshold: settings.mapThreshold,
                    slices: (settings.sliceX, settings.sliceY, settings.sliceZ)
                )
            }
            if let geometry {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(settings.mapColor)
            material.emission.contents = UIColor(settings.mapColor).withAlphaComponent(0.06)
            material.transparency = settings.mapOpacity
            material.isDoubleSided = true
            material.lightingModel = .physicallyBased
            material.fillMode = settings.mapWireframe ? .lines : .fill
            if settings.volumeDisplayStyle != .surface {
                material.lightingModel = .constant
                geometry.elements.forEach {
                    $0.pointSize = settings.volumeDisplayStyle == .slices ? 4 : 3
                    $0.minimumPointScreenSpaceRadius = 1
                    $0.maximumPointScreenSpaceRadius = 6
                }
            }
            geometry.materials = [material]
            let mapNode = SCNNode(geometry: geometry)
            mapNode.name = "density-map"
            content.addChildNode(mapNode)
            }
        }
        if (2...4).contains(selection.count), let structure {
            let atomByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
            let measuredAtoms = selection.compactMap { atomByID[$0] }
            for pair in zip(measuredAtoms, measuredAtoms.dropFirst()) {
                let measurement = cylinder(
                    from: pair.0.position,
                    to: pair.1.position,
                    radius: 0.035,
                    color: .systemYellow
                )
                measurement.name = "measurement"
                content.addChildNode(measurement)
            }
            if settings.showSelectionArrow, measuredAtoms.count >= 2 {
                content.addChildNode(arrow(
                    from: measuredAtoms[0].position,
                    to: measuredAtoms[1].position,
                    color: .systemOrange
                ))
            }
        }
        if let structure, !interactions.isEmpty {
            let atomByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
            for interaction in interactions.prefix(12_000) {
                guard let first = atomByID[interaction.atom1], let second = atomByID[interaction.atom2] else { continue }
                let color: UIColor = switch interaction.kind {
                case .hydrogenBond: .systemCyan
                case .contact: .systemGreen
                case .clash: .systemRed
                }
                let node = cylinder(from: first.position, to: second.position, radius: 0.025, color: color)
                node.name = "pseudobond:\(interaction.kind.rawValue)"
                content.addChildNode(node)
            }
        }
        if let structure, !customPseudobonds.isEmpty {
            let atomByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
            for bond in customPseudobonds.prefix(12_000) {
                guard let first = atomByID[bond.atom1], let second = atomByID[bond.atom2] else { continue }
                let components = bond.color
                let color = components.count >= 4
                    ? UIColor(
                        red: CGFloat(components[0]), green: CGFloat(components[1]),
                        blue: CGFloat(components[2]), alpha: CGFloat(components[3])
                    )
                    : UIColor.systemOrange
                let node = cylinder(from: first.position, to: second.position, radius: 0.035, color: color)
                node.name = "custom-pseudobond:\(bond.group)"
                content.addChildNode(node)
            }
        }
        for cavity in cavities.prefix(100) {
            let radius = max(0.35, min(4, pow(3 * cavity.volume / (4 * Float.pi), 1 / 3)))
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 16
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.14)
            material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.12)
            material.fillMode = .lines
            material.isDoubleSided = true
            sphere.materials = [material]
            let node = SCNNode(geometry: sphere)
            node.name = "cavity:\(cavity.id)"
            node.position = SCNVector3(cavity.center.x, cavity.center.y, cavity.center.z)
            content.addChildNode(node)
        }
        if let structure {
            addLabels(structure, settings: settings, selection: Set(selection), to: content)
            if settings.showAxes { addAxes(center: structure.center, radius: structure.radius, to: content) }
            if settings.showScaleBar { addScaleBar(structure: structure, labelColor: UIColor(settings.labelColor), to: content) }
        }
    }

    private static func molecularSurfaceGeometry(
        for structure: MolecularStructure,
        probeRadius: Float,
        style: MolecularSurfaceStyle
    ) -> SCNGeometry? {
        let key = SurfaceCacheKey(
            structureID: structure.id,
            atomCount: structure.atoms.count,
            probeHundredths: Int((probeRadius * 100).rounded()),
            style: style
        )
        if let cached = molecularSurfaceCache[key] { return cached }
        let geometry: SCNGeometry?
        if style == .dots {
            geometry = molecularSurfaceDotGeometry(for: structure, probeRadius: probeRadius)
        } else if let grid = MolecularSurfaceGridBuilder().build(
            structure: structure,
            probeRadius: probeRadius
        ) {
            geometry = IsosurfaceBuilder.geometry(volume: grid, threshold: 0)
        } else {
            geometry = nil
        }
        guard let geometry else { return nil }

        if molecularSurfaceCache.count >= 4 {
            molecularSurfaceCache.removeValue(forKey: molecularSurfaceCache.keys.first!)
        }
        molecularSurfaceCache[key] = geometry
        return geometry
    }

    private static func propertyColoredSurface(
        _ geometry: SCNGeometry,
        structure: MolecularStructure,
        mode: MolecularSurfaceColorMode
    ) -> SCNGeometry {
        guard let vertexSource = geometry.sources(for: .vertex).first,
              vertexSource.usesFloatComponents,
              vertexSource.componentsPerVector >= 3,
              vertexSource.bytesPerComponent == 4 else { return geometry }
        let atoms = structure.atoms
        guard !atoms.isEmpty else { return geometry }
        let bValues = atoms.map(\.bFactor)
        let bMinimum = bValues.min() ?? 0
        let bRange = max(0.001, (bValues.max() ?? 1) - bMinimum)
        let cellSize: Float = 5
        func cell(for position: Vector3) -> SpatialCell {
            SpatialCell(
                x: Int(floor(position.x / cellSize)),
                y: Int(floor(position.y / cellSize)),
                z: Int(floor(position.z / cellSize))
            )
        }
        var buckets: [SpatialCell: [Atom]] = [:]
        for atom in atoms { buckets[cell(for: atom.position), default: []].append(atom) }
        var colors: [SIMD4<Float>] = []
        colors.reserveCapacity(vertexSource.vectorCount)
        for index in 0..<vertexSource.vectorCount {
            let offset = vertexSource.dataOffset + index * vertexSource.dataStride
            let position = vertexSource.data.withUnsafeBytes { raw -> Vector3 in
                Vector3(
                    x: raw.loadUnaligned(fromByteOffset: offset, as: Float.self),
                    y: raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                    z: raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
                )
            }
            let origin = cell(for: position)
            var candidates: [Atom] = []
            for z in (origin.z - 1)...(origin.z + 1) {
                for y in (origin.y - 1)...(origin.y + 1) {
                    for x in (origin.x - 1)...(origin.x + 1) {
                        candidates.append(contentsOf: buckets[SpatialCell(x: x, y: y, z: z)] ?? [])
                    }
                }
            }
            let atom = candidates.min {
                ($0.position - position).length < ($1.position - position).length
            } ?? atoms[0]
            let color: UIColor
            switch mode {
            case .uniform:
                color = .white
            case .element:
                color = self.color(for: atom, mode: .element)
            case .chain:
                color = self.color(for: atom, mode: .chain)
            case .residue:
                color = self.color(for: atom, mode: .residue)
            case .bFactor:
                let value = CGFloat((atom.bFactor - bMinimum) / bRange)
                color = UIColor(red: value, green: 0.25, blue: 1 - value, alpha: 1)
            case .charge:
                let value = CGFloat(min(1, max(-1, atom.partialCharge)))
                color = value >= 0
                    ? UIColor(red: 1, green: 1 - value * 0.8, blue: 1 - value * 0.8, alpha: 1)
                    : UIColor(red: 1 + value * 0.8, green: 1 + value * 0.8, blue: 1, alpha: 1)
            }
            var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            colors.append(SIMD4(Float(red), Float(green), Float(blue), Float(alpha)))
        }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: colors.count,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
            dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let sources = geometry.sources.filter { $0.semantic != .color } + [colorSource]
        return SCNGeometry(sources: sources, elements: geometry.elements)
    }

    private static func molecularSurfaceDotGeometry(for structure: MolecularStructure, probeRadius: Float) -> SCNGeometry? {
        let directions: [Vector3] = [
            Vector3(x: 1, y: 0, z: 0), Vector3(x: -1, y: 0, z: 0),
            Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: -1, z: 0),
            Vector3(x: 0, y: 0, z: 1), Vector3(x: 0, y: 0, z: -1),
            Vector3(x: 0.577, y: 0.577, z: 0.577), Vector3(x: -0.577, y: 0.577, z: 0.577),
            Vector3(x: 0.577, y: -0.577, z: 0.577), Vector3(x: 0.577, y: 0.577, z: -0.577),
            Vector3(x: -0.577, y: -0.577, z: 0.577), Vector3(x: -0.577, y: 0.577, z: -0.577),
            Vector3(x: 0.577, y: -0.577, z: -0.577), Vector3(x: -0.577, y: -0.577, z: -0.577)
        ]
        var points: [SCNVector3] = []
        for atom in structure.atoms.prefix(8_000) {
            let radius = ElementTable.vanDerWaalsRadius(for: atom.element) + probeRadius
            for direction in directions {
                points.append(SCNVector3(
                    atom.position.x + direction.x * radius,
                    atom.position.y + direction.y * radius,
                    atom.position.z + direction.z * radius
                ))
            }
        }
        guard !points.isEmpty else { return nil }
        let indices = (0..<points.count).map(UInt32.init)
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 3
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: points)],
            elements: [element]
        )
    }

    private static func volumePointGeometry(
        _ volume: VolumeMap,
        threshold: Float,
        slices: (Double, Double, Double)?
    ) -> SCNGeometry? {
        let d = volume.dimensions
        let sliceIndices = slices.map {
            (
                x: min(d.x - 1, max(0, Int((Double(d.x - 1) * $0.0).rounded()))),
                y: min(d.y - 1, max(0, Int((Double(d.y - 1) * $0.1).rounded()))),
                z: min(d.z - 1, max(0, Int((Double(d.z - 1) * $0.2).rounded())))
            )
        }
        let strideValue = max(1, Int(ceil(pow(Double(max(1, volume.values.count)) / 90_000, 1.0 / 3.0))))
        var points: [SCNVector3] = []
        for z in Swift.stride(from: 0, to: d.z, by: strideValue) {
            for y in Swift.stride(from: 0, to: d.y, by: strideValue) {
                for x in Swift.stride(from: 0, to: d.x, by: strideValue) {
                    if let sliceIndices,
                       abs(x - sliceIndices.x) >= strideValue,
                       abs(y - sliceIndices.y) >= strideValue,
                       abs(z - sliceIndices.z) >= strideValue { continue }
                    guard volume.value(x: x, y: y, z: z) >= threshold else { continue }
                    points.append(SCNVector3(
                        volume.origin.x + Float(x) * volume.spacing.x,
                        volume.origin.y + Float(y) * volume.spacing.y,
                        volume.origin.z + Float(z) * volume.spacing.z
                    ))
                }
            }
        }
        guard !points.isEmpty else { return nil }
        let indices = (0..<points.count).map(UInt32.init)
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [element])
    }

    private static func updateEnvironment(scene: SCNScene, settings: RenderSettings) {
        let key = scene.rootNode.childNode(withName: "key-light", recursively: false)?.light
        let fill = scene.rootNode.childNode(withName: "fill-light", recursively: false)?.light
        switch settings.lightingPreset {
        case .studio:
            key?.intensity = 1_150; fill?.intensity = 430
        case .soft:
            key?.intensity = 760; fill?.intensity = 680
        case .flat:
            key?.intensity = 250; fill?.intensity = 900
        case .dramatic:
            key?.intensity = 1_750; fill?.intensity = 140
        }
        if let camera = scene.rootNode.childNode(withName: "camera", recursively: false)?.camera {
            camera.zNear = max(0.001, settings.nearClip)
            camera.zFar = max(camera.zNear + 1, settings.farClip)
        }
    }

    static func fitCamera(
        scene: SCNScene,
        structure: MolecularStructure?,
        volume: VolumeMap?,
        direction: ViewDirection = .front
    ) {
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
        let distance = max(8, radius * 3.1)
        switch direction {
        case .front: cameraNode.position = SCNVector3(center.x, center.y, center.z + distance)
        case .back: cameraNode.position = SCNVector3(center.x, center.y, center.z - distance)
        case .left: cameraNode.position = SCNVector3(center.x - distance, center.y, center.z)
        case .right: cameraNode.position = SCNVector3(center.x + distance, center.y, center.z)
        case .top: cameraNode.position = SCNVector3(center.x, center.y + distance, center.z)
        case .bottom: cameraNode.position = SCNVector3(center.x, center.y - distance, center.z)
        }
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
    }

    private static func addLabels(
        _ structure: MolecularStructure,
        settings: RenderSettings,
        selection: Set<Int>,
        to parent: SCNNode
    ) {
        let entries: [(String, Vector3)]
        switch settings.labelStyle {
        case .none:
            return
        case .selected:
            entries = structure.atoms.filter { selection.contains($0.id) }.prefix(150).map {
                ("\($0.name)  \($0.residueName) \($0.residueNumber)", $0.position)
            }
        case .atoms:
            entries = structure.atoms.prefix(300).map { ($0.name, $0.position) }
        case .residues:
            var seen = Set<String>()
            entries = structure.atoms.compactMap { atom in
                let key = "\(atom.chainID):\(atom.residueNumber)"
                guard (atom.name.uppercased() == "CA" || atom.name.uppercased() == "P"), seen.insert(key).inserted else { return nil }
                return ("\(atom.residueName) \(atom.residueNumber)", atom.position)
            }.prefix(300).map { $0 }
        case .chains:
            var seen = Set<String>()
            entries = structure.atoms.compactMap { atom in
                guard seen.insert(atom.chainID).inserted else { return nil }
                return (atom.chainID.isEmpty ? "Chain —" : "Chain \(atom.chainID)", atom.position)
            }.prefix(100).map { $0 }
        }
        for entry in entries {
            parent.addChildNode(textNode(entry.0, at: entry.1, color: UIColor(settings.labelColor), scale: 0.018))
        }
    }

    private static func textNode(_ text: String, at position: Vector3, color: UIColor, scale: Float) -> SCNNode {
        let geometry = SCNText(string: text, extrusionDepth: 0.05)
        geometry.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        geometry.flatness = 0.2
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.22)
        material.isDoubleSided = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(position.x + 0.18, position.y + 0.18, position.z)
        node.scale = SCNVector3(scale, scale, scale)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    private static func addAxes(center: Vector3, radius: Float, to parent: SCNNode) {
        let length = max(2, min(8, radius * 0.35))
        parent.addChildNode(cylinder(from: center, to: center + Vector3(x: length, y: 0, z: 0), radius: 0.055, color: .systemRed))
        parent.addChildNode(cylinder(from: center, to: center + Vector3(x: 0, y: length, z: 0), radius: 0.055, color: .systemGreen))
        parent.addChildNode(cylinder(from: center, to: center + Vector3(x: 0, y: 0, z: length), radius: 0.055, color: .systemBlue))
    }

    private static func addScaleBar(structure: MolecularStructure, labelColor: UIColor, to parent: SCNNode) {
        let length: Float = structure.radius > 35 ? 20 : (structure.radius > 12 ? 10 : 5)
        let start = structure.center + Vector3(x: -structure.radius * 0.75, y: -structure.radius * 0.85, z: 0)
        let end = start + Vector3(x: length, y: 0, z: 0)
        parent.addChildNode(cylinder(from: start, to: end, radius: 0.065, color: labelColor))
        parent.addChildNode(textNode("\(Int(length)) Å", at: end, color: labelColor, scale: 0.02))
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
        if settings.representation == .nucleotides || settings.representation == .glycans {
            let nucleotideNames = Set(["A", "C", "G", "U", "T", "DA", "DC", "DG", "DT", "DU", "ADE", "CYT", "GUA", "URI", "THY"])
            let glycanNames = Set(["NAG", "NDG", "BMA", "MAN", "FUC", "GAL", "GLC", "SIA", "NAN", "FUL", "XYS", "BGC"])
            let allowed = settings.representation == .nucleotides ? nucleotideNames : glycanNames
            let filteredAtoms = structure.atoms.filter { allowed.contains($0.residueName.uppercased()) }
            let visible = Set(filteredAtoms.map(\.id))
            guard !filteredAtoms.isEmpty else { return }
            var specializedSettings = settings
            specializedSettings.representation = settings.representation == .nucleotides ? .backbone : .ballAndStick
            let filtered = MolecularStructure(
                id: structure.id,
                name: structure.name,
                atoms: filteredAtoms,
                bonds: structure.bonds.filter { visible.contains($0.atom1) && visible.contains($0.atom2) },
                secondaryStructure: structure.secondaryStructure
            )
            addStructure(filtered, settings: specializedSettings, selection: selection, to: parent)
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
            case .thermal: radius = max(0.16, CGFloat(ElementTable.covalentRadius(for: atom.element)) * 0.36)
            case .nucleotides, .glycans: radius = 0.2
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
            if settings.representation == .thermal {
                let thermalScale = max(0.55, min(2.4, sqrt(max(0.01, atom.bFactor) / 20)))
                node.scale = SCNVector3(thermalScale * 1.18, thermalScale * 0.88, thermalScale)
            }
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

    private static func arrow(from a: Vector3, to b: Vector3, color: UIColor) -> SCNNode {
        let parent = SCNNode()
        let start = SIMD3<Float>(a.x, a.y, a.z)
        let end = SIMD3<Float>(b.x, b.y, b.z)
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.25 else { return parent }
        let direction = delta / length
        let headLength = min(0.8, length * 0.28)
        let shaftEnd = end - direction * headLength
        parent.addChildNode(cylinder(
            from: a,
            to: vector3(shaftEnd),
            radius: 0.08,
            color: color
        ))
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.22, height: CGFloat(headLength))
        cone.radialSegmentCount = 16
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        cone.materials = [material]
        let node = SCNNode(geometry: cone)
        node.simdPosition = (shaftEnd + end) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        parent.addChildNode(node)
        return parent
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
