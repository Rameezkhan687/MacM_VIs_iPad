import Foundation
import Testing
@testable import MoleculePadCore

struct MedicalImageParsersTests {
    @Test func parsesNIfTI() throws {
        var bytes = [UInt8](repeating: 0, count: 352 + 8 * 4)
        put(UInt32(348), at: 0, in: &bytes)
        put(UInt16(3), at: 40, in: &bytes)
        put(UInt16(2), at: 42, in: &bytes)
        put(UInt16(2), at: 44, in: &bytes)
        put(UInt16(2), at: 46, in: &bytes)
        put(UInt16(16), at: 70, in: &bytes)
        put(UInt16(32), at: 72, in: &bytes)
        put(Float(1.5).bitPattern, at: 80, in: &bytes)
        put(Float(2).bitPattern, at: 84, in: &bytes)
        put(Float(2.5).bitPattern, at: 88, in: &bytes)
        put(Float(352).bitPattern, at: 108, in: &bytes)
        for index in 0..<8 { put(Float(index).bitPattern, at: 352 + index * 4, in: &bytes) }

        let volume = try NIfTIParser().parse(Data(bytes))
        #expect(volume.dimensions.x == 2)
        #expect(volume.dimensions.z == 2)
        #expect(volume.spacing.z == 2.5)
        #expect(volume.maximum == 7)
    }

    @Test func parsesNRRD() throws {
        let header = """
        NRRD0005
        type: uchar
        dimension: 3
        sizes: 2 2 2
        spacings: 1 1.5 2
        encoding: raw

        """.appending("\n").data(using: .utf8)!
        let volume = try NRRDParser().parse(header + Data([0, 1, 2, 3, 4, 5, 6, 7]))
        #expect(volume.dimensions.y == 2)
        #expect(volume.spacing.y == 1.5)
        #expect(volume.maximum == 7)
    }

    @Test func parsesSingleSliceDICOM() throws {
        var data = Data(repeating: 0, count: 128)
        data.append(Data("DICM".utf8))
        appendElement(group: 0x0028, element: 0x0010, vr: "US", value: Data([2, 0]), to: &data)
        appendElement(group: 0x0028, element: 0x0011, vr: "US", value: Data([2, 0]), to: &data)
        appendElement(group: 0x0028, element: 0x0100, vr: "US", value: Data([16, 0]), to: &data)
        appendElement(group: 0x0028, element: 0x0103, vr: "US", value: Data([0, 0]), to: &data)
        appendElement(group: 0x0008, element: 0x0060, vr: "CS", value: Data("MR".utf8), to: &data)
        appendElement(group: 0x0010, element: 0x0010, vr: "PN", value: Data("Test^Subject".utf8), to: &data)
        appendElement(group: 0x7FE0, element: 0x0010, vr: "OW", value: Data([1, 0, 2, 0, 3, 0, 4, 0]), to: &data)
        let volume = try DICOMParser().parse(data)
        #expect(volume.dimensions.x == 2)
        #expect(volume.dimensions.z == 2)
        #expect(volume.maximum == 4)
        let series = try DICOMParser().parseSeries([data, data])
        #expect(series.dimensions.z == 2)
        #expect(series.values.count == 8)
        let metadata = try DICOMParser().metadata(data)
        #expect(metadata.modality == "MR")
        #expect(metadata.patientName == "Test Subject")
        #expect(metadata.rows == 2 && metadata.columns == 2)
    }

    private func put<T: FixedWidthInteger>(_ value: T, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<MemoryLayout<T>.size { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> T(index * 8)) }
    }

    private func appendElement(group: UInt16, element: UInt16, vr: String, value: Data, to data: inout Data) {
        var header: [UInt8] = [UInt8(group & 0xff), UInt8(group >> 8), UInt8(element & 0xff), UInt8(element >> 8)]
        header.append(contentsOf: vr.utf8)
        if ["OB", "OW", "SQ", "UN", "UT"].contains(vr) {
            header += [0, 0, UInt8(value.count & 0xff), UInt8((value.count >> 8) & 0xff), UInt8((value.count >> 16) & 0xff), UInt8((value.count >> 24) & 0xff)]
        } else {
            header += [UInt8(value.count & 0xff), UInt8((value.count >> 8) & 0xff)]
        }
        data.append(contentsOf: header)
        data.append(value)
    }
}
