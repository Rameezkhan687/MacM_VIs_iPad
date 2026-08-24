import Foundation

public enum MolecularSelectionQuery: Equatable, Sendable {
    case all
    case chain(String)
    case residueNumber(Int)
    case residueName(String)
    case element(String)
    case atomName(String)
    case ligand
    case water
}

public struct MolecularSelectionEngine: Sendable {
    private static let waterResidues = Set(["HOH", "WAT", "H2O", "DOD"])

    public init() {}

    public func atomIDs(in structure: MolecularStructure, matching query: MolecularSelectionQuery) -> [Int] {
        structure.atoms.compactMap { atom in
            let matches: Bool
            switch query {
            case .all:
                matches = true
            case .chain(let chainID):
                matches = atom.chainID.caseInsensitiveCompare(chainID) == .orderedSame
            case .residueNumber(let number):
                matches = atom.residueNumber == number
            case .residueName(let name):
                matches = atom.residueName.caseInsensitiveCompare(name) == .orderedSame
            case .element(let element):
                matches = ElementTable.normalized(atom.element) == ElementTable.normalized(element)
            case .atomName(let name):
                matches = atom.name.caseInsensitiveCompare(name) == .orderedSame
            case .ligand:
                matches = atom.isHetero && !Self.waterResidues.contains(atom.residueName.uppercased())
            case .water:
                matches = Self.waterResidues.contains(atom.residueName.uppercased())
            }
            return matches ? atom.id : nil
        }
    }
}

public enum MolecularMeasurements {
    public static func distance(_ first: Vector3, _ second: Vector3) -> Float {
        (first - second).length
    }

    public static func angle(_ first: Vector3, _ vertex: Vector3, _ third: Vector3) -> Float? {
        let a = components(first - vertex)
        let b = components(third - vertex)
        let denominator = length(a) * length(b)
        guard denominator > 0.000_001 else { return nil }
        let cosine = max(-1, min(1, dot(a, b) / denominator))
        return acos(cosine) * 180 / .pi
    }

    public static func torsion(_ first: Vector3, _ second: Vector3, _ third: Vector3, _ fourth: Vector3) -> Float? {
        let b0 = components(first - second)
        let b1 = components(third - second)
        let b2 = components(fourth - third)
        let b1Length = length(b1)
        guard b1Length > 0.000_001 else { return nil }
        let axis = scale(b1, by: 1 / b1Length)
        let v = subtract(b0, scale(axis, by: dot(b0, axis)))
        let w = subtract(b2, scale(axis, by: dot(b2, axis)))
        guard length(v) > 0.000_001, length(w) > 0.000_001 else { return nil }
        let x = dot(v, w)
        let y = dot(cross(axis, v), w)
        return atan2(y, x) * 180 / .pi
    }

    private static func components(_ value: Vector3) -> (Float, Float, Float) {
        (value.x, value.y, value.z)
    }

    private static func dot(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> Float {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    private static func length(_ value: (Float, Float, Float)) -> Float {
        sqrt(dot(value, value))
    }

    private static func scale(_ value: (Float, Float, Float), by scalar: Float) -> (Float, Float, Float) {
        (value.0 * scalar, value.1 * scalar, value.2 * scalar)
    }

    private static func subtract(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> (Float, Float, Float) {
        (a.0 - b.0, a.1 - b.1, a.2 - b.2)
    }

    private static func cross(_ a: (Float, Float, Float), _ b: (Float, Float, Float)) -> (Float, Float, Float) {
        (
            a.1 * b.2 - a.2 * b.1,
            a.2 * b.0 - a.0 * b.2,
            a.0 * b.1 - a.1 * b.0
        )
    }
}
