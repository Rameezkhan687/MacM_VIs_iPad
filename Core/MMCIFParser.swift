import Foundation

public struct MMCIFParser: Sendable {
    private struct AssemblyGeneration {
        let assemblyID: String
        let expression: String
        let labelChainIDs: [String]
    }

    public init() {}

    public func parse(_ data: Data, name: String = "Structure") throws -> MolecularStructure {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw MolecularError.invalidMMCIF("The file is not readable text.")
        }
        return try parse(text, name: name)
    }

    public func parse(_ text: String, name: String = "Structure") throws -> MolecularStructure {
        let tokens = tokenize(text)
        var atoms: [Atom] = []
        var secondaryStructure: [SecondaryStructureSegment] = []
        var assemblyOperators: [String: MolecularTransform] = [:]
        var assemblyGenerations: [AssemblyGeneration] = []
        var chainAliases: [String: String] = [:]
        var atomIndexByIdentity: [String: Int] = [:]
        var alternatePositions: [String: [Int: Vector3]] = [:]
        var index = 0

        while index < tokens.count {
            guard tokens[index].lowercased() == "loop_" else {
                index += 1
                continue
            }
            index += 1
            var tags: [String] = []
            while index < tokens.count, tokens[index].hasPrefix("_") {
                tags.append(tokens[index].lowercased())
                index += 1
            }
            guard !tags.isEmpty else { continue }

            while index + tags.count <= tokens.count {
                let token = tokens[index].lowercased()
                if token == "loop_" || token == "stop_" || token.hasPrefix("data_") || token.hasPrefix("save_") || token.hasPrefix("_") {
                    break
                }
                let row = Array(tokens[index..<(index + tags.count)])
                process(
                    tags: tags,
                    row: row,
                    atoms: &atoms,
                    secondaryStructure: &secondaryStructure,
                    assemblyOperators: &assemblyOperators,
                    assemblyGenerations: &assemblyGenerations,
                    chainAliases: &chainAliases,
                    atomIndexByIdentity: &atomIndexByIdentity,
                    alternatePositions: &alternatePositions
                )
                index += tags.count
            }
        }

        guard !atoms.isEmpty else {
            throw MolecularError.invalidMMCIF("No atom_site coordinate rows were found.")
        }
        let bonds = BondInference.infer(atoms: atoms)
        let assemblies = buildAssemblies(
            generations: assemblyGenerations,
            operators: assemblyOperators,
            chainAliases: chainAliases
        )
        return MolecularStructure(
            name: name,
            atoms: atoms,
            bonds: bonds,
            secondaryStructure: secondaryStructure,
            biologicalAssemblies: assemblies,
            alternateConformations: alternatePositions.keys.sorted().map {
                AlternateConformation(id: $0, positions: alternatePositions[$0] ?? [:])
            }
        )
    }

    private func process(
        tags: [String],
        row: [String],
        atoms: inout [Atom],
        secondaryStructure: inout [SecondaryStructureSegment],
        assemblyOperators: inout [String: MolecularTransform],
        assemblyGenerations: inout [AssemblyGeneration],
        chainAliases: inout [String: String],
        atomIndexByIdentity: inout [String: Int],
        alternatePositions: inout [String: [Int: Vector3]]
    ) {
        guard let category = tags.first?.split(separator: ".").first else { return }
        switch category {
        case "_atom_site":
            appendAtom(
                tags: tags,
                row: row,
                to: &atoms,
                chainAliases: &chainAliases,
                atomIndexByIdentity: &atomIndexByIdentity,
                alternatePositions: &alternatePositions
            )
        case "_struct_conf":
            appendSecondaryStructure(kind: .helix, tags: tags, row: row, to: &secondaryStructure)
        case "_struct_sheet_range":
            appendSecondaryStructure(kind: .sheet, tags: tags, row: row, to: &secondaryStructure)
        case "_pdbx_struct_oper_list":
            appendAssemblyOperator(tags: tags, row: row, to: &assemblyOperators)
        case "_pdbx_struct_assembly_gen":
            appendAssemblyGeneration(tags: tags, row: row, to: &assemblyGenerations)
        default:
            break
        }
    }

    private func appendAtom(
        tags: [String],
        row: [String],
        to atoms: inout [Atom],
        chainAliases: inout [String: String],
        atomIndexByIdentity: inout [String: Int],
        alternatePositions: inout [String: [Int: Vector3]]
    ) {
        let alternateLocation = value(tags, row, ["_atom_site.label_alt_id", "_atom_site.auth_alt_id"])
        guard let x = float(tags, row, "_atom_site.cartn_x"),
              let y = float(tags, row, "_atom_site.cartn_y"),
              let z = float(tags, row, "_atom_site.cartn_z") else { return }

        let atomName = value(tags, row, ["_atom_site.auth_atom_id", "_atom_site.label_atom_id"]) ?? "?"
        let element = value(tags, row, ["_atom_site.type_symbol"])
            ?? ElementTable.inferredElement(atomName: atomName)
        let id = atoms.count
        let labelChain = value(tags, row, ["_atom_site.label_asym_id"]) ?? ""
        let authorChain = value(tags, row, ["_atom_site.auth_asym_id"]) ?? labelChain
        if !labelChain.isEmpty { chainAliases[labelChain] = authorChain }
        let residueNumber = integer(tags, row, ["_atom_site.auth_seq_id", "_atom_site.label_seq_id"]) ?? 0
        let identity = "\(authorChain)|\(residueNumber)|\(atomName)"
        let position = Vector3(x: x, y: y, z: z)
        if let atomID = atomIndexByIdentity[identity] {
            if let alternateLocation {
                alternatePositions[alternateLocation, default: [:]][atomID] = position
                if alternateLocation == "A" || alternateLocation == "1" { atoms[atomID].position = position }
            }
            return
        }
        atoms.append(Atom(
            id: id,
            serial: integer(tags, row, ["_atom_site.id"]) ?? id + 1,
            name: atomName,
            element: element,
            residueName: value(tags, row, ["_atom_site.auth_comp_id", "_atom_site.label_comp_id"]) ?? "UNK",
            residueNumber: residueNumber,
            chainID: authorChain,
            position: position,
            occupancy: float(tags, row, "_atom_site.occupancy") ?? 1,
            bFactor: float(tags, row, "_atom_site.b_iso_or_equiv") ?? 0,
            isHetero: value(tags, row, ["_atom_site.group_pdb"])?.uppercased() == "HETATM"
        ))
        atomIndexByIdentity[identity] = id
        if let alternateLocation {
            alternatePositions[alternateLocation, default: [:]][id] = position
        }
    }

    private func appendAssemblyOperator(
        tags: [String],
        row: [String],
        to operators: inout [String: MolecularTransform]
    ) {
        guard let id = value(tags, row, ["_pdbx_struct_oper_list.id"]) else { return }
        func component(_ rowIndex: Int, _ columnIndex: Int, fallback: Float) -> Float {
            float(tags, row, "_pdbx_struct_oper_list.matrix[\(rowIndex)][\(columnIndex)]") ?? fallback
        }
        func translation(_ index: Int) -> Float {
            float(tags, row, "_pdbx_struct_oper_list.vector[\(index)]") ?? 0
        }
        operators[id] = MolecularTransform(
            m11: component(1, 1, fallback: 1), m12: component(1, 2, fallback: 0), m13: component(1, 3, fallback: 0), tx: translation(1),
            m21: component(2, 1, fallback: 0), m22: component(2, 2, fallback: 1), m23: component(2, 3, fallback: 0), ty: translation(2),
            m31: component(3, 1, fallback: 0), m32: component(3, 2, fallback: 0), m33: component(3, 3, fallback: 1), tz: translation(3)
        )
    }

    private func appendAssemblyGeneration(
        tags: [String],
        row: [String],
        to generations: inout [AssemblyGeneration]
    ) {
        guard let assemblyID = value(tags, row, ["_pdbx_struct_assembly_gen.assembly_id"]),
              let expression = value(tags, row, ["_pdbx_struct_assembly_gen.oper_expression"]) else { return }
        let chains = value(tags, row, ["_pdbx_struct_assembly_gen.asym_id_list"])?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        generations.append(AssemblyGeneration(
            assemblyID: assemblyID,
            expression: expression,
            labelChainIDs: chains
        ))
    }

    private func buildAssemblies(
        generations: [AssemblyGeneration],
        operators: [String: MolecularTransform],
        chainAliases: [String: String]
    ) -> [BiologicalAssembly] {
        let grouped = Dictionary(grouping: generations, by: \.assemblyID)
        return grouped.keys.sorted().compactMap { assemblyID in
            var instances: [AssemblyInstance] = []
            for generation in grouped[assemblyID] ?? [] {
                let chains = generation.labelChainIDs.map { chainAliases[$0] ?? $0 }
                for operation in expandedOperations(generation.expression, operators: operators) {
                    instances.append(AssemblyInstance(
                        operatorID: operation.id,
                        chainIDs: chains,
                        transform: operation.transform
                    ))
                }
            }
            guard !instances.isEmpty else { return nil }
            return BiologicalAssembly(id: assemblyID, instances: instances)
        }
    }

    private func expandedOperations(
        _ expression: String,
        operators: [String: MolecularTransform]
    ) -> [(id: String, transform: MolecularTransform)] {
        let groupPattern = try? NSRegularExpression(pattern: #"\(([^()]*)\)"#)
        let range = NSRange(expression.startIndex..<expression.endIndex, in: expression)
        let captures = groupPattern?.matches(in: expression, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: expression) else { return nil }
            return String(expression[valueRange])
        } ?? []
        let groups = captures.isEmpty ? [expression] : captures
        var combinations: [(id: String, transform: MolecularTransform)] = [("", .identity)]
        for group in groups {
            let ids = operationIDs(group)
            var next: [(id: String, transform: MolecularTransform)] = []
            for combination in combinations {
                for id in ids {
                    guard let transform = operators[id] else { continue }
                    next.append((
                        combination.id.isEmpty ? id : "\(combination.id)×\(id)",
                        combination.transform.followed(by: transform)
                    ))
                }
            }
            combinations = next
        }
        return combinations
    }

    private func operationIDs(_ expression: String) -> [String] {
        expression.split(separator: ",").flatMap { component -> [String] in
            let value = component.trimmingCharacters(in: .whitespaces)
            let limits = value.split(separator: "-", maxSplits: 1).compactMap { Int($0) }
            if limits.count == 2, limits[0] <= limits[1], limits[1] - limits[0] <= 500 {
                return (limits[0]...limits[1]).map(String.init)
            }
            return value.isEmpty ? [] : [value]
        }
    }

    private func appendSecondaryStructure(
        kind: SecondaryStructureKind,
        tags: [String],
        row: [String],
        to segments: inout [SecondaryStructureSegment]
    ) {
        if kind == .helix,
           let type = value(tags, row, ["_struct_conf.conf_type_id"]),
           !type.uppercased().hasPrefix("HELX") { return }

        let prefix = kind == .helix ? "_struct_conf" : "_struct_sheet_range"
        guard let chain = value(tags, row, ["\(prefix).beg_auth_asym_id", "\(prefix).beg_label_asym_id"]),
              let start = integer(tags, row, ["\(prefix).beg_auth_seq_id", "\(prefix).beg_label_seq_id"]),
              let end = integer(tags, row, ["\(prefix).end_auth_seq_id", "\(prefix).end_label_seq_id"]) else { return }
        let endingChain = value(tags, row, ["\(prefix).end_auth_asym_id", "\(prefix).end_label_asym_id"])
        guard endingChain == nil || endingChain?.caseInsensitiveCompare(chain) == .orderedSame else { return }
        let segment = SecondaryStructureSegment(kind: kind, chainID: chain, startResidue: start, endResidue: end)
        if !segments.contains(segment) { segments.append(segment) }
    }

    private func value(_ tags: [String], _ row: [String], _ candidates: [String]) -> String? {
        for candidate in candidates {
            guard let index = tags.firstIndex(of: candidate), row.indices.contains(index) else { continue }
            let value = row[index]
            if value != ".", value != "?", !value.isEmpty { return value }
        }
        return nil
    }

    private func integer(_ tags: [String], _ row: [String], _ candidates: [String]) -> Int? {
        guard let value = value(tags, row, candidates) else { return nil }
        if let integer = Int(value) { return integer }
        if let float = Float(value), float.isFinite { return Int(float) }
        return nil
    }

    private func float(_ tags: [String], _ row: [String], _ candidate: String) -> Float? {
        guard let value = value(tags, row, [candidate]) else { return nil }
        let uncertaintyFree = value.split(separator: "(", maxSplits: 1).first.map(String.init) ?? value
        return Float(uncertaintyFree)
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let characters = Array(text)
        var index = 0
        var atLineStart = true

        while index < characters.count {
            let character = characters[index]
            if character == "\n" || character == "\r" {
                atLineStart = true
                index += 1
                continue
            }
            if character.isWhitespace {
                index += 1
                continue
            }
            if character == "#" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if character == ";", atLineStart {
                index += 1
                let start = index
                while index < characters.count {
                    if characters[index] == "\n", index + 1 < characters.count, characters[index + 1] == ";" {
                        tokens.append(String(characters[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                        index += 2
                        while index < characters.count, characters[index] != "\n" { index += 1 }
                        break
                    }
                    index += 1
                }
                atLineStart = true
                continue
            }

            atLineStart = false
            if character == "'" || character == "\"" {
                let quote = character
                index += 1
                let start = index
                while index < characters.count, characters[index] != quote { index += 1 }
                tokens.append(String(characters[start..<min(index, characters.count)]))
                if index < characters.count { index += 1 }
                continue
            }

            let start = index
            while index < characters.count, !characters[index].isWhitespace, characters[index] != "#" { index += 1 }
            tokens.append(String(characters[start..<index]))
        }
        return tokens
    }
}
