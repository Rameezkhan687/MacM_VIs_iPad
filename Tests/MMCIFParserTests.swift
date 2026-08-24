import Testing
@testable import MoleculePadCore

struct MMCIFParserTests {
    private let sample = """
    data_demo
    loop_
    _struct_conf.conf_type_id
    _struct_conf.beg_auth_asym_id
    _struct_conf.beg_auth_seq_id
    _struct_conf.end_auth_asym_id
    _struct_conf.end_auth_seq_id
    HELX_P A 1 A 2
    #
    loop_
    _atom_site.group_PDB
    _atom_site.id
    _atom_site.type_symbol
    _atom_site.auth_atom_id
    _atom_site.auth_comp_id
    _atom_site.auth_asym_id
    _atom_site.auth_seq_id
    _atom_site.Cartn_x
    _atom_site.Cartn_y
    _atom_site.Cartn_z
    _atom_site.occupancy
    _atom_site.B_iso_or_equiv
    ATOM 1 N N ALA A 1 0.0 0.0 0.0 1.0 10.0
    ATOM 2 C CA ALA A 1 1.45 0.0 0.0 1.0 11.0
    ATOM 3 C C ALA A 1 2.10 1.3 0.0 1.0 12.0
    ATOM 4 O O ALA A 1 1.60 2.4 0.0 1.0 13.0
    ATOM 5 N N GLY A 2 3.30 1.2 0.0 1.0 14.0
    ATOM 6 C CA GLY A 2 4.00 2.4 0.0 1.0 15.0
    #
    """

    @Test func parsesAtomsAndSecondaryStructure() throws {
        let structure = try MMCIFParser().parse(sample, name: "Demo")

        #expect(structure.name == "Demo")
        #expect(structure.atoms.count == 6)
        #expect(structure.atoms[1].name == "CA")
        #expect(structure.atoms[4].residueNumber == 2)
        #expect(structure.chainIDs == ["A"])
        #expect(structure.secondaryStructure == [SecondaryStructureSegment(
            kind: .helix,
            chainID: "A",
            startResidue: 1,
            endResidue: 2
        )])
    }

    @Test func rejectsCoordinateFreeCIF() {
        #expect(throws: MolecularError.self) {
            try MMCIFParser().parse("data_empty\n_entry.id empty")
        }
    }

    @Test func parsesAndBuildsBiologicalAssembly() throws {
        let cif = """
        data_assembly
        loop_
        _pdbx_struct_oper_list.id
        _pdbx_struct_oper_list.matrix[1][1]
        _pdbx_struct_oper_list.matrix[1][2]
        _pdbx_struct_oper_list.matrix[1][3]
        _pdbx_struct_oper_list.vector[1]
        _pdbx_struct_oper_list.matrix[2][1]
        _pdbx_struct_oper_list.matrix[2][2]
        _pdbx_struct_oper_list.matrix[2][3]
        _pdbx_struct_oper_list.vector[2]
        _pdbx_struct_oper_list.matrix[3][1]
        _pdbx_struct_oper_list.matrix[3][2]
        _pdbx_struct_oper_list.matrix[3][3]
        _pdbx_struct_oper_list.vector[3]
        1 1 0 0 0 0 1 0 0 0 0 1 0
        2 1 0 0 10 0 1 0 0 0 0 1 0
        loop_
        _pdbx_struct_assembly_gen.assembly_id
        _pdbx_struct_assembly_gen.oper_expression
        _pdbx_struct_assembly_gen.asym_id_list
        1 '(1-2)' A1
        loop_
        _atom_site.group_PDB
        _atom_site.id
        _atom_site.type_symbol
        _atom_site.auth_atom_id
        _atom_site.auth_comp_id
        _atom_site.label_asym_id
        _atom_site.auth_asym_id
        _atom_site.auth_seq_id
        _atom_site.Cartn_x
        _atom_site.Cartn_y
        _atom_site.Cartn_z
        ATOM 1 C CA GLY A1 A 1 0 0 0
        """
        let structure = try MMCIFParser().parse(cif)
        let expanded = BiologicalAssemblyBuilder().expandedStructure(from: structure, assemblyID: "1")

        #expect(structure.biologicalAssemblies.count == 1)
        #expect(expanded?.atoms.count == 2)
        #expect(expanded?.atoms[1].position.x == 10)
        #expect(expanded?.chainIDs == ["A·1", "A·2"])
    }

    @Test func preservesAlternateLocations() throws {
        let cif = """
        data_alt
        loop_
        _atom_site.group_PDB
        _atom_site.id
        _atom_site.type_symbol
        _atom_site.auth_atom_id
        _atom_site.auth_comp_id
        _atom_site.auth_asym_id
        _atom_site.auth_seq_id
        _atom_site.label_alt_id
        _atom_site.Cartn_x
        _atom_site.Cartn_y
        _atom_site.Cartn_z
        ATOM 1 C CA GLY A 1 A 1 2 3
        ATOM 2 C CA GLY A 1 B 4 5 6
        """
        let structure = try MMCIFParser().parse(cif)
        let alternate = structure.applyingAlternateConformation("B")

        #expect(structure.atoms.count == 1)
        #expect(structure.alternateConformations.map(\.id) == ["A", "B"])
        #expect(structure.atoms[0].position == Vector3(x: 1, y: 2, z: 3))
        #expect(alternate.atoms[0].position == Vector3(x: 4, y: 5, z: 6))
    }
}
