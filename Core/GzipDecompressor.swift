import Compression
import Foundation

public struct GzipDecompressor: Sendable {
    public init() {}

    public func decompress(
        _ data: Data,
        maximumOutputSize: Int = 1_500_000_000
    ) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 8 else {
            throw MolecularError.invalidMap("The downloaded file is not a valid gzip-compressed map.")
        }

        let flags = data[3]
        guard flags & 0xe0 == 0 else {
            throw MolecularError.invalidMap("The gzip header uses unsupported flags.")
        }

        let trailerStart = data.count - 8
        var cursor = 10

        if flags & 0x04 != 0 {
            guard cursor + 2 <= trailerStart else { throw truncatedHeaderError }
            let extraLength = Int(data[cursor]) | Int(data[cursor + 1]) << 8
            cursor += 2 + extraLength
            guard cursor <= trailerStart else { throw truncatedHeaderError }
        }
        if flags & 0x08 != 0 { cursor = try indexAfterNull(in: data, from: cursor, before: trailerStart) }
        if flags & 0x10 != 0 { cursor = try indexAfterNull(in: data, from: cursor, before: trailerStart) }
        if flags & 0x02 != 0 {
            cursor += 2
            guard cursor <= trailerStart else { throw truncatedHeaderError }
        }

        guard cursor < trailerStart else {
            throw MolecularError.invalidMap("The compressed map does not contain voxel data.")
        }

        let expectedSize = Int(littleEndianUInt32(in: data, at: trailerStart + 4))
        guard expectedSize > 0 else {
            throw MolecularError.invalidMap("The compressed map reports an empty output file.")
        }
        guard expectedSize <= maximumOutputSize else {
            throw MolecularError.invalidMap(
                "This map expands to more than \(maximumOutputSize / 1_000_000) MB and is too large for this version of MoleculePad."
            )
        }

        var output = Data(count: expectedSize)
        let decodedSize = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard
                    let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                    let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    expectedSize,
                    sourceAddress.advanced(by: cursor),
                    trailerStart - cursor,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedSize == expectedSize else {
            throw MolecularError.invalidMap("The gzip stream could not be decompressed completely.")
        }
        return output
    }

    private var truncatedHeaderError: MolecularError {
        .invalidMap("The gzip header is incomplete.")
    }

    private func indexAfterNull(in data: Data, from start: Int, before end: Int) throws -> Int {
        guard start < end else { throw truncatedHeaderError }
        for index in start..<end where data[index] == 0 { return index + 1 }
        throw truncatedHeaderError
    }

    private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
