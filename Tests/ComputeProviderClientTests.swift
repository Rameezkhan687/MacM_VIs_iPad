import Foundation
import Testing
@testable import MoleculePadCore

@Suite struct ComputeProviderClientTests {
    @Test func writesRoundTrippablePDB() throws {
        let structure = MolecularStructure(name: "Export", atoms: [
            Atom(id: 0, serial: 1, name: "CA", element: "C", residueName: "GLY", residueNumber: 1, chainID: "A", position: Vector3(x: 1, y: 2, z: 3))
        ], bonds: [])
        let data = StructureFileWriter().pdb(structure)
        let restored = try PDBParser().parse(data)
        #expect(restored.atoms.count == 1)
        #expect(restored.atoms[0].position == Vector3(x: 1, y: 2, z: 3))
    }

    @Test func validatesComputeResponseURLs() throws {
        let valid = MolecularComputeResponse(summary: "Prediction complete", structureURL: "https://example.org/model.cif")
        #expect(try MolecularComputeClient().validated(valid) == valid)
        let invalid = MolecularComputeResponse(summary: "Bad", structureURL: "file:///private/model.pdb")
        #expect(throws: MolecularError.self) { try MolecularComputeClient().validated(invalid) }
    }
}
