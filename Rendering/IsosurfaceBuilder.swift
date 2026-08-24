import Foundation
import SceneKit
import simd

enum IsosurfaceBuilder {
    private static let cubeOffsets = [
        (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
        (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)
    ]

    private static let tetrahedra = [
        [0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6],
        [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]
    ]

    static func geometry(volume: VolumeMap, threshold: Float) -> SCNGeometry? {
        let d = volume.dimensions
        guard d.x > 1, d.y > 1, d.z > 1 else { return nil }
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(min(volume.values.count * 3, 1_500_000))

        for z in 0..<(d.z - 1) {
            for y in 0..<(d.y - 1) {
                for x in 0..<(d.x - 1) {
                    var positions: [Vector3] = []
                    var values: [Float] = []
                    positions.reserveCapacity(8)
                    values.reserveCapacity(8)
                    for offset in cubeOffsets {
                        let gx = x + offset.0
                        let gy = y + offset.1
                        let gz = z + offset.2
                        positions.append(Vector3(
                            x: volume.origin.x + Float(gx) * volume.spacing.x,
                            y: volume.origin.y + Float(gy) * volume.spacing.y,
                            z: volume.origin.z + Float(gz) * volume.spacing.z
                        ))
                        values.append(volume.value(x: gx, y: gy, z: gz))
                    }
                    if (values.min() ?? threshold) > threshold || (values.max() ?? threshold) < threshold { continue }
                    for tetrahedron in tetrahedra {
                        polygonize(
                            indices: tetrahedron,
                            positions: positions,
                            values: values,
                            threshold: threshold,
                            output: &vertices
                        )
                    }
                }
            }
        }
        guard !vertices.isEmpty else { return nil }

        var normals: [SCNVector3] = []
        normals.reserveCapacity(vertices.count)
        for index in stride(from: 0, to: vertices.count, by: 3) {
            let a = vertices[index]
            let b = vertices[index + 1]
            let c = vertices[index + 2]
            let ab = SIMD3<Float>(b.x - a.x, b.y - a.y, b.z - a.z)
            let ac = SIMD3<Float>(c.x - a.x, c.y - a.y, c.z - a.z)
            let crossed = simd_cross(ab, ac)
            let normal = simd_length(crossed) > 0 ? simd_normalize(crossed) : SIMD3<Float>(0, 1, 0)
            let n = SCNVector3(normal.x, normal.y, normal.z)
            normals.append(contentsOf: [n, n, n])
        }

        let source = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let indices = Array(0..<Int32(vertices.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source, normalSource], elements: [element])
    }

    private static func polygonize(
        indices: [Int],
        positions: [Vector3],
        values: [Float],
        threshold: Float,
        output: inout [SCNVector3]
    ) {
        let inside = indices.filter { values[$0] >= threshold }
        let outside = indices.filter { values[$0] < threshold }
        guard !inside.isEmpty, !outside.isEmpty else { return }

        if inside.count == 1 || inside.count == 3 {
            let invert = inside.count == 3
            let pivot = invert ? outside[0] : inside[0]
            let others = invert ? inside : outside
            var triangle = others.map { interpolate(
                positions[pivot], positions[$0], values[pivot], values[$0], threshold
            ) }
            if invert { triangle.swapAt(1, 2) }
            output.append(contentsOf: triangle.map(scn))
        } else if inside.count == 2 {
            let a = interpolate(positions[inside[0]], positions[outside[0]], values[inside[0]], values[outside[0]], threshold)
            let b = interpolate(positions[inside[0]], positions[outside[1]], values[inside[0]], values[outside[1]], threshold)
            let c = interpolate(positions[inside[1]], positions[outside[0]], values[inside[1]], values[outside[0]], threshold)
            let d = interpolate(positions[inside[1]], positions[outside[1]], values[inside[1]], values[outside[1]], threshold)
            output.append(contentsOf: [scn(a), scn(b), scn(c), scn(b), scn(d), scn(c)])
        }
    }

    private static func interpolate(_ a: Vector3, _ b: Vector3, _ va: Float, _ vb: Float, _ level: Float) -> Vector3 {
        let difference = vb - va
        let t = abs(difference) < 0.000_001 ? 0.5 : max(0, min(1, (level - va) / difference))
        return Vector3(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            z: a.z + (b.z - a.z) * t
        )
    }

    private static func scn(_ p: Vector3) -> SCNVector3 { SCNVector3(p.x, p.y, p.z) }
}
