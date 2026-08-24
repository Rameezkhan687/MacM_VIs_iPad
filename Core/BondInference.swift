import Foundation

public enum BondInference {
    private struct Cell: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    public static func infer(atoms: [Atom]) -> [Bond] {
        let cellSize: Float = 2.6
        var grid: [Cell: [Int]] = [:]
        for atom in atoms {
            grid[cell(for: atom.position, size: cellSize), default: []].append(atom.id)
        }

        var bonds: [Bond] = []
        for atom in atoms {
            let base = cell(for: atom.position, size: cellSize)
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let nearby = grid[Cell(x: base.x + dx, y: base.y + dy, z: base.z + dz)] ?? []
                        for otherID in nearby where otherID > atom.id {
                            let other = atoms[otherID]
                            let distance = (atom.position - other.position).length
                            let cutoff = ElementTable.covalentRadius(for: atom.element)
                                + ElementTable.covalentRadius(for: other.element) + 0.45
                            if distance > 0.35 && distance <= cutoff {
                                bonds.append(Bond(atom1: atom.id, atom2: other.id))
                            }
                        }
                    }
                }
            }
        }
        return bonds
    }

    private static func cell(for p: Vector3, size: Float) -> Cell {
        Cell(
            x: Int(floor(p.x / size)),
            y: Int(floor(p.y / size)),
            z: Int(floor(p.z / size))
        )
    }
}
