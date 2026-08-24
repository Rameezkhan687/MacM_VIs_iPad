import Foundation

public struct MRCParser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "Density map", maxDimension: Int = 96) throws -> VolumeMap {
        guard data.count >= 1024 else { throw MolecularError.invalidMap("The MRC header is incomplete.") }

        var reader = BinaryReader(data: data, isBigEndian: false)
        var nx = reader.int32(at: 0)
        var ny = reader.int32(at: 4)
        var nz = reader.int32(at: 8)
        let littleEndianLooksValid = (1...100_000).contains(nx) && (1...100_000).contains(ny) && (1...100_000).contains(nz)
        if !littleEndianLooksValid {
            reader = BinaryReader(data: data, isBigEndian: true)
            nx = reader.int32(at: 0)
            ny = reader.int32(at: 4)
            nz = reader.int32(at: 8)
        }
        guard nx > 1, ny > 1, nz > 1 else { throw MolecularError.invalidMap("Invalid grid dimensions.") }

        let mode = reader.int32(at: 12)
        guard [0, 1, 2, 6].contains(mode) else {
            throw MolecularError.invalidMap("MRC mode \(mode) is not supported.")
        }
        let sourceDimensions = (x: Int(nx), y: Int(ny), z: Int(nz))
        let nsymbt = max(0, Int(reader.int32(at: 92)))
        let dataOffset = 1024 + nsymbt
        let bytesPerValue = mode == 0 ? 1 : (mode == 2 ? 4 : 2)
        let valueCount = sourceDimensions.x * sourceDimensions.y * sourceDimensions.z
        guard valueCount > 0, dataOffset + valueCount * bytesPerValue <= data.count else {
            throw MolecularError.invalidMap("The voxel data is incomplete.")
        }

        let mx = max(1, Int(reader.int32(at: 28)))
        let my = max(1, Int(reader.int32(at: 32)))
        let mz = max(1, Int(reader.int32(at: 36)))
        var spacing = Vector3(
            x: reader.float32(at: 40) / Float(mx),
            y: reader.float32(at: 44) / Float(my),
            z: reader.float32(at: 48) / Float(mz)
        )
        if !spacing.x.isFinite || spacing.x <= 0 { spacing.x = 1 }
        if !spacing.y.isFinite || spacing.y <= 0 { spacing.y = 1 }
        if !spacing.z.isFinite || spacing.z <= 0 { spacing.z = 1 }

        var origin = Vector3(
            x: reader.float32(at: 196),
            y: reader.float32(at: 200),
            z: reader.float32(at: 204)
        )
        if origin == .zero {
            origin = Vector3(
                x: Float(reader.int32(at: 16)) * spacing.x,
                y: Float(reader.int32(at: 20)) * spacing.y,
                z: Float(reader.int32(at: 24)) * spacing.z
            )
        }

        let strideValue = max(1, Int(ceil(Double(max(sourceDimensions.x, sourceDimensions.y, sourceDimensions.z)) / Double(maxDimension))))
        let outputDimensions = (
            x: (sourceDimensions.x - 1) / strideValue + 1,
            y: (sourceDimensions.y - 1) / strideValue + 1,
            z: (sourceDimensions.z - 1) / strideValue + 1
        )
        var values: [Float] = []
        values.reserveCapacity(outputDimensions.x * outputDimensions.y * outputDimensions.z)
        for z in Swift.stride(from: 0, to: sourceDimensions.z, by: strideValue) {
            for y in Swift.stride(from: 0, to: sourceDimensions.y, by: strideValue) {
                for x in Swift.stride(from: 0, to: sourceDimensions.x, by: strideValue) {
                    let index = x + sourceDimensions.x * (y + sourceDimensions.y * z)
                    let offset = dataOffset + index * bytesPerValue
                    switch mode {
                    case 0: values.append(Float(Int8(bitPattern: data[offset])))
                    case 1: values.append(Float(reader.int16(at: offset)))
                    case 2: values.append(reader.float32(at: offset))
                    case 6: values.append(Float(reader.uint16(at: offset)))
                    default: break
                    }
                }
            }
        }

        return VolumeMap(
            name: name,
            dimensions: outputDimensions,
            origin: origin,
            spacing: Vector3(
                x: spacing.x * Float(strideValue),
                y: spacing.y * Float(strideValue),
                z: spacing.z * Float(strideValue)
            ),
            values: values
        )
    }
}

private struct BinaryReader {
    let data: Data
    let isBigEndian: Bool

    func int16(at offset: Int) -> Int16 { Int16(bitPattern: uint16(at: offset)) }

    func uint16(at offset: Int) -> UInt16 {
        let a = UInt16(data[offset])
        let b = UInt16(data[offset + 1])
        return isBigEndian ? (a << 8 | b) : (a | b << 8)
    }

    func int32(at offset: Int) -> Int {
        Int(Int32(bitPattern: uint32(at: offset)))
    }

    func float32(at offset: Int) -> Float {
        Float(bitPattern: uint32(at: offset))
    }

    private func uint32(at offset: Int) -> UInt32 {
        let bytes = (0..<4).map { UInt32(data[offset + $0]) }
        if isBigEndian {
            return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
        }
        return bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
    }
}
