import Foundation

public struct NIfTIParser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "NIfTI") throws -> VolumeMap {
        guard data.count >= 352 else { throw MolecularError.invalidMap("The NIfTI header is incomplete.") }
        let littleEndian: Bool
        if int32(data, 0, little: true) == 348 { littleEndian = true }
        else if int32(data, 0, little: false) == 348 { littleEndian = false }
        else { throw MolecularError.invalidMap("The NIfTI header size is invalid.") }

        let dimensions = (
            x: max(1, Int(int16(data, 42, little: littleEndian))),
            y: max(1, Int(int16(data, 44, little: littleEndian))),
            z: max(1, Int(int16(data, 46, little: littleEndian)))
        )
        let datatype = Int(int16(data, 70, little: littleEndian))
        let spacing = Vector3(
            x: abs(float32(data, 80, little: littleEndian)),
            y: abs(float32(data, 84, little: littleEndian)),
            z: abs(float32(data, 88, little: littleEndian))
        )
        let offset = max(352, Int(float32(data, 108, little: littleEndian)))
        let slope = float32(data, 112, little: littleEndian)
        let intercept = float32(data, 116, little: littleEndian)
        let voxelCount = dimensions.x * dimensions.y * dimensions.z
        let bytesPerVoxel: Int = switch datatype {
        case 2: 1
        case 4, 512: 2
        case 8, 16, 768: 4
        case 64: 8
        default: throw MolecularError.invalidMap("Unsupported NIfTI datatype \(datatype).")
        }
        guard offset >= 0, voxelCount > 0, offset + voxelCount * bytesPerVoxel <= data.count else {
            throw MolecularError.invalidMap("The NIfTI voxel payload is incomplete.")
        }
        var values: [Float] = []
        values.reserveCapacity(voxelCount)
        for index in 0..<voxelCount {
            let position = offset + index * bytesPerVoxel
            let raw: Float = switch datatype {
            case 2: Float(data[position])
            case 4: Float(int16(data, position, little: littleEndian))
            case 8: Float(int32(data, position, little: littleEndian))
            case 16: float32(data, position, little: littleEndian)
            case 64: Float(float64(data, position, little: littleEndian))
            case 512: Float(uint16(data, position, little: littleEndian))
            case 768: Float(uint32(data, position, little: littleEndian))
            default: 0
            }
            values.append(raw * (slope == 0 ? 1 : slope) + intercept)
        }
        let origin = Vector3(
            x: float32(data, 268, little: littleEndian),
            y: float32(data, 272, little: littleEndian),
            z: float32(data, 276, little: littleEndian)
        )
        return VolumeMap(
            name: name,
            dimensions: dimensions,
            origin: origin,
            spacing: Vector3(x: spacing.x == 0 ? 1 : spacing.x, y: spacing.y == 0 ? 1 : spacing.y, z: spacing.z == 0 ? 1 : spacing.z),
            values: values
        )
    }
}

public struct NRRDParser: Sendable {
    public init() {}

    public func parse(_ data: Data, name: String = "NRRD") throws -> VolumeMap {
        guard let boundary = headerBoundary(in: data),
              let header = String(data: data.prefix(boundary.start), encoding: .utf8),
              header.hasPrefix("NRRD") else { throw MolecularError.invalidMap("The NRRD header is invalid.") }
        var fields: [String: String] = [:]
        for line in header.split(whereSeparator: \.isNewline).dropFirst() {
            let text = String(line)
            guard !text.hasPrefix("#"), let separator = text.firstIndex(of: ":") else { continue }
            fields[String(text[..<separator]).lowercased()] = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        }
        guard let sizes = fields["sizes"]?.split(whereSeparator: \.isWhitespace).compactMap({ Int($0) }), sizes.count >= 3 else {
            throw MolecularError.invalidMap("NRRD sizes are missing.")
        }
        let dimensions = (x: sizes[0], y: sizes[1], z: sizes[2])
        let count = dimensions.x * dimensions.y * dimensions.z
        let type = fields["type"]?.lowercased() ?? "float"
        let bytesPerValue: Int = switch type {
        case "uchar", "unsigned char", "uint8", "uint8_t": 1
        case "short", "short int", "int16", "int16_t", "ushort", "unsigned short", "uint16", "uint16_t": 2
        case "int", "int32", "int32_t", "uint", "unsigned int", "uint32", "uint32_t", "float": 4
        case "double": 8
        default: throw MolecularError.invalidMap("Unsupported NRRD type \(type).")
        }
        var payload = data.suffix(from: boundary.end)
        let encoding = fields["encoding"]?.lowercased() ?? "raw"
        if encoding == "gzip" || encoding == "gz" { payload = try GzipDecompressor().decompress(Data(payload))[...] }
        else if encoding != "raw" { throw MolecularError.invalidMap("Only raw and gzip NRRD encodings are supported.") }
        guard payload.count >= count * bytesPerValue else { throw MolecularError.invalidMap("The NRRD voxel payload is incomplete.") }
        let little = fields["endian"]?.lowercased() != "big"
        let payloadData = Data(payload)
        var values: [Float] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            let offset = index * bytesPerValue
            let value: Float = switch type {
            case "uchar", "unsigned char", "uint8", "uint8_t": Float(payloadData[offset])
            case "short", "short int", "int16", "int16_t": Float(int16(payloadData, offset, little: little))
            case "ushort", "unsigned short", "uint16", "uint16_t": Float(uint16(payloadData, offset, little: little))
            case "int", "int32", "int32_t": Float(int32(payloadData, offset, little: little))
            case "uint", "unsigned int", "uint32", "uint32_t": Float(uint32(payloadData, offset, little: little))
            case "float": float32(payloadData, offset, little: little)
            case "double": Float(float64(payloadData, offset, little: little))
            default: 0
            }
            values.append(value)
        }
        let spacings = fields["spacings"]?.split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
        let directions = fields["space directions"].map(directionLengths)
        let spacing = Vector3(
            x: spacings?.indices.contains(0) == true ? spacings![0] : directions?.indices.contains(0) == true ? directions![0] : 1,
            y: spacings?.indices.contains(1) == true ? spacings![1] : directions?.indices.contains(1) == true ? directions![1] : 1,
            z: spacings?.indices.contains(2) == true ? spacings![2] : directions?.indices.contains(2) == true ? directions![2] : 1
        )
        let originValues = fields["space origin"].map(vectorValues) ?? []
        let origin = Vector3(
            x: originValues.indices.contains(0) ? originValues[0] : 0,
            y: originValues.indices.contains(1) ? originValues[1] : 0,
            z: originValues.indices.contains(2) ? originValues[2] : 0
        )
        return VolumeMap(name: name, dimensions: dimensions, origin: origin, spacing: spacing, values: values)
    }

    private func headerBoundary(in data: Data) -> (start: Int, end: Int)? {
        let bytes = [UInt8](data)
        if let index = bytes.indices.dropLast(3).first(where: { bytes[$0...($0 + 3)] == [13, 10, 13, 10] }) { return (index, index + 4) }
        if let index = bytes.indices.dropLast().first(where: { bytes[$0] == 10 && bytes[$0 + 1] == 10 }) { return (index, index + 2) }
        return nil
    }

    private func vectorValues(_ text: String) -> [Float] {
        text.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            .split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func directionLengths(_ text: String) -> [Float] {
        text.split(whereSeparator: \.isWhitespace).map { vector in
            let values = vectorValues(String(vector))
            return sqrt(values.reduce(0) { $0 + $1 * $1 })
        }
    }
}

public struct DICOMMetadata: Codable, Equatable, Sendable {
    public var patientName: String?
    public var patientID: String?
    public var modality: String?
    public var studyDate: String?
    public var studyInstanceUID: String?
    public var seriesInstanceUID: String?
    public var seriesDescription: String?
    public var instanceNumber: Int?
    public var numberOfFrames: Int
    public var rows: Int
    public var columns: Int
    public var transferSyntaxUID: String?

    public init(
        patientName: String? = nil, patientID: String? = nil, modality: String? = nil,
        studyDate: String? = nil, studyInstanceUID: String? = nil,
        seriesInstanceUID: String? = nil, seriesDescription: String? = nil,
        instanceNumber: Int? = nil, numberOfFrames: Int = 1,
        rows: Int = 0, columns: Int = 0, transferSyntaxUID: String? = nil
    ) {
        self.patientName = patientName; self.patientID = patientID; self.modality = modality
        self.studyDate = studyDate; self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID; self.seriesDescription = seriesDescription
        self.instanceNumber = instanceNumber; self.numberOfFrames = numberOfFrames
        self.rows = rows; self.columns = columns; self.transferSyntaxUID = transferSyntaxUID
    }

    public var isCompressed: Bool {
        guard let transferSyntaxUID else { return false }
        return transferSyntaxUID.contains(".1.2.4.") || transferSyntaxUID.hasSuffix(".1.2.5") || transferSyntaxUID.hasSuffix(".1.2.1.99")
    }
}

public struct DICOMParser: Sendable {
    public init() {}

    public func metadata(_ data: Data) throws -> DICOMMetadata {
        guard data.count > 132 else { throw MolecularError.invalidMap("The DICOM file is incomplete.") }
        var result = DICOMMetadata()
        var offset = data[128..<132] == Data("DICM".utf8) ? 132 : 0
        while offset + 8 <= data.count {
            let group = uint16(data, offset, little: true)
            let element = uint16(data, offset + 2, little: true)
            let vr = String(data: data[(offset + 4)..<(offset + 6)], encoding: .ascii) ?? ""
            guard vr.allSatisfy({ $0.isUppercase }) else { break }
            let longVR = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)
            let lengthOffset = offset + (longVR ? 8 : 6)
            let valueOffset = offset + (longVR ? 12 : 8)
            guard lengthOffset + (longVR ? 4 : 2) <= data.count else { break }
            let length = longVR ? Int(uint32(data, lengthOffset, little: true)) : Int(uint16(data, lengthOffset, little: true))
            guard length >= 0, valueOffset + length <= data.count else { break }
            let tag = (UInt32(group) << 16) | UInt32(element)
            let value = Data(data[valueOffset..<(valueOffset + length)])
            switch tag {
            case 0x0002_0010: result.transferSyntaxUID = dicomString(value)
            case 0x0008_0020: result.studyDate = dicomString(value)
            case 0x0008_0060: result.modality = dicomString(value)
            case 0x0008_103E: result.seriesDescription = dicomString(value)
            case 0x0010_0010: result.patientName = dicomString(value)?.replacingOccurrences(of: "^", with: " ")
            case 0x0010_0020: result.patientID = dicomString(value)
            case 0x0020_000D: result.studyInstanceUID = dicomString(value)
            case 0x0020_000E: result.seriesInstanceUID = dicomString(value)
            case 0x0020_0013: result.instanceNumber = dicomString(value).flatMap(Int.init)
            case 0x0028_0008: result.numberOfFrames = dicomString(value).flatMap(Int.init) ?? 1
            case 0x0028_0010: result.rows = Int(uint16(value, 0, little: true))
            case 0x0028_0011: result.columns = Int(uint16(value, 0, little: true))
            default: break
            }
            offset = valueOffset + length
            if tag == 0x7FE0_0010 { break }
        }
        return result
    }

    public func parse(_ data: Data, name: String = "DICOM") throws -> VolumeMap {
        guard data.count > 132 else { throw MolecularError.invalidMap("The DICOM file is incomplete.") }
        let metadata = try metadata(data)
        if metadata.isCompressed {
            throw MolecularError.invalidMap(
                "This DICOM uses compressed transfer syntax \(metadata.transferSyntaxUID ?? "unknown"). Export it as uncompressed Explicit VR Little Endian before opening."
            )
        }
        var offset = data[128..<132] == Data("DICM".utf8) ? 132 : 0
        var rows = 0, columns = 0, bits = 16, signed = false
        var spacingX: Float = 1, spacingY: Float = 1, spacingZ: Float = 1
        var pixels: Data?
        while offset + 8 <= data.count {
            let group = uint16(data, offset, little: true)
            let element = uint16(data, offset + 2, little: true)
            let vr = String(data: data[(offset + 4)..<(offset + 6)], encoding: .ascii) ?? ""
            let longVR = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr)
            let lengthOffset = offset + (longVR ? 8 : 6)
            let valueOffset = offset + (longVR ? 12 : 8)
            guard lengthOffset + (longVR ? 4 : 2) <= data.count else { break }
            let length = longVR ? Int(uint32(data, lengthOffset, little: true)) : Int(uint16(data, lengthOffset, little: true))
            guard length >= 0, valueOffset + length <= data.count else { break }
            let tag = (UInt32(group) << 16) | UInt32(element)
            switch tag {
            case 0x0028_0010: rows = Int(uint16(data, valueOffset, little: true))
            case 0x0028_0011: columns = Int(uint16(data, valueOffset, little: true))
            case 0x0028_0100: bits = Int(uint16(data, valueOffset, little: true))
            case 0x0028_0103: signed = uint16(data, valueOffset, little: true) != 0
            case 0x0028_0030:
                let values = decimalValues(data[valueOffset..<(valueOffset + length)])
                if values.count >= 2 { spacingY = values[0]; spacingX = values[1] }
            case 0x0018_0050:
                spacingZ = decimalValues(data[valueOffset..<(valueOffset + length)]).first ?? 1
            case 0x7FE0_0010: pixels = Data(data[valueOffset..<(valueOffset + length)])
            default: break
            }
            offset = valueOffset + length
            if tag == 0x7FE0_0010 { break }
        }
        guard rows > 0, columns > 0, let pixels else { throw MolecularError.invalidMap("DICOM pixel data was not found.") }
        let count = rows * columns
        let bytesPerPixel = bits <= 8 ? 1 : 2
        guard pixels.count >= count * bytesPerPixel else { throw MolecularError.invalidMap("The DICOM pixel payload is incomplete.") }
        var slice: [Float] = []
        slice.reserveCapacity(count)
        for index in 0..<count {
            if bytesPerPixel == 1 { slice.append(Float(pixels[index])) }
            else if signed { slice.append(Float(int16(pixels, index * 2, little: true))) }
            else { slice.append(Float(uint16(pixels, index * 2, little: true))) }
        }
        return VolumeMap(
            name: name,
            dimensions: (columns, rows, 2),
            origin: .zero,
            spacing: Vector3(x: spacingX, y: spacingY, z: spacingZ),
            values: slice + slice
        )
    }

    public func parseSeries(_ files: [Data], name: String = "DICOM Series") throws -> VolumeMap {
        guard !files.isEmpty else { throw MolecularError.invalidMap("The DICOM series is empty.") }
        let slices = try files.enumerated().map { try parse($0.element, name: "Slice \($0.offset + 1)") }
        guard let first = slices.first,
              slices.allSatisfy({ $0.dimensions.x == first.dimensions.x && $0.dimensions.y == first.dimensions.y }) else {
            throw MolecularError.invalidMap("DICOM series slices have inconsistent dimensions.")
        }
        let sliceCount = first.dimensions.x * first.dimensions.y
        let values = slices.flatMap { Array($0.values.prefix(sliceCount)) }
        return VolumeMap(
            name: name,
            dimensions: (first.dimensions.x, first.dimensions.y, slices.count),
            origin: first.origin,
            spacing: first.spacing,
            values: values
        )
    }

    private func decimalValues(_ data: Data.SubSequence) -> [Float] {
        (String(data: data, encoding: .ascii) ?? "").split(separator: "\\").compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func dicomString(_ data: Data) -> String? {
        let value = String(data: data, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return value?.isEmpty == false ? value : nil
    }
}

private func uint16(_ data: Data, _ offset: Int, little: Bool) -> UInt16 {
    guard offset + 2 <= data.count else { return 0 }
    let a = UInt16(data[offset]), b = UInt16(data[offset + 1])
    return little ? a | (b << 8) : (a << 8) | b
}

private func int16(_ data: Data, _ offset: Int, little: Bool) -> Int16 {
    Int16(bitPattern: uint16(data, offset, little: little))
}

private func uint32(_ data: Data, _ offset: Int, little: Bool) -> UInt32 {
    guard offset + 4 <= data.count else { return 0 }
    let bytes = (0..<4).map { UInt32(data[offset + $0]) }
    return little
        ? bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
        : (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
}

private func int32(_ data: Data, _ offset: Int, little: Bool) -> Int32 {
    Int32(bitPattern: uint32(data, offset, little: little))
}

private func float32(_ data: Data, _ offset: Int, little: Bool) -> Float {
    Float(bitPattern: uint32(data, offset, little: little))
}

private func float64(_ data: Data, _ offset: Int, little: Bool) -> Double {
    guard offset + 8 <= data.count else { return 0 }
    let bytes = (0..<8).map { UInt64(data[offset + $0]) }
    let bits: UInt64
    if little { bits = bytes.enumerated().reduce(0) { $0 | ($1.element << UInt64($1.offset * 8)) } }
    else { bits = bytes.enumerated().reduce(0) { $0 | ($1.element << UInt64((7 - $1.offset) * 8)) } }
    return Double(bitPattern: bits)
}
