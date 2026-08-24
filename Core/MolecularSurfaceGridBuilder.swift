import Foundation

public struct MolecularSurfaceGridBuilder: Sendable {
    public init() {}

    public func build(
        structure: MolecularStructure,
        probeRadius: Float = 1.4,
        maximumDimension: Int = 68
    ) -> VolumeMap? {
        let atoms = Array(structure.atoms.prefix(30_000))
        guard !atoms.isEmpty, maximumDimension >= 8 else { return nil }

        let padding = max(2.5, probeRadius + 1.5)
        let minimum = Vector3(
            x: (atoms.map(\.position.x).min() ?? 0) - padding,
            y: (atoms.map(\.position.y).min() ?? 0) - padding,
            z: (atoms.map(\.position.z).min() ?? 0) - padding
        )
        let maximum = Vector3(
            x: (atoms.map(\.position.x).max() ?? 0) + padding,
            y: (atoms.map(\.position.y).max() ?? 0) + padding,
            z: (atoms.map(\.position.z).max() ?? 0) + padding
        )
        let extents = maximum - minimum
        let longestExtent = max(extents.x, extents.y, extents.z)
        let spacing = max(0.65, longestExtent / Float(maximumDimension - 1))
        let dimensions = (
            x: max(2, min(maximumDimension, Int(ceil(extents.x / spacing)) + 1)),
            y: max(2, min(maximumDimension, Int(ceil(extents.y / spacing)) + 1)),
            z: max(2, min(maximumDimension, Int(ceil(extents.z / spacing)) + 1))
        )
        var values = [Float](repeating: -padding, count: dimensions.x * dimensions.y * dimensions.z)

        for atom in atoms {
            let influence = ElementTable.vanDerWaalsRadius(for: atom.element) + probeRadius
            let centerX = (atom.position.x - minimum.x) / spacing
            let centerY = (atom.position.y - minimum.y) / spacing
            let centerZ = (atom.position.z - minimum.z) / spacing
            let gridRadius = Int(ceil(influence / spacing)) + 1
            let xRange = max(0, Int(floor(centerX)) - gridRadius)...min(dimensions.x - 1, Int(ceil(centerX)) + gridRadius)
            let yRange = max(0, Int(floor(centerY)) - gridRadius)...min(dimensions.y - 1, Int(ceil(centerY)) + gridRadius)
            let zRange = max(0, Int(floor(centerZ)) - gridRadius)...min(dimensions.z - 1, Int(ceil(centerZ)) + gridRadius)

            for z in zRange {
                let dz = minimum.z + Float(z) * spacing - atom.position.z
                for y in yRange {
                    let dy = minimum.y + Float(y) * spacing - atom.position.y
                    for x in xRange {
                        let dx = minimum.x + Float(x) * spacing - atom.position.x
                        let signedDistance = influence - sqrt(dx * dx + dy * dy + dz * dz)
                        let index = x + dimensions.x * (y + dimensions.y * z)
                        values[index] = max(values[index], signedDistance)
                    }
                }
            }
        }

        return VolumeMap(
            name: "\(structure.name) molecular surface",
            dimensions: dimensions,
            origin: minimum,
            spacing: Vector3(x: spacing, y: spacing, z: spacing),
            values: values
        )
    }
}
