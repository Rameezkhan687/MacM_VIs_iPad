import Foundation
import Testing
@testable import MoleculePadCore

struct MRCParserTests {
    @Test func decompressesGzipData() throws {
        let compressed = Data([
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
            0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00,
            0x86, 0xa6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00
        ])
        let decompressed = try GzipDecompressor().decompress(compressed)
        #expect(String(data: decompressed, encoding: .utf8) == "hello")
    }

    @Test func parsesFloatMap() throws {
        var data = Data(repeating: 0, count: 1024 + 8 * 4)
        writeInt32(2, at: 0, to: &data)
        writeInt32(2, at: 4, to: &data)
        writeInt32(2, at: 8, to: &data)
        writeInt32(2, at: 12, to: &data)
        writeInt32(2, at: 28, to: &data)
        writeInt32(2, at: 32, to: &data)
        writeInt32(2, at: 36, to: &data)
        writeFloat(2, at: 40, to: &data)
        writeFloat(2, at: 44, to: &data)
        writeFloat(2, at: 48, to: &data)
        for index in 0..<8 { writeFloat(Float(index), at: 1024 + index * 4, to: &data) }

        let map = try MRCParser().parse(data, name: "Test")
        #expect(map.dimensions.x == 2)
        #expect(map.values.count == 8)
        #expect(map.minimum == 0)
        #expect(map.maximum == 7)
        #expect(map.mean == 3.5)
    }

    private func writeInt32(_ value: Int32, at offset: Int, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in data.replaceSubrange(offset..<(offset + 4), with: bytes) }
    }

    private func writeFloat(_ value: Float, at offset: Int, to data: inout Data) {
        var littleEndian = value.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in data.replaceSubrange(offset..<(offset + 4), with: bytes) }
    }
}
