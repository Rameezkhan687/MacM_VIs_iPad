import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var structure: MolecularStructure?
    @Published var volume: VolumeMap?
    @Published var settings = RenderSettings()
    @Published var selectedAtomIDs: [Int] = []
    @Published var isLoading = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var commandText = ""
    @Published var commandHistory: [String] = []
    @Published var showInspector = true
    @Published var sceneRevision = 0

    init(loadSample: Bool = true) {
        if loadSample {
            structure = SampleData.miniProtein
            statusMessage = "Welcome protein — \(structure?.atoms.count ?? 0) atoms"
        }
    }

    var selectedAtoms: [Atom] {
        guard let structure else { return [] }
        return selectedAtomIDs.compactMap { id in structure.atoms.first { $0.id == id } }
    }

    var measuredDistance: Float? {
        guard selectedAtoms.count == 2 else { return nil }
        return (selectedAtoms[0].position - selectedAtoms[1].position).length
    }

    func selectAtom(_ id: Int, additive: Bool) {
        if additive {
            if selectedAtomIDs.contains(id) {
                selectedAtomIDs.removeAll { $0 == id }
            } else {
                selectedAtomIDs.append(id)
                if selectedAtomIDs.count > 2 { selectedAtomIDs.removeFirst() }
            }
        } else {
            selectedAtomIDs = [id]
        }
        sceneRevision += 1
    }

    func clearSelection() {
        selectedAtomIDs = []
        sceneRevision += 1
    }

    func openFiles(_ urls: [URL]) {
        Task {
            for url in urls { await openFile(url) }
        }
    }

    func openFile(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let ext = url.pathExtension.lowercased()
            if ["pdb", "ent"].contains(ext) {
                structure = try PDBParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                selectedAtomIDs = []
                statusMessage = "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ["mrc", "map", "ccp4"].contains(ext) {
                volume = try MRCParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                statusMessage = "Opened \(url.lastPathComponent) — \(volumeDescription)"
            } else {
                throw MolecularError.unsupportedFile(url.pathExtension)
            }
            sceneRevision += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPDB(id rawID: String) async {
        let pdbID = rawID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard pdbID.count == 4, pdbID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            errorMessage = "Enter a four-character PDB ID, for example 1CRN."
            return
        }
        guard let url = URL(string: "https://files.rcsb.org/download/\(pdbID).pdb") else { return }
        isLoading = true
        statusMessage = "Downloading \(pdbID)…"
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MolecularError.network("RCSB did not return PDB \(pdbID).")
            }
            structure = try PDBParser().parse(data, name: pdbID)
            selectedAtomIDs = []
            statusMessage = "Opened \(pdbID) — \(structure?.atoms.count ?? 0) atoms"
            sceneRevision += 1
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Download failed"
        }
    }

    func closeStructure() {
        structure = nil
        selectedAtomIDs = []
        statusMessage = "Structure closed"
        sceneRevision += 1
    }

    func closeMap() {
        volume = nil
        statusMessage = "Map closed"
        sceneRevision += 1
    }

    func executeCommand() {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        commandHistory.append(command)
        commandText = ""
        execute(command)
    }

    func execute(_ command: String) {
        let parts = command.lowercased().split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        switch verb {
        case "open" where parts.count == 2, "fetch" where parts.count == 2:
            Task { await fetchPDB(id: parts[1]) }
        case "style" where parts.count >= 2:
            let value = parts.dropFirst().joined(separator: "")
            let mapping: [String: MolecularRepresentation] = [
                "ball": .ballAndStick, "ball&stick": .ballAndStick, "ballandstick": .ballAndStick,
                "spacefill": .spacefill, "spheres": .spacefill,
                "sticks": .sticks, "backbone": .backbone
            ]
            if let representation = mapping[value] {
                settings.representation = representation
                sceneRevision += 1
                statusMessage = "Style: \(representation.rawValue)"
            } else { errorMessage = "Styles: ball, spacefill, sticks, backbone" }
        case "color" where parts.count == 2:
            let mapping: [String: AtomColorMode] = [
                "element": .element, "chain": .chain, "residue": .residue,
                "mono": .monochrome, "monochrome": .monochrome
            ]
            if let mode = mapping[parts[1]] {
                settings.colorMode = mode
                sceneRevision += 1
                statusMessage = "Color: \(mode.rawValue)"
            } else { errorMessage = "Colors: element, chain, residue, mono" }
        case "surface" where parts.count == 3 && parts[1] == "level":
            if let value = Float(parts[2]) {
                settings.mapThreshold = value
                settings.showMap = true
                sceneRevision += 1
            } else { errorMessage = "Usage: surface level 0.8" }
        case "hide" where parts.count == 2:
            setVisibility(parts[1], visible: false)
        case "show" where parts.count == 2:
            setVisibility(parts[1], visible: true)
        case "clear", "select" where parts.dropFirst().first == "clear":
            clearSelection()
        case "help":
            statusMessage = "open 1crn · style ball|spacefill|sticks|backbone · color element|chain|residue|mono · surface level N · show/hide atoms|map"
        default:
            errorMessage = "Unknown command. Type help for supported commands."
        }
    }

    private func setVisibility(_ target: String, visible: Bool) {
        if ["atoms", "structure", "model"].contains(target) {
            settings.showAtoms = visible
        } else if ["map", "surface", "volume"].contains(target) {
            settings.showMap = visible
        } else {
            errorMessage = "Choose atoms or map."
            return
        }
        sceneRevision += 1
    }

    private var volumeDescription: String {
        guard let d = volume?.dimensions else { return "0 voxels" }
        return "\(d.x) × \(d.y) × \(d.z) voxels"
    }
}
