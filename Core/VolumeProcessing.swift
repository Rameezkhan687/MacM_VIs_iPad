import Foundation

public struct VolumeStatistics: Sendable {
    public let minimum: Float
    public let maximum: Float
    public let mean: Float
    public let standardDeviation: Float
    public let nonzeroVoxelCount: Int
}

public struct VolumeSegment: Identifiable, Sendable {
    public let id: Int
    public let voxelCount: Int
    public let volume: Float
    public let center: Vector3
    public let peakValue: Float
}

public struct VolumeFitResult: Sendable {
    public let translation: Vector3
    public let score: Float
}

public struct RigidVolumeFitResult: Sendable {
    public let translation: Vector3
    public let rotationDegrees: Vector3
    public let center: Vector3
    public let score: Float

    public func applying(to point: Vector3) -> Vector3 {
        VolumeProcessor.rotated(point, around: center, degrees: rotationDegrees) + translation
    }
}

public struct VolumeProcessor: Sendable {
    public init() {}

    public func statistics(_ volume: VolumeMap) -> VolumeStatistics {
        guard !volume.values.isEmpty else {
            return VolumeStatistics(minimum: 0, maximum: 0, mean: 0, standardDeviation: 0, nonzeroVoxelCount: 0)
        }
        let variance = volume.values.reduce(Float.zero) { total, value in
            let delta = value - volume.mean
            return total + delta * delta
        } / Float(volume.values.count)
        return VolumeStatistics(
            minimum: volume.minimum,
            maximum: volume.maximum,
            mean: volume.mean,
            standardDeviation: sqrt(variance),
            nonzeroVoxelCount: volume.values.count { $0 != 0 }
        )
    }

    public func smoothed(_ volume: VolumeMap, radius: Int = 1) -> VolumeMap {
        guard radius > 0 else { return volume }
        let d = volume.dimensions
        var xPass = [Float](repeating: 0, count: volume.values.count)
        var yPass = xPass
        var result = xPass
        for z in 0..<d.z { for y in 0..<d.y { for x in 0..<d.x {
            var sum: Float = 0, count: Float = 0
            for dx in -radius...radius where x + dx >= 0 && x + dx < d.x { sum += volume.value(x: x + dx, y: y, z: z); count += 1 }
            xPass[index(x, y, z, d)] = sum / count
        } } }
        for z in 0..<d.z { for y in 0..<d.y { for x in 0..<d.x {
            var sum: Float = 0, count: Float = 0
            for dy in -radius...radius where y + dy >= 0 && y + dy < d.y { sum += xPass[index(x, y + dy, z, d)]; count += 1 }
            yPass[index(x, y, z, d)] = sum / count
        } } }
        for z in 0..<d.z { for y in 0..<d.y { for x in 0..<d.x {
            var sum: Float = 0, count: Float = 0
            for dz in -radius...radius where z + dz >= 0 && z + dz < d.z { sum += yPass[index(x, y, z + dz, d)]; count += 1 }
            result[index(x, y, z, d)] = sum / count
        } } }
        return copied(volume, name: "\(volume.name) · smooth \(radius)", values: result)
    }

    public func sharpened(_ volume: VolumeMap, amount: Float = 1) -> VolumeMap {
        let blurred = smoothed(volume)
        let values = zip(volume.values, blurred.values).map { original, smooth in original + amount * (original - smooth) }
        return copied(volume, name: "\(volume.name) · sharpen", values: values)
    }

    public func cropped(
        _ volume: VolumeMap,
        x: ClosedRange<Int>,
        y: ClosedRange<Int>,
        z: ClosedRange<Int>
    ) -> VolumeMap? {
        let d = volume.dimensions
        let xr = max(0, x.lowerBound)...min(d.x - 1, x.upperBound)
        let yr = max(0, y.lowerBound)...min(d.y - 1, y.upperBound)
        let zr = max(0, z.lowerBound)...min(d.z - 1, z.upperBound)
        guard !xr.isEmpty, !yr.isEmpty, !zr.isEmpty else { return nil }
        var values: [Float] = []
        values.reserveCapacity(xr.count * yr.count * zr.count)
        for zi in zr { for yi in yr { for xi in xr { values.append(volume.value(x: xi, y: yi, z: zi)) } } }
        return VolumeMap(
            name: "\(volume.name) · crop",
            dimensions: (xr.count, yr.count, zr.count),
            origin: Vector3(
                x: volume.origin.x + Float(xr.lowerBound) * volume.spacing.x,
                y: volume.origin.y + Float(yr.lowerBound) * volume.spacing.y,
                z: volume.origin.z + Float(zr.lowerBound) * volume.spacing.z
            ),
            spacing: volume.spacing,
            values: values
        )
    }

    public func zoned(_ volume: VolumeMap, around atoms: [Atom], radius: Float) -> VolumeMap {
        guard !atoms.isEmpty, radius > 0 else { return volume }
        let d = volume.dimensions
        var values = [Float](repeating: volume.minimum, count: volume.values.count)
        for atom in atoms.prefix(50_000) {
            let centerX = (atom.position.x - volume.origin.x) / volume.spacing.x
            let centerY = (atom.position.y - volume.origin.y) / volume.spacing.y
            let centerZ = (atom.position.z - volume.origin.z) / volume.spacing.z
            let rx = Int(ceil(radius / abs(volume.spacing.x)))
            let ry = Int(ceil(radius / abs(volume.spacing.y)))
            let rz = Int(ceil(radius / abs(volume.spacing.z)))
            for z in max(0, Int(centerZ) - rz)...min(d.z - 1, Int(centerZ) + rz) {
                for y in max(0, Int(centerY) - ry)...min(d.y - 1, Int(centerY) + ry) {
                    for x in max(0, Int(centerX) - rx)...min(d.x - 1, Int(centerX) + rx) {
                        let point = coordinate(volume, x, y, z)
                        if (point - atom.position).length <= radius {
                            let i = index(x, y, z, d)
                            values[i] = volume.values[i]
                        }
                    }
                }
            }
        }
        return copied(volume, name: "\(volume.name) · zone \(radius) Å", values: values)
    }

    public func difference(_ first: VolumeMap, _ second: VolumeMap) -> VolumeMap? {
        guard first.dimensions == second.dimensions, first.values.count == second.values.count else { return nil }
        let values = zip(first.values, second.values).map(-)
        return VolumeMap(
            name: "\(first.name) − \(second.name)",
            dimensions: first.dimensions,
            origin: first.origin,
            spacing: first.spacing,
            values: values
        )
    }

    public func segments(_ volume: VolumeMap, threshold: Float, minimumVoxels: Int = 8) -> [VolumeSegment] {
        let d = volume.dimensions
        var visited = [Bool](repeating: false, count: volume.values.count)
        let neighbors = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
        var result: [VolumeSegment] = []
        for z in 0..<d.z { for y in 0..<d.y { for x in 0..<d.x {
            let start = index(x, y, z, d)
            guard !visited[start], volume.values[start] >= threshold else { continue }
            visited[start] = true
            var queue = [(x, y, z)]
            var cursor = 0
            var sum = Vector3.zero
            var peak = volume.values[start]
            while cursor < queue.count {
                let point = queue[cursor]; cursor += 1
                sum = sum + coordinate(volume, point.0, point.1, point.2)
                peak = max(peak, volume.value(x: point.0, y: point.1, z: point.2))
                for offset in neighbors {
                    let nx = point.0 + offset.0, ny = point.1 + offset.1, nz = point.2 + offset.2
                    guard nx >= 0, ny >= 0, nz >= 0, nx < d.x, ny < d.y, nz < d.z else { continue }
                    let i = index(nx, ny, nz, d)
                    if !visited[i], volume.values[i] >= threshold { visited[i] = true; queue.append((nx, ny, nz)) }
                }
            }
            guard queue.count >= minimumVoxels else { continue }
            result.append(VolumeSegment(
                id: result.count,
                voxelCount: queue.count,
                volume: Float(queue.count) * abs(volume.spacing.x * volume.spacing.y * volume.spacing.z),
                center: sum / Float(queue.count),
                peakValue: peak
            ))
        } } }
        return result.sorted { $0.voxelCount > $1.voxelCount }
    }

    public func fitAtoms(_ atoms: [Atom], to volume: VolumeMap) -> VolumeFitResult? {
        guard !atoms.isEmpty else { return nil }
        let sampled = Array(atoms.prefix(4_000))
        var translation = Vector3.zero
        var step = max(abs(volume.spacing.x), abs(volume.spacing.y), abs(volume.spacing.z)) * 4
        func score(_ offset: Vector3) -> Float {
            sampled.reduce(0) { $0 + sample(volume, at: $1.position + offset) } / Float(sampled.count)
        }
        var best = score(translation)
        let directions = [
            Vector3(x: 1, y: 0, z: 0), Vector3(x: -1, y: 0, z: 0),
            Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: -1, z: 0),
            Vector3(x: 0, y: 0, z: 1), Vector3(x: 0, y: 0, z: -1)
        ]
        for _ in 0..<24 {
            var improved = false
            for direction in directions {
                let candidate = translation + Vector3(x: direction.x * step, y: direction.y * step, z: direction.z * step)
                let candidateScore = score(candidate)
                if candidateScore > best { best = candidateScore; translation = candidate; improved = true }
            }
            if !improved { step *= 0.5 }
            if step < 0.05 { break }
        }
        return VolumeFitResult(translation: translation, score: best)
    }

    public func rigidFitAtoms(_ atoms: [Atom], to volume: VolumeMap) -> RigidVolumeFitResult? {
        guard !atoms.isEmpty else { return nil }
        let sampled = Array(atoms.prefix(2_000))
        let center = sampled.reduce(Vector3.zero) { $0 + $1.position } / Float(sampled.count)
        var rotation = Vector3.zero
        var translation = fitAtoms(sampled, to: volume)?.translation ?? .zero
        func score(rotation: Vector3, translation: Vector3) -> Float {
            sampled.reduce(Float.zero) { total, atom in
                let point = Self.rotated(atom.position, around: center, degrees: rotation) + translation
                return total + sample(volume, at: point)
            } / Float(sampled.count)
        }
        var best = score(rotation: rotation, translation: translation)
        for angleStep in [90, 45, 22.5, 10, 5, 2] as [Float] {
            var changed = true
            while changed {
                changed = false
                let candidates = [
                    Vector3(x: angleStep, y: 0, z: 0), Vector3(x: -angleStep, y: 0, z: 0),
                    Vector3(x: 0, y: angleStep, z: 0), Vector3(x: 0, y: -angleStep, z: 0),
                    Vector3(x: 0, y: 0, z: angleStep), Vector3(x: 0, y: 0, z: -angleStep)
                ]
                for delta in candidates {
                    let candidate = rotation + delta
                    let value = score(rotation: candidate, translation: translation)
                    if value > best {
                        rotation = candidate
                        best = value
                        changed = true
                    }
                }
            }
        }
        var translationStep = max(abs(volume.spacing.x), abs(volume.spacing.y), abs(volume.spacing.z)) * 2
        let directions = [
            Vector3(x: 1, y: 0, z: 0), Vector3(x: -1, y: 0, z: 0),
            Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: -1, z: 0),
            Vector3(x: 0, y: 0, z: 1), Vector3(x: 0, y: 0, z: -1)
        ]
        for _ in 0..<20 {
            var improved = false
            for direction in directions {
                let candidate = translation + Vector3(
                    x: direction.x * translationStep,
                    y: direction.y * translationStep,
                    z: direction.z * translationStep
                )
                let value = score(rotation: rotation, translation: candidate)
                if value > best { best = value; translation = candidate; improved = true }
            }
            if !improved { translationStep *= 0.5 }
            if translationStep < 0.05 { break }
        }
        return RigidVolumeFitResult(
            translation: translation,
            rotationDegrees: rotation,
            center: center,
            score: best
        )
    }

    public func fitMap(_ moving: VolumeMap, to reference: VolumeMap) -> VolumeFitResult? {
        let d = reference.dimensions
        let strideValue = max(1, Int(ceil(pow(Double(max(1, reference.values.count)) / 12_000, 1.0 / 3.0))))
        var samples: [(Vector3, Float)] = []
        for z in Swift.stride(from: 0, to: d.z, by: strideValue) {
            for y in Swift.stride(from: 0, to: d.y, by: strideValue) {
                for x in Swift.stride(from: 0, to: d.x, by: strideValue) {
                    let value = reference.value(x: x, y: y, z: z)
                    if value > reference.mean { samples.append((coordinate(reference, x, y, z), value - reference.mean)) }
                }
            }
        }
        guard !samples.isEmpty else { return nil }
        var translation = Vector3.zero
        var step = max(abs(reference.spacing.x), abs(reference.spacing.y), abs(reference.spacing.z)) * 4
        func score(_ offset: Vector3) -> Float {
            samples.reduce(0) { total, item in
                let sourcePoint = item.0 - offset
                return total + item.1 * (sample(moving, at: sourcePoint) - moving.mean)
            } / Float(samples.count)
        }
        var best = score(translation)
        let directions = [
            Vector3(x: 1, y: 0, z: 0), Vector3(x: -1, y: 0, z: 0),
            Vector3(x: 0, y: 1, z: 0), Vector3(x: 0, y: -1, z: 0),
            Vector3(x: 0, y: 0, z: 1), Vector3(x: 0, y: 0, z: -1)
        ]
        for _ in 0..<24 {
            var improved = false
            for direction in directions {
                let candidate = translation + Vector3(x: direction.x * step, y: direction.y * step, z: direction.z * step)
                let candidateScore = score(candidate)
                if candidateScore > best { best = candidateScore; translation = candidate; improved = true }
            }
            if !improved { step *= 0.5 }
            if step < 0.05 { break }
        }
        return VolumeFitResult(translation: translation, score: best)
    }

    public func sample(_ volume: VolumeMap, at point: Vector3) -> Float {
        let fx = (point.x - volume.origin.x) / volume.spacing.x
        let fy = (point.y - volume.origin.y) / volume.spacing.y
        let fz = (point.z - volume.origin.z) / volume.spacing.z
        let x0 = Int(floor(fx)), y0 = Int(floor(fy)), z0 = Int(floor(fz))
        let d = volume.dimensions
        guard x0 >= 0, y0 >= 0, z0 >= 0, x0 + 1 < d.x, y0 + 1 < d.y, z0 + 1 < d.z else { return volume.minimum }
        let tx = fx - Float(x0), ty = fy - Float(y0), tz = fz - Float(z0)
        func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let c00 = lerp(volume.value(x: x0, y: y0, z: z0), volume.value(x: x0 + 1, y: y0, z: z0), tx)
        let c10 = lerp(volume.value(x: x0, y: y0 + 1, z: z0), volume.value(x: x0 + 1, y: y0 + 1, z: z0), tx)
        let c01 = lerp(volume.value(x: x0, y: y0, z: z0 + 1), volume.value(x: x0 + 1, y: y0, z: z0 + 1), tx)
        let c11 = lerp(volume.value(x: x0, y: y0 + 1, z: z0 + 1), volume.value(x: x0 + 1, y: y0 + 1, z: z0 + 1), tx)
        return lerp(lerp(c00, c10, ty), lerp(c01, c11, ty), tz)
    }

    private func copied(_ volume: VolumeMap, name: String, values: [Float]) -> VolumeMap {
        VolumeMap(name: name, dimensions: volume.dimensions, origin: volume.origin, spacing: volume.spacing, values: values)
    }

    private func coordinate(_ volume: VolumeMap, _ x: Int, _ y: Int, _ z: Int) -> Vector3 {
        Vector3(
            x: volume.origin.x + Float(x) * volume.spacing.x,
            y: volume.origin.y + Float(y) * volume.spacing.y,
            z: volume.origin.z + Float(z) * volume.spacing.z
        )
    }

    private func index(_ x: Int, _ y: Int, _ z: Int, _ d: (x: Int, y: Int, z: Int)) -> Int {
        x + d.x * (y + d.y * z)
    }

    fileprivate static func rotated(_ point: Vector3, around center: Vector3, degrees: Vector3) -> Vector3 {
        let radians = Vector3(
            x: degrees.x * .pi / 180,
            y: degrees.y * .pi / 180,
            z: degrees.z * .pi / 180
        )
        var value = point - center
        let cx = cos(radians.x), sx = sin(radians.x)
        value = Vector3(x: value.x, y: value.y * cx - value.z * sx, z: value.y * sx + value.z * cx)
        let cy = cos(radians.y), sy = sin(radians.y)
        value = Vector3(x: value.x * cy + value.z * sy, y: value.y, z: -value.x * sy + value.z * cy)
        let cz = cos(radians.z), sz = sin(radians.z)
        value = Vector3(x: value.x * cz - value.y * sz, y: value.x * sz + value.y * cz, z: value.z)
        return value + center
    }
}
