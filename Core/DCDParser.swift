import Foundation

/// Reads standard CHARMM/NAMD DCD coordinate trajectories using an already-open
/// structure as topology. Both little- and big-endian Fortran records are accepted.
public struct DCDParser: Sendable {
    public init() {}

    public func parse(_ data: Data, topology: MolecularStructure, name: String = "DCD trajectory") throws -> MolecularTrajectory {
        guard !topology.atoms.isEmpty else {
            throw MolecularError.invalidStructure("Open the matching PDB or mmCIF topology before a DCD trajectory.")
        }
        var reader = DCDRecordReader(data: data)
        let header = try reader.readRecord()
        guard header.count >= 84,
              let signature = String(data: header.prefix(4), encoding: .ascii),
              ["CORD", "VELD"].contains(signature) else {
            throw MolecularError.invalidStructure("This file is not a supported DCD coordinate trajectory.")
        }
        let declaredFrames = Int(reader.int32(in: header, at: 4))
        _ = try reader.readRecord() // title block
        let atomRecord = try reader.readRecord()
        guard atomRecord.count >= 4 else {
            throw MolecularError.invalidStructure("The DCD atom-count record is missing.")
        }
        let atomCount = Int(reader.int32(in: atomRecord, at: 0))
        guard atomCount == topology.atoms.count else {
            throw MolecularError.invalidStructure(
                "DCD has \(atomCount) atoms, but the open topology has \(topology.atoms.count)."
            )
        }

        var frames: [MolecularStructure] = []
        let expectedCoordinateBytes = atomCount * MemoryLayout<Float>.size
        while !reader.isAtEnd && (declaredFrames <= 0 || frames.count < declaredFrames) {
            var xRecord = try reader.readRecord()
            if [48, 56].contains(xRecord.count) { // optional unit-cell record
                guard !reader.isAtEnd else { break }
                xRecord = try reader.readRecord()
            }
            guard xRecord.count == expectedCoordinateBytes else {
                throw MolecularError.invalidStructure("Unexpected DCD X-coordinate record size.")
            }
            let yRecord = try reader.readRecord()
            let zRecord = try reader.readRecord()
            guard yRecord.count == expectedCoordinateBytes, zRecord.count == expectedCoordinateBytes else {
                throw MolecularError.invalidStructure("Incomplete DCD coordinate frame.")
            }

            var frame = topology
            frame.name = "\(name) · Frame \(frames.count + 1)"
            for index in frame.atoms.indices {
                frame.atoms[index].position = Vector3(
                    x: reader.float32(in: xRecord, at: index * 4),
                    y: reader.float32(in: yRecord, at: index * 4),
                    z: reader.float32(in: zRecord, at: index * 4)
                )
            }
            frames.append(frame)
        }
        guard !frames.isEmpty else {
            throw MolecularError.invalidStructure("The DCD file contains no coordinate frames.")
        }
        return MolecularTrajectory(name: name, frames: frames)
    }
}

private struct DCDRecordReader {
    private let data: Data
    private(set) var offset = 0
    private let isLittleEndian: Bool

    init(data: Data) {
        self.data = data
        if data.count >= 4 {
            let little = Self.readUInt32(data, offset: 0, littleEndian: true)
            isLittleEndian = little == 84 || little == 164
        } else {
            isLittleEndian = true
        }
    }

    var isAtEnd: Bool { offset >= data.count }

    mutating func readRecord() throws -> Data {
        guard offset + 8 <= data.count else {
            throw MolecularError.invalidStructure("The DCD file ended inside a record.")
        }
        let count = Int(Self.readUInt32(data, offset: offset, littleEndian: isLittleEndian))
        guard count >= 0, count <= 512_000_000, offset + 8 + count <= data.count else {
            throw MolecularError.invalidStructure("The DCD record length is invalid.")
        }
        let start = offset + 4
        let payload = data.subdata(in: start..<(start + count))
        let trailer = Int(Self.readUInt32(data, offset: start + count, littleEndian: isLittleEndian))
        guard trailer == count else {
            throw MolecularError.invalidStructure("The DCD record markers do not match.")
        }
        offset = start + count + 4
        return payload
    }

    func int32(in bytes: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: Self.readUInt32(bytes, offset: offset, littleEndian: isLittleEndian))
    }

    func float32(in bytes: Data, at offset: Int) -> Float {
        Float(bitPattern: Self.readUInt32(bytes, offset: offset, littleEndian: isLittleEndian))
    }

    private static func readUInt32(_ bytes: Data, offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        let value = bytes.withUnsafeBytes { raw -> UInt32 in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return littleEndian ? UInt32(littleEndian: value) : UInt32(bigEndian: value)
    }
}
