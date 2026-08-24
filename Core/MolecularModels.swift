import Foundation

public struct Vector3: Codable, Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func / (lhs: Vector3, rhs: Float) -> Vector3 {
        Vector3(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }

    public var length: Float { sqrt(x * x + y * y + z * z) }
}

public struct Atom: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public let serial: Int
    public let name: String
    public let element: String
    public let residueName: String
    public let residueNumber: Int
    public let chainID: String
    public let position: Vector3
    public let occupancy: Float
    public let bFactor: Float
    public let isHetero: Bool

    public init(
        id: Int,
        serial: Int,
        name: String,
        element: String,
        residueName: String,
        residueNumber: Int,
        chainID: String,
        position: Vector3,
        occupancy: Float = 1,
        bFactor: Float = 0,
        isHetero: Bool = false
    ) {
        self.id = id
        self.serial = serial
        self.name = name
        self.element = element
        self.residueName = residueName
        self.residueNumber = residueNumber
        self.chainID = chainID
        self.position = position
        self.occupancy = occupancy
        self.bFactor = bFactor
        self.isHetero = isHetero
    }
}

public struct Bond: Codable, Hashable, Sendable {
    public let atom1: Int
    public let atom2: Int
    public let order: Int

    public init(atom1: Int, atom2: Int, order: Int = 1) {
        self.atom1 = min(atom1, atom2)
        self.atom2 = max(atom1, atom2)
        self.order = order
    }
}

public enum SecondaryStructureKind: String, Codable, Hashable, Sendable {
    case helix
    case sheet
    case coil
}

public struct SecondaryStructureSegment: Codable, Hashable, Sendable {
    public let kind: SecondaryStructureKind
    public let chainID: String
    public let startResidue: Int
    public let endResidue: Int

    public init(kind: SecondaryStructureKind, chainID: String, startResidue: Int, endResidue: Int) {
        self.kind = kind
        self.chainID = chainID
        self.startResidue = min(startResidue, endResidue)
        self.endResidue = max(startResidue, endResidue)
    }

    public func contains(chainID: String, residueNumber: Int) -> Bool {
        self.chainID == chainID && residueNumber >= startResidue && residueNumber <= endResidue
    }
}

public struct MolecularStructure: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var atoms: [Atom]
    public var bonds: [Bond]
    public var secondaryStructure: [SecondaryStructureSegment]

    public init(
        id: UUID = UUID(),
        name: String,
        atoms: [Atom],
        bonds: [Bond],
        secondaryStructure: [SecondaryStructureSegment] = []
    ) {
        self.id = id
        self.name = name
        self.atoms = atoms
        self.bonds = bonds
        self.secondaryStructure = secondaryStructure
    }

    public var center: Vector3 {
        guard !atoms.isEmpty else { return .zero }
        return atoms.reduce(.zero) { $0 + $1.position } / Float(atoms.count)
    }

    public var radius: Float {
        let c = center
        return max(1, atoms.map { ($0.position - c).length }.max() ?? 1)
    }

    public var chainIDs: [String] {
        Array(Set(atoms.map(\.chainID))).sorted()
    }

    public func secondaryStructureKind(chainID: String, residueNumber: Int) -> SecondaryStructureKind {
        secondaryStructure.first {
            $0.contains(chainID: chainID, residueNumber: residueNumber)
        }?.kind ?? .coil
    }
}

public struct VolumeMap: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let dimensions: (x: Int, y: Int, z: Int)
    public let origin: Vector3
    public let spacing: Vector3
    public let values: [Float]
    public let minimum: Float
    public let maximum: Float
    public let mean: Float

    public init(
        id: UUID = UUID(),
        name: String,
        dimensions: (x: Int, y: Int, z: Int),
        origin: Vector3,
        spacing: Vector3,
        values: [Float]
    ) {
        self.id = id
        self.name = name
        self.dimensions = dimensions
        self.origin = origin
        self.spacing = spacing
        self.values = values
        self.minimum = values.min() ?? 0
        self.maximum = values.max() ?? 0
        self.mean = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    public func value(x: Int, y: Int, z: Int) -> Float {
        values[x + dimensions.x * (y + dimensions.y * z)]
    }

    public var suggestedContour: Float {
        mean + (maximum - mean) * 0.18
    }
}

public enum MolecularError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case invalidPDB(String)
    case invalidMap(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let value): "Unsupported file: \(value)"
        case .invalidPDB(let value): "Invalid PDB: \(value)"
        case .invalidMap(let value): "Invalid density map: \(value)"
        case .network(let value): "Download failed: \(value)"
        }
    }
}
