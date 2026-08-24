import Foundation

public enum MolecularInteractionKind: String, Codable, Hashable, Sendable {
    case hydrogenBond = "Hydrogen bond"
    case contact = "Contact"
    case clash = "Clash"
}

public struct MolecularInteraction: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let atom1: Int
    public let atom2: Int
    public let distance: Float
    public let kind: MolecularInteractionKind

    public init(atom1: Int, atom2: Int, distance: Float, kind: MolecularInteractionKind) {
        self.atom1 = min(atom1, atom2)
        self.atom2 = max(atom1, atom2)
        self.distance = distance
        self.kind = kind
        self.id = "\(kind.rawValue):\(min(atom1, atom2)):\(max(atom1, atom2))"
    }
}

public struct MolecularSequence: Identifiable, Equatable, Sendable {
    public let id: String
    public let chainID: String
    public let residues: [String]
    public let codes: String

    public init(chainID: String, residues: [String], codes: String) {
        self.id = chainID
        self.chainID = chainID
        self.residues = residues
        self.codes = codes
    }
}

public struct SequenceAlignment: Equatable, Sendable {
    public let first: String
    public let second: String
    public let identity: Double
}

public struct StructuralComparison: Sendable {
    public let alignedStructure: MolecularStructure
    public let rmsd: Float
    public let matchedAtomCount: Int
}

public struct MolecularCavity: Identifiable, Sendable {
    public let id: Int
    public let center: Vector3
    public let volume: Float
    public let voxelCount: Int
}

public struct MolecularInterface: Identifiable, Sendable {
    public let id: String
    public let chain1: String
    public let chain2: String
    public let contactCount: Int
    public let minimumDistance: Float
}

public struct SequenceConservation: Sendable {
    public let consensus: String
    public let scores: [Double]
}

public struct MolecularAnalysisEngine: Sendable {
    private struct Cell: Hashable {
        let x: Int; let y: Int; let z: Int
    }

    public init() {}

    public func hydrogenBonds(in structure: MolecularStructure, maximum: Int = 5_000) -> [MolecularInteraction] {
        let eligible = Set(["N", "O", "S"])
        return nearbyPairs(in: structure, cutoff: 3.5, maximum: maximum).compactMap { first, second, distance in
            let a = structure.atoms[first]
            let b = structure.atoms[second]
            guard distance >= 2.2,
                  eligible.contains(ElementTable.normalized(a.element)),
                  eligible.contains(ElementTable.normalized(b.element)),
                  !structure.bonds.contains(Bond(atom1: a.id, atom2: b.id)) else { return nil }
            return MolecularInteraction(atom1: a.id, atom2: b.id, distance: distance, kind: .hydrogenBond)
        }
    }

    public func contacts(in structure: MolecularStructure, cutoff: Float = 4, maximum: Int = 8_000) -> [MolecularInteraction] {
        let bonds = Set(structure.bonds)
        return nearbyPairs(in: structure, cutoff: cutoff, maximum: maximum).compactMap { first, second, distance in
            let a = structure.atoms[first]
            let b = structure.atoms[second]
            guard distance > 1.5, !bonds.contains(Bond(atom1: a.id, atom2: b.id)) else { return nil }
            return MolecularInteraction(atom1: a.id, atom2: b.id, distance: distance, kind: .contact)
        }
    }

    public func clashes(in structure: MolecularStructure, overlap: Float = 0.6, maximum: Int = 5_000) -> [MolecularInteraction] {
        let bonds = Set(structure.bonds)
        return nearbyPairs(in: structure, cutoff: 4.2, maximum: maximum).compactMap { first, second, distance in
            let a = structure.atoms[first]
            let b = structure.atoms[second]
            let allowed = ElementTable.vanDerWaalsRadius(for: a.element) + ElementTable.vanDerWaalsRadius(for: b.element) - overlap
            guard distance < allowed, !bonds.contains(Bond(atom1: a.id, atom2: b.id)) else { return nil }
            return MolecularInteraction(atom1: a.id, atom2: b.id, distance: distance, kind: .clash)
        }
    }

    public func centroid(of atoms: [Atom]) -> Vector3 {
        guard !atoms.isEmpty else { return .zero }
        return atoms.reduce(.zero) { $0 + $1.position } / Float(atoms.count)
    }

    public func principalAxis(of atoms: [Atom]) -> Vector3 {
        guard atoms.count >= 2 else { return Vector3(x: 1, y: 0, z: 0) }
        let center = centroid(of: atoms)
        var xx: Float = 0, xy: Float = 0, xz: Float = 0
        var yy: Float = 0, yz: Float = 0, zz: Float = 0
        for atom in atoms {
            let p = atom.position - center
            xx += p.x * p.x; xy += p.x * p.y; xz += p.x * p.z
            yy += p.y * p.y; yz += p.y * p.z; zz += p.z * p.z
        }
        var axis = Vector3(x: 1, y: 0.5, z: 0.25)
        for _ in 0..<20 {
            let next = Vector3(
                x: xx * axis.x + xy * axis.y + xz * axis.z,
                y: xy * axis.x + yy * axis.y + yz * axis.z,
                z: xz * axis.x + yz * axis.y + zz * axis.z
            )
            let length = max(0.000_001, next.length)
            axis = next / length
        }
        return axis
    }

    public func bestFitPlane(of atoms: [Atom]) -> (center: Vector3, normal: Vector3, rmsd: Float)? {
        guard atoms.count >= 3 else { return nil }
        let center = centroid(of: atoms)
        var matrix = [Float](repeating: 0, count: 9)
        for atom in atoms {
            let p = atom.position - center
            matrix[0] += p.x * p.x; matrix[1] += p.x * p.y; matrix[2] += p.x * p.z
            matrix[3] += p.y * p.x; matrix[4] += p.y * p.y; matrix[5] += p.y * p.z
            matrix[6] += p.z * p.x; matrix[7] += p.z * p.y; matrix[8] += p.z * p.z
        }
        let regularizer = max(0.000_001, (matrix[0] + matrix[4] + matrix[8]) * 0.000_001)
        matrix[0] += regularizer; matrix[4] += regularizer; matrix[8] += regularizer
        guard let inverse = inverse3x3(matrix) else { return nil }
        var normal = Vector3(x: 0.31, y: 0.53, z: 0.79)
        for _ in 0..<24 {
            let next = Vector3(
                x: inverse[0] * normal.x + inverse[1] * normal.y + inverse[2] * normal.z,
                y: inverse[3] * normal.x + inverse[4] * normal.y + inverse[5] * normal.z,
                z: inverse[6] * normal.x + inverse[7] * normal.y + inverse[8] * normal.z
            )
            normal = next / max(0.000_001, next.length)
        }
        let squared = atoms.reduce(Float.zero) { total, atom in
            let p = atom.position - center
            let distance = p.x * normal.x + p.y * normal.y + p.z * normal.z
            return total + distance * distance
        }
        return (center, normal, sqrt(squared / Float(atoms.count)))
    }

    public func cavities(in structure: MolecularStructure, spacing: Float = 1.5) -> [MolecularCavity] {
        let atoms = Array(structure.atoms.prefix(20_000))
        guard !atoms.isEmpty else { return [] }
        let padding: Float = 2.5
        let minimum = Vector3(
            x: (atoms.map(\.position.x).min() ?? 0) - padding,
            y: (atoms.map(\.position.y).min() ?? 0) - padding,
            z: (atoms.map(\.position.z).min() ?? 0) - padding
        )
        let maximum = Vector3(
            x: (atoms.map(\.position.x).max() ?? 0) + padding,
            y: (atoms.map(\.position.y).max() ?? 0) + padding,
            z: (atoms.map(\.position.z).max() ?? 0) + padding
        )
        let dimensions = (
            x: min(52, max(3, Int(ceil((maximum.x - minimum.x) / spacing)) + 1)),
            y: min(52, max(3, Int(ceil((maximum.y - minimum.y) / spacing)) + 1)),
            z: min(52, max(3, Int(ceil((maximum.z - minimum.z) / spacing)) + 1))
        )
        let count = dimensions.x * dimensions.y * dimensions.z
        func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + dimensions.x * (y + dimensions.y * z) }
        var occupied = [Bool](repeating: false, count: count)
        for atom in atoms {
            let radius = ElementTable.vanDerWaalsRadius(for: atom.element)
            let centerX = Int(((atom.position.x - minimum.x) / spacing).rounded())
            let centerY = Int(((atom.position.y - minimum.y) / spacing).rounded())
            let centerZ = Int(((atom.position.z - minimum.z) / spacing).rounded())
            let gridRadius = Int(ceil(radius / spacing))
            for z in max(0, centerZ - gridRadius)...min(dimensions.z - 1, centerZ + gridRadius) {
                for y in max(0, centerY - gridRadius)...min(dimensions.y - 1, centerY + gridRadius) {
                    for x in max(0, centerX - gridRadius)...min(dimensions.x - 1, centerX + gridRadius) {
                        let point = Vector3(x: minimum.x + Float(x) * spacing, y: minimum.y + Float(y) * spacing, z: minimum.z + Float(z) * spacing)
                        if (point - atom.position).length <= radius { occupied[index(x, y, z)] = true }
                    }
                }
            }
        }
        let neighbors = [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]
        var exterior = [Bool](repeating: false, count: count)
        var queue: [(Int, Int, Int)] = []
        for z in 0..<dimensions.z { for y in 0..<dimensions.y { for x in 0..<dimensions.x
            where x == 0 || y == 0 || z == 0 || x == dimensions.x - 1 || y == dimensions.y - 1 || z == dimensions.z - 1 {
            let i = index(x, y, z)
            if !occupied[i], !exterior[i] { exterior[i] = true; queue.append((x, y, z)) }
        } } }
        var cursor = 0
        while cursor < queue.count {
            let (x, y, z) = queue[cursor]; cursor += 1
            for offset in neighbors {
                let nx = x + offset.0, ny = y + offset.1, nz = z + offset.2
                guard nx >= 0, ny >= 0, nz >= 0, nx < dimensions.x, ny < dimensions.y, nz < dimensions.z else { continue }
                let i = index(nx, ny, nz)
                if !occupied[i], !exterior[i] { exterior[i] = true; queue.append((nx, ny, nz)) }
            }
        }
        var visited = exterior
        var cavities: [MolecularCavity] = []
        for z in 1..<(dimensions.z - 1) { for y in 1..<(dimensions.y - 1) { for x in 1..<(dimensions.x - 1) {
            let start = index(x, y, z)
            guard !occupied[start], !visited[start] else { continue }
            var component = [(x, y, z)]
            visited[start] = true
            var componentCursor = 0
            var sum = Vector3.zero
            while componentCursor < component.count {
                let point = component[componentCursor]; componentCursor += 1
                sum = sum + Vector3(x: minimum.x + Float(point.0) * spacing, y: minimum.y + Float(point.1) * spacing, z: minimum.z + Float(point.2) * spacing)
                for offset in neighbors {
                    let nx = point.0 + offset.0, ny = point.1 + offset.1, nz = point.2 + offset.2
                    guard nx > 0, ny > 0, nz > 0, nx < dimensions.x - 1, ny < dimensions.y - 1, nz < dimensions.z - 1 else { continue }
                    let i = index(nx, ny, nz)
                    if !occupied[i], !visited[i] { visited[i] = true; component.append((nx, ny, nz)) }
                }
            }
            guard component.count >= 3 else { continue }
            cavities.append(MolecularCavity(
                id: cavities.count,
                center: sum / Float(component.count),
                volume: Float(component.count) * spacing * spacing * spacing,
                voxelCount: component.count
            ))
        } } }
        return cavities.sorted { $0.volume > $1.volume }
    }

    public func interfaces(in structure: MolecularStructure, cutoff: Float = 5) -> [MolecularInterface] {
        var grouped: [String: (String, String, Int, Float)] = [:]
        for (firstIndex, secondIndex, distance) in nearbyPairs(in: structure, cutoff: cutoff, maximum: 100_000) {
            let first = structure.atoms[firstIndex], second = structure.atoms[secondIndex]
            guard first.chainID != second.chainID else { continue }
            let chains = [first.chainID, second.chainID].sorted()
            let key = "\(chains[0])|\(chains[1])"
            let current = grouped[key] ?? (chains[0], chains[1], 0, Float.greatestFiniteMagnitude)
            grouped[key] = (current.0, current.1, current.2 + 1, min(current.3, distance))
        }
        return grouped.values.map {
            MolecularInterface(id: "\($0.0)|\($0.1)", chain1: $0.0, chain2: $0.1, contactCount: $0.2, minimumDistance: $0.3)
        }.sorted { $0.contactCount > $1.contactCount }
    }

    public func estimatedSurfaceArea(of atoms: [Atom], probeRadius: Float = 1.4) -> Float {
        guard !atoms.isEmpty else { return 0 }
        let pi = Float.pi
        var area = atoms.reduce(Float.zero) { total, atom in
            let r = ElementTable.vanDerWaalsRadius(for: atom.element) + probeRadius
            return total + 4 * pi * r * r
        }
        let structure = MolecularStructure(name: "area", atoms: atoms, bonds: [])
        for (first, second, distance) in nearbyPairs(in: structure, cutoff: 7, maximum: 50_000) {
            let r1 = ElementTable.vanDerWaalsRadius(for: atoms[first].element) + probeRadius
            let r2 = ElementTable.vanDerWaalsRadius(for: atoms[second].element) + probeRadius
            guard distance < r1 + r2, distance > abs(r1 - r2) else { continue }
            let cap1 = r1 - (distance * distance + r1 * r1 - r2 * r2) / (2 * distance)
            let cap2 = r2 - (distance * distance + r2 * r2 - r1 * r1) / (2 * distance)
            area -= max(0, 2 * pi * r1 * cap1 + 2 * pi * r2 * cap2) * 0.5
        }
        return max(0, area)
    }

    public func estimatedVolume(of atoms: [Atom]) -> Float {
        atoms.reduce(0) { total, atom in
            let radius = ElementTable.vanDerWaalsRadius(for: atom.element)
            return total + 4 * Float.pi * radius * radius * radius / 3
        }
    }

    public func sequences(in structure: MolecularStructure) -> [MolecularSequence] {
        var residuesByChain: [String: [(number: Int, name: String)]] = [:]
        var seen = Set<String>()
        for atom in structure.atoms {
            let key = "\(atom.chainID):\(atom.residueNumber):\(atom.residueName)"
            guard seen.insert(key).inserted else { continue }
            residuesByChain[atom.chainID, default: []].append((atom.residueNumber, atom.residueName.uppercased()))
        }
        return residuesByChain.keys.sorted().map { chain in
            let residues = (residuesByChain[chain] ?? []).sorted { $0.number < $1.number }.map(\.name)
            return MolecularSequence(
                chainID: chain,
                residues: residues,
                codes: String(residues.map(oneLetterCode))
            )
        }
    }

    public func align(_ first: String, _ second: String) -> SequenceAlignment {
        let a = Array(first), b = Array(second)
        let gap = -2, match = 2, mismatch = -1
        var score = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty { for index in 1...a.count { score[index][0] = index * gap } }
        if !b.isEmpty { for index in 1...b.count { score[0][index] = index * gap } }
        if !a.isEmpty, !b.isEmpty {
            for i in 1...a.count {
                for j in 1...b.count {
                    score[i][j] = max(
                        score[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch),
                        score[i - 1][j] + gap,
                        score[i][j - 1] + gap
                    )
                }
            }
        }
        var i = a.count, j = b.count
        var alignedA: [Character] = [], alignedB: [Character] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0,
               score[i][j] == score[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch) {
                alignedA.append(a[i - 1]); alignedB.append(b[j - 1]); i -= 1; j -= 1
            } else if i > 0, score[i][j] == score[i - 1][j] + gap {
                alignedA.append(a[i - 1]); alignedB.append("-"); i -= 1
            } else {
                alignedA.append("-"); alignedB.append(b[j - 1]); j -= 1
            }
        }
        let firstAligned = String(alignedA.reversed())
        let secondAligned = String(alignedB.reversed())
        let paired = zip(firstAligned, secondAligned).filter { $0 != "-" && $1 != "-" }
        let pairedCount = paired.count
        let identities = zip(firstAligned, secondAligned).filter { $0 == $1 && $0 != "-" }.count
        return SequenceAlignment(
            first: firstAligned,
            second: secondAligned,
            identity: pairedCount == 0 ? 0 : Double(identities) / Double(pairedCount)
        )
    }

    public func conservation(of sequences: [String]) -> SequenceConservation? {
        guard let first = sequences.first, !first.isEmpty else { return nil }
        let alignments = sequences.dropFirst().map { align(first, $0) }
        guard !alignments.isEmpty else { return SequenceConservation(consensus: first, scores: Array(repeating: 1, count: first.count)) }
        var columns = Array(first).map { [String($0)] }
        for alignment in alignments {
            var firstIndex = 0
            for pair in zip(alignment.first, alignment.second) where pair.0 != "-" {
                if firstIndex < columns.count { columns[firstIndex].append(String(pair.1)) }
                firstIndex += 1
            }
        }
        var consensus = ""
        var scores: [Double] = []
        for column in columns {
            let residues = column.filter { $0 != "-" }
            let counts = Dictionary(grouping: residues, by: { $0 }).mapValues(\.count)
            let best = counts.max { $0.value < $1.value }
            consensus += best?.key ?? "X"
            scores.append(residues.isEmpty ? 0 : Double(best?.value ?? 0) / Double(residues.count))
        }
        return SequenceConservation(consensus: consensus, scores: scores)
    }

    public func superpose(_ moving: MolecularStructure, onto reference: MolecularStructure) -> StructuralComparison? {
        let referenceByKey = Dictionary(uniqueKeysWithValues: reference.atoms.map { (atomKey($0), $0) })
        let pairs = moving.atoms.compactMap { atom -> (Atom, Atom)? in
            referenceByKey[atomKey(atom)].map { (atom, $0) }
        }
        guard pairs.count >= 3 else { return nil }
        let movingCenter = centroid(of: pairs.map(\.0))
        let referenceCenter = centroid(of: pairs.map(\.1))
        var covariance = [Float](repeating: 0, count: 9)
        for pair in pairs {
            let p = pair.0.position - movingCenter
            let q = pair.1.position - referenceCenter
            covariance[0] += p.x * q.x; covariance[1] += p.x * q.y; covariance[2] += p.x * q.z
            covariance[3] += p.y * q.x; covariance[4] += p.y * q.y; covariance[5] += p.y * q.z
            covariance[6] += p.z * q.x; covariance[7] += p.z * q.y; covariance[8] += p.z * q.z
        }
        let quaternion = optimalQuaternion(covariance)
        func transformed(_ point: Vector3) -> Vector3 {
            rotate(point - movingCenter, by: quaternion) + referenceCenter
        }
        var aligned = moving
        aligned.name = "\(moving.name) · matched"
        for index in aligned.atoms.indices { aligned.atoms[index].position = transformed(aligned.atoms[index].position) }
        let squared = pairs.reduce(Float.zero) { total, pair in
            let delta = transformed(pair.0.position) - pair.1.position
            return total + delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
        }
        return StructuralComparison(
            alignedStructure: aligned,
            rmsd: sqrt(squared / Float(pairs.count)),
            matchedAtomCount: pairs.count
        )
    }

    private func nearbyPairs(
        in structure: MolecularStructure,
        cutoff: Float,
        maximum: Int
    ) -> [(Int, Int, Float)] {
        let atoms = Array(structure.atoms.prefix(30_000))
        var grid: [Cell: [Int]] = [:]
        func cell(_ position: Vector3) -> Cell {
            Cell(x: Int(floor(position.x / cutoff)), y: Int(floor(position.y / cutoff)), z: Int(floor(position.z / cutoff)))
        }
        for index in atoms.indices { grid[cell(atoms[index].position), default: []].append(index) }
        var result: [(Int, Int, Float)] = []
        for first in atoms.indices {
            let origin = cell(atoms[first].position)
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 {
                let neighbor = Cell(x: origin.x + dx, y: origin.y + dy, z: origin.z + dz)
                for second in grid[neighbor] ?? [] where second > first {
                    let distance = (atoms[first].position - atoms[second].position).length
                    if distance <= cutoff { result.append((first, second, distance)) }
                    if result.count >= maximum { return result }
                }
            } } }
        }
        return result
    }

    private func atomKey(_ atom: Atom) -> String {
        "\(atom.chainID)|\(atom.residueNumber)|\(atom.residueName)|\(atom.name)"
    }

    private func inverse3x3(_ m: [Float]) -> [Float]? {
        let determinant = m[0] * (m[4] * m[8] - m[5] * m[7])
            - m[1] * (m[3] * m[8] - m[5] * m[6])
            + m[2] * (m[3] * m[7] - m[4] * m[6])
        guard abs(determinant) > 0.000_000_001 else { return nil }
        let inverse = 1 / determinant
        return [
            (m[4] * m[8] - m[5] * m[7]) * inverse,
            (m[2] * m[7] - m[1] * m[8]) * inverse,
            (m[1] * m[5] - m[2] * m[4]) * inverse,
            (m[5] * m[6] - m[3] * m[8]) * inverse,
            (m[0] * m[8] - m[2] * m[6]) * inverse,
            (m[2] * m[3] - m[0] * m[5]) * inverse,
            (m[3] * m[7] - m[4] * m[6]) * inverse,
            (m[1] * m[6] - m[0] * m[7]) * inverse,
            (m[0] * m[4] - m[1] * m[3]) * inverse
        ]
    }

    private func oneLetterCode(_ residue: String) -> Character {
        let codes: [String: Character] = [
            "ALA":"A", "ARG":"R", "ASN":"N", "ASP":"D", "CYS":"C", "GLN":"Q", "GLU":"E",
            "GLY":"G", "HIS":"H", "ILE":"I", "LEU":"L", "LYS":"K", "MET":"M", "PHE":"F",
            "PRO":"P", "SER":"S", "THR":"T", "TRP":"W", "TYR":"Y", "VAL":"V",
            "A":"A", "C":"C", "G":"G", "U":"U", "T":"T", "DA":"A", "DC":"C", "DG":"G", "DT":"T"
        ]
        return codes[residue] ?? "X"
    }

    private func optimalQuaternion(_ s: [Float]) -> (w: Float, x: Float, y: Float, z: Float) {
        let trace = s[0] + s[4] + s[8]
        let matrix: [[Float]] = [
            [trace, s[5] - s[7], s[6] - s[2], s[1] - s[3]],
            [s[5] - s[7], s[0] - s[4] - s[8], s[1] + s[3], s[2] + s[6]],
            [s[6] - s[2], s[1] + s[3], -s[0] + s[4] - s[8], s[5] + s[7]],
            [s[1] - s[3], s[2] + s[6], s[5] + s[7], -s[0] - s[4] + s[8]]
        ]
        var q: [Float] = [1, 0, 0, 0]
        for _ in 0..<30 {
            var next = [Float](repeating: 0, count: 4)
            for row in 0..<4 { for column in 0..<4 { next[row] += matrix[row][column] * q[column] } }
            let length = sqrt(next.reduce(0) { $0 + $1 * $1 })
            guard length > 0.000_001 else { break }
            q = next.map { $0 / length }
        }
        return (q[0], q[1], q[2], q[3])
    }

    private func rotate(_ p: Vector3, by q: (w: Float, x: Float, y: Float, z: Float)) -> Vector3 {
        let u = Vector3(x: q.x, y: q.y, z: q.z)
        let dotUP = u.x * p.x + u.y * p.y + u.z * p.z
        let dotUU = u.x * u.x + u.y * u.y + u.z * u.z
        let cross = Vector3(
            x: u.y * p.z - u.z * p.y,
            y: u.z * p.x - u.x * p.z,
            z: u.x * p.y - u.y * p.x
        )
        return Vector3(
            x: 2 * dotUP * u.x + (q.w * q.w - dotUU) * p.x + 2 * q.w * cross.x,
            y: 2 * dotUP * u.y + (q.w * q.w - dotUU) * p.y + 2 * q.w * cross.y,
            z: 2 * dotUP * u.z + (q.w * q.w - dotUU) * p.z + 2 * q.w * cross.z
        )
    }
}
