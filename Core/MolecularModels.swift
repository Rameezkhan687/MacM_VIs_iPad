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
    public var position: Vector3
    public let occupancy: Float
    public let bFactor: Float
    public let isHetero: Bool
    public var partialCharge: Float

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
        isHetero: Bool = false,
        partialCharge: Float = 0
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
        self.partialCharge = partialCharge
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

public struct MolecularTransform: Codable, Hashable, Sendable {
    public var m11: Float; public var m12: Float; public var m13: Float; public var tx: Float
    public var m21: Float; public var m22: Float; public var m23: Float; public var ty: Float
    public var m31: Float; public var m32: Float; public var m33: Float; public var tz: Float

    public init(
        m11: Float = 1, m12: Float = 0, m13: Float = 0, tx: Float = 0,
        m21: Float = 0, m22: Float = 1, m23: Float = 0, ty: Float = 0,
        m31: Float = 0, m32: Float = 0, m33: Float = 1, tz: Float = 0
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.tx = tx
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.ty = ty
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.tz = tz
    }

    public static let identity = MolecularTransform()

    public func applying(to point: Vector3) -> Vector3 {
        Vector3(
            x: m11 * point.x + m12 * point.y + m13 * point.z + tx,
            y: m21 * point.x + m22 * point.y + m23 * point.z + ty,
            z: m31 * point.x + m32 * point.y + m33 * point.z + tz
        )
    }

    public func followed(by next: MolecularTransform) -> MolecularTransform {
        MolecularTransform(
            m11: next.m11 * m11 + next.m12 * m21 + next.m13 * m31,
            m12: next.m11 * m12 + next.m12 * m22 + next.m13 * m32,
            m13: next.m11 * m13 + next.m12 * m23 + next.m13 * m33,
            tx: next.m11 * tx + next.m12 * ty + next.m13 * tz + next.tx,
            m21: next.m21 * m11 + next.m22 * m21 + next.m23 * m31,
            m22: next.m21 * m12 + next.m22 * m22 + next.m23 * m32,
            m23: next.m21 * m13 + next.m22 * m23 + next.m23 * m33,
            ty: next.m21 * tx + next.m22 * ty + next.m23 * tz + next.ty,
            m31: next.m31 * m11 + next.m32 * m21 + next.m33 * m31,
            m32: next.m31 * m12 + next.m32 * m22 + next.m33 * m32,
            m33: next.m31 * m13 + next.m32 * m23 + next.m33 * m33,
            tz: next.m31 * tx + next.m32 * ty + next.m33 * tz + next.tz
        )
    }
}

public struct AssemblyInstance: Codable, Hashable, Sendable {
    public let operatorID: String
    public let chainIDs: [String]
    public let transform: MolecularTransform

    public init(operatorID: String, chainIDs: [String], transform: MolecularTransform) {
        self.operatorID = operatorID
        self.chainIDs = chainIDs
        self.transform = transform
    }
}

public struct BiologicalAssembly: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let details: String
    public let instances: [AssemblyInstance]

    public init(id: String, details: String = "Deposited biological assembly", instances: [AssemblyInstance]) {
        self.id = id
        self.details = details
        self.instances = instances
    }
}

public struct AlternateConformation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let positions: [Int: Vector3]

    public init(id: String, positions: [Int: Vector3]) {
        self.id = id
        self.positions = positions
    }
}

public struct MolecularStructure: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var atoms: [Atom]
    public var bonds: [Bond]
    public var secondaryStructure: [SecondaryStructureSegment]
    public var biologicalAssemblies: [BiologicalAssembly]
    public var alternateConformations: [AlternateConformation]

    public init(
        id: UUID = UUID(),
        name: String,
        atoms: [Atom],
        bonds: [Bond],
        secondaryStructure: [SecondaryStructureSegment] = [],
        biologicalAssemblies: [BiologicalAssembly] = [],
        alternateConformations: [AlternateConformation] = []
    ) {
        self.id = id
        self.name = name
        self.atoms = atoms
        self.bonds = bonds
        self.secondaryStructure = secondaryStructure
        self.biologicalAssemblies = biologicalAssemblies
        self.alternateConformations = alternateConformations
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

    public func applyingAlternateConformation(_ identifier: String?) -> MolecularStructure {
        guard let identifier,
              let conformation = alternateConformations.first(where: { $0.id.caseInsensitiveCompare(identifier) == .orderedSame }) else {
            return self
        }
        var copy = self
        copy.name = "\(name) · Alt \(conformation.id)"
        for index in copy.atoms.indices {
            if let position = conformation.positions[copy.atoms[index].id] {
                copy.atoms[index].position = position
            }
        }
        return copy
    }
}

public struct MolecularTrajectory: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var frames: [MolecularStructure]

    public init(id: UUID = UUID(), name: String, frames: [MolecularStructure]) {
        self.id = id
        self.name = name
        self.frames = frames
    }

    public var frameCount: Int { frames.count }
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
    case invalidMMCIF(String)
    case invalidStructure(String)
    case invalidMap(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let value): "Unsupported file: \(value)"
        case .invalidPDB(let value): "Invalid PDB: \(value)"
        case .invalidMMCIF(let value): "Invalid mmCIF: \(value)"
        case .invalidStructure(let value): "Invalid structure: \(value)"
        case .invalidMap(let value): "Invalid density map: \(value)"
        case .network(let value): "Download failed: \(value)"
        }
    }
}
