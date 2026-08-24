import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum CommandInputMode: String, CaseIterable, Identifiable {
    case copilot = "Copilot"
    case terminal = "Terminal"

    var id: Self { self }
}

enum WorkspaceTaskState: String {
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
}

struct WorkspaceTaskItem: Identifiable {
    let id: UUID
    let title: String
    var state: WorkspaceTaskState
    var detail: String
    let startedAt: Date
}

@MainActor
final class WorkspaceStore: ObservableObject {
    private struct Snapshot {
        let structure: MolecularStructure?
        let asymmetricUnit: MolecularStructure?
        let volume: VolumeMap?
        let settings: RenderSettings
        let selection: [Int]
    }
    @Published var structure: MolecularStructure?
    @Published var asymmetricUnit: MolecularStructure?
    @Published var activeAlternateLocation: String?
    @Published var trajectory: MolecularTrajectory?
    @Published var trajectoryFrameIndex = 0
    @Published var isTrajectoryPlaying = false
    @Published var volume: VolumeMap?
    @Published var dicomMetadata: DICOMMetadata?
    @Published var referenceVolume: VolumeMap?
    @Published var volumeSegments: [VolumeSegment] = []
    @Published var referenceStructure: MolecularStructure?
    @Published var interactions: [MolecularInteraction] = []
    @Published var cavities: [MolecularCavity] = []
    @Published var analysisReport: String?
    @Published var settings = RenderSettings()
    @Published var selectedAtomIDs: [Int] = []
    @Published var isLoading = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var commandText = ""
    @Published var commandHistory: [String] = []
    @Published var commandInputMode: CommandInputMode = .copilot
    @Published var copilotPlan: CopilotPlan?
    @Published var showInspector = true
    @Published var isPresentationMode = false
    @Published var sceneRevision = 0
    @Published var aliases: [String: String] = [:]
    @Published var savedScenes: [String: RenderSettings] = [:]
    @Published var installedPlugins: [MoleculePadPluginManifest] = []
    @Published var quickCommands: [MoleculePadQuickCommand] = []
    @Published var customPseudobonds: [CustomPseudobond] = []
    @Published var canvasStrokes: [CanvasStroke] = []
    @Published var isDrawingAnnotations = false
    @Published var taskItems: [WorkspaceTaskItem] = []
    @Published var copilotBackendURLString: String
    @Published var computeProviderURLString: String
    @Published var copilotAccessToken: String
    @Published var computeProviderAccessToken: String
    private var trajectoryPlaybackTask: Task<Void, Never>?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(loadSample: Bool = true) {
        copilotBackendURLString = UserDefaults.standard.string(forKey: "MoleculePad.CopilotBackendURL") ?? ""
        computeProviderURLString = UserDefaults.standard.string(forKey: "MoleculePad.ComputeProviderURL") ?? ""
        copilotAccessToken = KeychainStore.value(for: "copilot-access-token")
        computeProviderAccessToken = KeychainStore.value(for: "compute-access-token")
        if loadSample {
            structure = SampleData.miniProtein
            asymmetricUnit = structure
            statusMessage = "Welcome protein — \(structure?.atoms.count ?? 0) atoms"
        }
    }

    var selectedAtoms: [Atom] {
        guard let structure else { return [] }
        return selectedAtomIDs.compactMap { id in
            if structure.atoms.indices.contains(id), structure.atoms[id].id == id {
                return structure.atoms[id]
            }
            return structure.atoms.first { $0.id == id }
        }
    }

    var measuredDistance: Float? {
        guard selectedAtoms.count == 2 else { return nil }
        return MolecularMeasurements.distance(selectedAtoms[0].position, selectedAtoms[1].position)
    }

    var measuredAngle: Float? {
        guard selectedAtoms.count == 3 else { return nil }
        return MolecularMeasurements.angle(
            selectedAtoms[0].position,
            selectedAtoms[1].position,
            selectedAtoms[2].position
        )
    }

    var measuredTorsion: Float? {
        guard selectedAtoms.count == 4 else { return nil }
        return MolecularMeasurements.torsion(
            selectedAtoms[0].position,
            selectedAtoms[1].position,
            selectedAtoms[2].position,
            selectedAtoms[3].position
        )
    }

    func selectAtom(_ id: Int, additive: Bool) {
        if additive {
            if selectedAtomIDs.count > 4 {
                selectedAtomIDs = [id]
                sceneRevision += 1
                return
            }
            if selectedAtomIDs.contains(id) {
                selectedAtomIDs.removeAll { $0 == id }
            } else {
                selectedAtomIDs.append(id)
                if selectedAtomIDs.count > 4 { selectedAtomIDs.removeFirst() }
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
        let dicomURLs = urls.filter { ["dcm", "dicom"].contains($0.pathExtension.lowercased()) }
        if dicomURLs.count == urls.count, dicomURLs.count > 1 {
            Task { await openDICOMSeries(dicomURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }) }
            return
        }
        Task {
            for url in urls { await openFile(url) }
        }
    }

    func runBatch(_ urls: [URL], script: String) async {
        guard !urls.isEmpty else { return }
        errorMessage = nil
        let statements = MoleculePadPluginLoader.statements(in: script)
        guard !statements.isEmpty, statements.allSatisfy(CopilotInterpreter().isAllowedCommand) else {
            errorMessage = "Batch scripts may only contain allow-listed MoleculePad commands."
            return
        }
        let taskID = beginTask("Batch processing", detail: "0 of \(urls.count) files")
        var completed: [String] = []
        for (index, url) in urls.enumerated() {
            errorMessage = nil
            await openFile(url)
            guard errorMessage == nil else {
                let message = errorMessage ?? "Unknown error"
                finishTask(taskID, state: .failed, detail: "\(url.lastPathComponent): \(message)")
                return
            }
            executeScript(script)
            guard errorMessage == nil else {
                let message = errorMessage ?? "Unknown error"
                finishTask(taskID, state: .failed, detail: "\(url.lastPathComponent): \(message)")
                return
            }
            completed.append(url.lastPathComponent)
            if let itemIndex = taskItems.firstIndex(where: { $0.id == taskID }) {
                taskItems[itemIndex].detail = "\(index + 1) of \(urls.count) files"
            }
        }
        analysisReport = "Batch complete · \(completed.count) files\n" + completed.joined(separator: "\n")
        finishTask(taskID, state: .completed, detail: "\(completed.count) files processed")
        statusMessage = "Batch processing complete"
    }

    func openDICOMSeries(_ urls: [URL]) async {
        isLoading = true
        statusMessage = "Reading \(urls.count) DICOM slices…"
        defer { isLoading = false }
        do {
            var files: [Data] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                files.append(try Data(contentsOf: url, options: .mappedIfSafe))
            }
            dicomMetadata = files.first.flatMap { try? DICOMParser().metadata($0) }
            volume = try DICOMParser().parseSeries(files, name: urls.first?.deletingLastPathComponent().lastPathComponent ?? "DICOM Series")
            settings.mapThreshold = volume?.suggestedContour ?? 0
            settings.volumeDisplayStyle = .slices
            settings.showMap = true
            statusMessage = "Opened DICOM series — \(volumeDescription)"
            sceneRevision += 1
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "DICOM series import failed"
        }
    }

    func openFile(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            var data = try Data(contentsOf: url, options: .mappedIfSafe)
            let ext = url.pathExtension.lowercased()
            if !["dcm", "dicom"].contains(ext) { dicomMetadata = nil }
            if ["pdb", "ent", "cif", "mmcif", "sdf", "mol", "mol2", "xyz"].contains(ext) {
                interactions = []
                cavities = []
                analysisReport = nil
            }
            if ext == "moleculepad" {
                try restoreSession(SessionCodec().decode(data))
                statusMessage = "Restored \(url.lastPathComponent)"
            } else if ext == "molplugin" {
                let plugin = try MoleculePadPluginLoader().decodeAndValidate(data)
                installedPlugins.removeAll { $0.id == plugin.id }
                installedPlugins.append(plugin)
                installedPlugins.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                statusMessage = "Installed \(plugin.name) \(plugin.version)"
            } else if ["molcmd", "cxc"].contains(ext) {
                guard let script = String(data: data, encoding: .utf8) else {
                    throw MolecularError.invalidStructure("The command script is not UTF-8 text.")
                }
                executeScript(script)
                statusMessage = "Ran \(url.lastPathComponent)"
            } else if ["pdb", "ent"].contains(ext) {
                let loaded = try PDBParser().parseTrajectory(
                    data,
                    name: url.deletingPathExtension().lastPathComponent
                )
                trajectory = loaded.frameCount > 1 ? loaded : nil
                trajectoryFrameIndex = 0
                structure = loaded.frames.first
                asymmetricUnit = structure
                activeAlternateLocation = nil
                selectedAtomIDs = []
                statusMessage = loaded.frameCount > 1
                    ? "Opened \(url.lastPathComponent) — \(loaded.frameCount) frames"
                    : "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ["cif", "mmcif"].contains(ext) {
                structure = try MMCIFParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                asymmetricUnit = structure
                activeAlternateLocation = nil
                resetTrajectory()
                selectedAtomIDs = []
                statusMessage = "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ["sdf", "mol"].contains(ext) {
                structure = try SDFParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                asymmetricUnit = structure
                activeAlternateLocation = nil
                resetTrajectory()
                selectedAtomIDs = []
                statusMessage = "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ext == "mol2" {
                structure = try MOL2Parser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                asymmetricUnit = structure
                activeAlternateLocation = nil
                resetTrajectory()
                selectedAtomIDs = []
                statusMessage = "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ext == "xyz" {
                let loaded = try XYZParser().parseTrajectory(data, name: url.deletingPathExtension().lastPathComponent)
                trajectory = loaded.frameCount > 1 ? loaded : nil
                trajectoryFrameIndex = 0
                structure = loaded.frames.first
                asymmetricUnit = structure
                activeAlternateLocation = nil
                selectedAtomIDs = []
                statusMessage = loaded.frameCount > 1
                    ? "Opened \(url.lastPathComponent) — \(loaded.frameCount) XYZ frames"
                    : "Opened \(url.lastPathComponent) — \(structure?.atoms.count ?? 0) atoms"
            } else if ext == "dcd" {
                guard let topology = structure else {
                    throw MolecularError.invalidStructure("Open the matching PDB or mmCIF topology before the DCD file.")
                }
                let loaded = try DCDParser().parse(data, topology: topology, name: url.deletingPathExtension().lastPathComponent)
                trajectory = loaded
                trajectoryFrameIndex = 0
                structure = loaded.frames.first
                selectedAtomIDs = []
                statusMessage = "Opened \(url.lastPathComponent) — \(loaded.frameCount) DCD frames"
            } else if ["mrc", "map", "ccp4"].contains(ext) {
                volume = try MRCParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
                statusMessage = "Opened \(url.lastPathComponent) — \(volumeDescription)"
            } else if ext == "nii" {
                volume = try NIfTIParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
                statusMessage = "Opened NIfTI \(url.lastPathComponent) — \(volumeDescription)"
            } else if ext == "nrrd" {
                volume = try NRRDParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
                statusMessage = "Opened NRRD \(url.lastPathComponent) — \(volumeDescription)"
            } else if ["dcm", "dicom"].contains(ext) {
                dicomMetadata = try DICOMParser().metadata(data)
                volume = try DICOMParser().parse(data, name: url.deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
                statusMessage = "Opened DICOM \(url.lastPathComponent) — \(volumeDescription)"
            } else if ext == "gz", url.lastPathComponent.lowercased().hasSuffix(".nii.gz") {
                statusMessage = "Decompressing \(url.lastPathComponent)…"
                data = try GzipDecompressor().decompress(data)
                volume = try NIfTIParser().parse(data, name: url.deletingPathExtension().deletingPathExtension().lastPathComponent)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
                statusMessage = "Opened NIfTI \(url.lastPathComponent) — \(volumeDescription)"
            } else if ext == "gz", isCompressedMap(url) {
                statusMessage = "Decompressing \(url.lastPathComponent)…"
                data = try GzipDecompressor().decompress(data)
                let mapName = url.deletingPathExtension().deletingPathExtension().lastPathComponent
                volume = try MRCParser().parse(data, name: mapName)
                settings.mapThreshold = volume?.suggestedContour ?? 0
                settings.showMap = true
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
        guard let url = URL(string: "https://files.rcsb.org/download/\(pdbID).cif") else { return }
        let taskID = beginTask("RCSB PDB \(pdbID)", detail: "Downloading coordinates")
        isLoading = true
        statusMessage = "Downloading \(pdbID)…"
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MolecularError.network("RCSB did not return PDB \(pdbID).")
            }
            structure = try MMCIFParser().parse(data, name: pdbID)
            asymmetricUnit = structure
            activeAlternateLocation = nil
            resetTrajectory()
            selectedAtomIDs = []
            statusMessage = "Opened \(pdbID) — \(structure?.atoms.count ?? 0) atoms"
            finishTask(taskID, state: .completed, detail: "\(structure?.atoms.count ?? 0) atoms")
            sceneRevision += 1
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "Download failed"
        }
    }

    func fetchEMDB(id rawID: String) async {
        let digits = normalizedEMDBID(rawID)
        guard (4...6).contains(digits.count), digits.allSatisfy(\.isNumber) else {
            errorMessage = "Enter an EMDB ID such as EMD-1001 or 1001."
            return
        }
        guard let url = URL(
            string: "https://ftp.ebi.ac.uk/pub/databases/emdb/structures/EMD-\(digits)/map/emd_\(digits).map.gz"
        ) else { return }

        let taskID = beginTask("EMDB EMD-\(digits)", detail: "Downloading density map")
        isLoading = true
        statusMessage = "Downloading EMD-\(digits)…"
        defer { isLoading = false }
        do {
            let request = URLRequest(url: url, timeoutInterval: 300)
            let (compressedData, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MolecularError.network("EMDB did not return EMD-\(digits).")
            }

            statusMessage = "Decompressing and reading EMD-\(digits)…"
            let loadedVolume = try await Task.detached(priority: .userInitiated) {
                let mapData = try GzipDecompressor().decompress(compressedData)
                return try MRCParser().parse(mapData, name: "EMD-\(digits)")
            }.value
            volume = loadedVolume
            settings.mapThreshold = volume?.suggestedContour ?? 0
            settings.showMap = true
            statusMessage = "Opened EMD-\(digits) — \(volumeDescription)"
            finishTask(taskID, state: .completed, detail: volumeDescription)
            sceneRevision += 1
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "EMDB download failed"
        }
    }

    func fetchAlphaFold(id rawID: String) async {
        let accession = rawID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard accession.range(of: #"^[A-Z0-9]{6,12}(?:-\d+)?$"#, options: .regularExpression) != nil,
              let metadataURL = URL(string: "https://alphafold.ebi.ac.uk/api/prediction/\(accession)") else {
            errorMessage = "Enter a UniProt accession such as P07550."
            return
        }
        let taskID = beginTask("AlphaFold \(accession)", detail: "Looking up prediction")
        isLoading = true
        statusMessage = "Looking up AlphaFold \(accession)…"
        defer { isLoading = false }
        do {
            let (metadata, response) = try await URLSession.shared.data(from: metadataURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let records = try JSONSerialization.jsonObject(with: metadata) as? [[String: Any]],
                  let record = records.first else {
                throw MolecularError.network("AlphaFold DB has no prediction for \(accession).")
            }
            let fields = ["cifUrl", "cif_url", "modelCifUrl", "model_cif_url", "pdbUrl", "pdb_url"]
            guard let urlString = fields.compactMap({ record[$0] as? String }).first,
                  let modelURL = URL(string: urlString) else {
                throw MolecularError.network("AlphaFold DB did not provide a coordinate-file URL.")
            }
            statusMessage = "Downloading AlphaFold \(accession)…"
            let (modelData, modelResponse) = try await URLSession.shared.data(from: modelURL)
            guard (modelResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw MolecularError.network("The AlphaFold coordinate download failed.")
            }
            if modelURL.pathExtension.lowercased() == "pdb" {
                structure = try PDBParser().parse(modelData, name: "AlphaFold \(accession)")
            } else {
                structure = try MMCIFParser().parse(modelData, name: "AlphaFold \(accession)")
            }
            asymmetricUnit = structure
            activeAlternateLocation = nil
            resetTrajectory()
            interactions = []
            cavities = []
            selectedAtomIDs = []
            statusMessage = "Opened AlphaFold \(accession) — \(structure?.atoms.count ?? 0) atoms"
            finishTask(taskID, state: .completed, detail: "\(structure?.atoms.count ?? 0) atoms")
            sceneRevision += 1
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "AlphaFold download failed"
        }
    }

    func runProteinBLAST() async {
        guard let structure,
              let sequence = MolecularAnalysisEngine().sequences(in: structure).first?.codes,
              sequence.count >= 10 else {
            errorMessage = "Open a protein with a sequence of at least 10 residues."
            return
        }
        let taskID = beginTask("Protein BLAST", detail: "Submitting sequence")
        isLoading = true
        statusMessage = "Submitting protein BLAST…"
        defer { isLoading = false }
        do {
            let submitText = try await blastRequest(parameters: [
                "CMD": "Put", "PROGRAM": "blastp", "DATABASE": "swissprot",
                "QUERY": sequence, "HITLIST_SIZE": "25"
            ])
            guard let rid = firstRegexCapture(#"RID\s*=\s*([A-Z0-9-]+)"#, in: submitText) else {
                throw MolecularError.network("NCBI BLAST did not return a request ID.")
            }
            for attempt in 1...18 {
                try await Task.sleep(for: .seconds(attempt == 1 ? 5 : 10))
                statusMessage = "Waiting for BLAST results…"
                let status = try await blastRequest(parameters: ["CMD": "Get", "RID": rid, "FORMAT_OBJECT": "SearchInfo"])
                if status.contains("Status=FAILED") || status.contains("Status=UNKNOWN") {
                    throw MolecularError.network("NCBI BLAST could not complete this search.")
                }
                if status.contains("Status=READY"), !status.contains("ThereAreHits=no") {
                    let result = try await blastRequest(parameters: [
                        "CMD": "Get", "RID": rid, "FORMAT_TYPE": "Text",
                        "DESCRIPTIONS": "25", "ALIGNMENTS": "10"
                    ])
                    analysisReport = String(result.prefix(12_000))
                    statusMessage = "BLAST results ready"
                    finishTask(taskID, state: .completed, detail: "Results ready")
                    return
                }
            }
            throw MolecularError.network("The BLAST search timed out; try again later.")
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "BLAST search failed"
        }
    }

    func runRCSBStructureSimilarity(pdbID requestedID: String? = nil) async {
        let candidate = requestedID ?? structure?.name ?? ""
        guard let pdbID = firstRegexCapture(#"(?i)\b([0-9][a-z0-9]{3})\b"#, in: candidate)?.uppercased() else {
            errorMessage = "3D similarity search needs a deposited PDB model. Open one from RCSB or use: similar 1CRN"
            return
        }
        let taskID = beginTask("RCSB 3D similarity", detail: "Searching from \(pdbID)")
        isLoading = true
        statusMessage = "Searching RCSB for structures similar to \(pdbID)…"
        defer { isLoading = false }
        do {
            let hits = try await RCSBStructureSearchClient().search(pdbID: pdbID)
            let filtered = hits.filter { !$0.identifier.uppercased().hasPrefix("\(pdbID)-") }
            analysisReport = filtered.isEmpty
                ? "RCSB 3D similarity · no matches returned for \(pdbID)"
                : "RCSB 3D similarity to \(pdbID)\n" + filtered.prefix(25).map { hit in
                    hit.score.map { String(format: "%@ · score %.4f", hit.identifier, $0) } ?? hit.identifier
                }.joined(separator: "\n")
            finishTask(taskID, state: .completed, detail: "\(filtered.count) match(es)")
            statusMessage = "RCSB 3D similarity results ready"
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "RCSB structure search failed"
        }
    }

    func runMolecularCompute(_ operation: MolecularComputeOperation) async {
        let endpointText = computeProviderURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: endpointText), !endpointText.isEmpty else {
            errorMessage = "Add your HTTPS molecular compute endpoint in Automation & Plug-ins first."
            return
        }
        guard let structure else { errorMessage = "Open a protein structure first."; return }
        let sequence = MolecularAnalysisEngine().sequences(in: structure).first?.codes
        if operation != .foldseek, (sequence?.count ?? 0) < 10 {
            errorMessage = "Prediction requires a protein sequence of at least 10 residues."
            return
        }
        let pdbText = operation == .foldseek ? String(data: StructureFileWriter().pdb(structure), encoding: .utf8) : nil
        let request = MolecularComputeRequest(
            operation: operation,
            sequence: operation == .foldseek ? nil : sequence,
            pdb: pdbText
        )
        let taskID = beginTask(operation.rawValue.uppercased(), detail: "Running on compute provider")
        isLoading = true
        statusMessage = "Running \(operation.rawValue)…"
        defer { isLoading = false }
        do {
            let result = try await MolecularComputeClient().run(
                endpoint: endpoint,
                request: request,
                bearerToken: computeProviderAccessToken
            )
            analysisReport = result.resultText.map { "\(result.summary)\n\n\($0)" } ?? result.summary
            if let location = result.structureURL, let url = URL(string: location) {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 200_000_000 else {
                    throw MolecularError.network("The provider’s predicted structure could not be downloaded.")
                }
                let name = "\(operation.rawValue.uppercased()) prediction"
                if ["pdb", "ent"].contains(url.pathExtension.lowercased()) {
                    self.structure = try PDBParser().parse(data, name: name)
                } else {
                    self.structure = try MMCIFParser().parse(data, name: name)
                }
                asymmetricUnit = self.structure
                selectedAtomIDs = []
                resetTrajectory()
                sceneRevision += 1
            }
            finishTask(taskID, state: .completed, detail: result.summary)
            statusMessage = result.summary
        } catch {
            finishTask(taskID, state: .failed, detail: error.localizedDescription)
            errorMessage = error.localizedDescription
            statusMessage = "\(operation.rawValue) failed"
        }
    }

    private func blastRequest(parameters: [String: String]) async throws -> String {
        guard let url = URL(string: "https://blast.ncbi.nlm.nih.gov/Blast.cgi") else { throw MolecularError.network("Invalid BLAST URL.") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(formEncoded(key))=\(formEncoded(value))"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            throw MolecularError.network("NCBI BLAST returned an invalid response.")
        }
        return text
    }

    private func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    func closeStructure() {
        structure = nil
        asymmetricUnit = nil
        activeAlternateLocation = nil
        referenceStructure = nil
        interactions = []
        customPseudobonds = []
        cavities = []
        analysisReport = nil
        resetTrajectory()
        selectedAtomIDs = []
        statusMessage = "Structure closed"
        sceneRevision += 1
    }

    func closeMap() {
        volume = nil
        dicomMetadata = nil
        volumeSegments = []
        statusMessage = "Map closed"
        sceneRevision += 1
    }

    func setTrajectoryFrame(_ index: Int) {
        guard let trajectory, !trajectory.frames.isEmpty else { return }
        let bounded = min(max(0, index), trajectory.frames.count - 1)
        trajectoryFrameIndex = bounded
        structure = trajectory.frames[bounded]
        selectedAtomIDs = selectedAtomIDs.filter { id in structure?.atoms.contains(where: { $0.id == id }) == true }
        statusMessage = "Frame \(bounded + 1) of \(trajectory.frames.count)"
        sceneRevision += 1
    }

    func stepTrajectory(_ offset: Int = 1) {
        guard let trajectory, !trajectory.frames.isEmpty else { return }
        let next = (trajectoryFrameIndex + offset + trajectory.frames.count) % trajectory.frames.count
        setTrajectoryFrame(next)
    }

    func setTrajectoryPlayback(_ playing: Bool) {
        trajectoryPlaybackTask?.cancel()
        trajectoryPlaybackTask = nil
        isTrajectoryPlaying = playing && (trajectory?.frameCount ?? 0) > 1
        guard isTrajectoryPlaying else { return }
        trajectoryPlaybackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled, self.isTrajectoryPlaying else { return }
                self.stepTrajectory()
            }
        }
    }

    func showBiologicalAssembly(_ id: String) {
        guard let source = asymmetricUnit,
              let expanded = BiologicalAssemblyBuilder().expandedStructure(from: source, assemblyID: id) else {
            errorMessage = "Assembly \(id) is not available for this structure."
            return
        }
        setTrajectoryPlayback(false)
        activeAlternateLocation = nil
        structure = expanded
        selectedAtomIDs = []
        statusMessage = "Showing biological assembly \(id) — \(expanded.atoms.count) atoms"
        sceneRevision += 1
    }

    func showAsymmetricUnit() {
        guard let asymmetricUnit else { return }
        structure = asymmetricUnit.applyingAlternateConformation(activeAlternateLocation)
        selectedAtomIDs = []
        statusMessage = "Showing asymmetric unit"
        sceneRevision += 1
    }

    func showAlternateLocation(_ identifier: String?) {
        guard let asymmetricUnit else { return }
        if let identifier,
           !asymmetricUnit.alternateConformations.contains(where: { $0.id.caseInsensitiveCompare(identifier) == .orderedSame }) {
            errorMessage = "Alternate location \(identifier) is not available."
            return
        }
        setTrajectoryPlayback(false)
        activeAlternateLocation = identifier
        structure = asymmetricUnit.applyingAlternateConformation(identifier)
        selectedAtomIDs = []
        statusMessage = identifier.map { "Showing alternate location \($0)" } ?? "Showing primary coordinates"
        sceneRevision += 1
    }

    func calculateInteractions(_ kind: MolecularInteractionKind) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let engine = MolecularAnalysisEngine()
        switch kind {
        case .hydrogenBond: interactions = engine.hydrogenBonds(in: structure)
        case .contact: interactions = engine.contacts(in: structure)
        case .clash: interactions = engine.clashes(in: structure)
        }
        analysisReport = "\(interactions.count) \(kind.rawValue.lowercased())\(interactions.count == 1 ? "" : "s")"
        statusMessage = analysisReport ?? "Analysis complete"
        sceneRevision += 1
    }

    func clearInteractions() {
        interactions = []
        cavities = []
        statusMessage = "Interaction pseudobonds cleared"
        sceneRevision += 1
    }

    func reportGeometry(_ quantity: String) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let atoms = selectedAtoms.isEmpty ? structure.atoms : selectedAtoms
        let engine = MolecularAnalysisEngine()
        switch quantity {
        case "area", "surface":
            analysisReport = String(format: "Estimated solvent-accessible area: %.2f Å² (%d atoms)", engine.estimatedSurfaceArea(of: atoms), atoms.count)
        case "volume":
            analysisReport = String(format: "Estimated van der Waals volume: %.2f Å³ (%d atoms)", engine.estimatedVolume(of: atoms), atoms.count)
        case "centroid", "center":
            let center = engine.centroid(of: atoms)
            analysisReport = String(format: "Centroid: (%.3f, %.3f, %.3f) Å", center.x, center.y, center.z)
        case "axis":
            let axis = engine.principalAxis(of: atoms)
            analysisReport = String(format: "Principal axis: (%.4f, %.4f, %.4f)", axis.x, axis.y, axis.z)
        case "plane":
            if let plane = engine.bestFitPlane(of: atoms) {
                analysisReport = String(
                    format: "Best-fit plane center (%.3f, %.3f, %.3f) · normal (%.4f, %.4f, %.4f) · RMS %.4f Å",
                    plane.center.x, plane.center.y, plane.center.z,
                    plane.normal.x, plane.normal.y, plane.normal.z,
                    plane.rmsd
                )
            } else { errorMessage = "Select at least three non-collinear atoms." }
        default:
            errorMessage = "Measure area, volume, centroid, or axis."
        }
        if let analysisReport { statusMessage = analysisReport }
    }

    func reportCavities() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        cavities = MolecularAnalysisEngine().cavities(in: structure)
        let total = cavities.reduce(Float.zero) { $0 + $1.volume }
        analysisReport = String(format: "%d enclosed cavit%@ · estimated total %.2f Å³", cavities.count, cavities.count == 1 ? "y" : "ies", total)
        statusMessage = analysisReport ?? "Cavity search complete"
        sceneRevision += 1
    }

    func reportInterfaces() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let engine = MolecularAnalysisEngine()
        let summaries = engine.interfaces(in: structure)
        let atomsByID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
        interactions = engine.contacts(in: structure, cutoff: 5, maximum: 20_000).filter { interaction in
            guard let first = atomsByID[interaction.atom1], let second = atomsByID[interaction.atom2] else { return false }
            return first.chainID != second.chainID
        }
        analysisReport = summaries.isEmpty ? "No chain interfaces found." : summaries.prefix(12).map {
            String(format: "Chains %@–%@ · %d contacts · minimum %.2f Å", $0.chain1, $0.chain2, $0.contactCount, $0.minimumDistance)
        }.joined(separator: "\n")
        statusMessage = "Found \(summaries.count) chain interface\(summaries.count == 1 ? "" : "s")"
        sceneRevision += 1
    }

    func reportConservation() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let engine = MolecularAnalysisEngine()
        let sequences = engine.sequences(in: structure)
        guard let result = engine.conservation(of: sequences.map(\.codes)) else {
            errorMessage = "At least one polymer sequence is required."
            return
        }
        let bars = result.scores.map { score in
            switch score { case 0.999...: "█"; case 0.75...: "▓"; case 0.5...: "▒"; default: "░" }
        }.joined()
        analysisReport = "Consensus across \(sequences.count) chain\(sequences.count == 1 ? "" : "s")\n\(result.consensus)\n\(bars)"
        statusMessage = "Sequence conservation calculated"
    }

    func reportSequences() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let sequences = MolecularAnalysisEngine().sequences(in: structure)
        guard !sequences.isEmpty else { analysisReport = "No polymer sequence was found."; return }
        analysisReport = sequences.map {
            ">Chain \($0.chainID.isEmpty ? "—" : $0.chainID) · \($0.residues.count) residues\n\($0.codes)"
        }.joined(separator: "\n\n")
        statusMessage = "Extracted \(sequences.count) chain sequence\(sequences.count == 1 ? "" : "s")"
    }

    func setReferenceStructure() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        referenceStructure = structure
        statusMessage = "Reference saved: \(structure.name)"
    }

    func compareWithReference(applyAlignment: Bool) {
        guard let structure, let referenceStructure else {
            errorMessage = "Save a reference structure first, then open or switch to the structure to compare."
            return
        }
        guard let comparison = MolecularAnalysisEngine().superpose(structure, onto: referenceStructure) else {
            errorMessage = "At least three matching atom names are required."
            return
        }
        analysisReport = String(
            format: "Matched %d atoms · RMSD %.4f Å",
            comparison.matchedAtomCount,
            comparison.rmsd
        )
        if applyAlignment {
            self.structure = comparison.alignedStructure
            selectedAtomIDs = []
            sceneRevision += 1
            statusMessage = "Structures matched · \(analysisReport ?? "")"
        } else {
            statusMessage = analysisReport ?? "Comparison complete"
        }
    }

    func compareTrajectoryFrame() {
        guard let structure, let first = trajectory?.frames.first,
              let comparison = MolecularAnalysisEngine().superpose(structure, onto: first) else {
            errorMessage = "Open a trajectory with matching frames first."
            return
        }
        analysisReport = String(format: "Frame %d vs frame 1 · fitted RMSD %.4f Å", trajectoryFrameIndex + 1, comparison.rmsd)
        statusMessage = analysisReport ?? "Trajectory comparison complete"
    }

    func alignSequences(chain firstChain: String, chain secondChain: String) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let sequences = MolecularAnalysisEngine().sequences(in: structure)
        guard let first = sequences.first(where: { $0.chainID.caseInsensitiveCompare(firstChain) == .orderedSame }),
              let second = sequences.first(where: { $0.chainID.caseInsensitiveCompare(secondChain) == .orderedSame }) else {
            errorMessage = "Both chain IDs must exist in the current structure."
            return
        }
        let alignment = MolecularAnalysisEngine().align(first.codes, second.codes)
        analysisReport = String(format: "Chain %@ vs %@ · %.1f%% identity\n%@\n%@", firstChain, secondChain, alignment.identity * 100, alignment.first, alignment.second)
        statusMessage = "Sequence alignment complete"
    }

    func reportMapStatistics() {
        guard let volume else { errorMessage = "Open a map first."; return }
        let stats = VolumeProcessor().statistics(volume)
        analysisReport = String(
            format: "%@ · %d × %d × %d\nmin %.5g · max %.5g · mean %.5g · σ %.5g\n%d nonzero voxels",
            volume.name, volume.dimensions.x, volume.dimensions.y, volume.dimensions.z,
            stats.minimum, stats.maximum, stats.mean, stats.standardDeviation, stats.nonzeroVoxelCount
        )
        statusMessage = "Map statistics calculated"
    }

    func smoothMap(radius: Int) {
        guard let volume else { errorMessage = "Open a map first."; return }
        self.volume = VolumeProcessor().smoothed(volume, radius: min(5, max(1, radius)))
        settings.mapThreshold = self.volume?.suggestedContour ?? settings.mapThreshold
        statusMessage = "Map smoothed"
        sceneRevision += 1
    }

    func sharpenMap(amount: Float) {
        guard let volume else { errorMessage = "Open a map first."; return }
        self.volume = VolumeProcessor().sharpened(volume, amount: min(5, max(0.1, amount)))
        settings.mapThreshold = self.volume?.suggestedContour ?? settings.mapThreshold
        statusMessage = "Map sharpened"
        sceneRevision += 1
    }

    func zoneMap(radius: Float) {
        guard let volume, let structure else { errorMessage = "Open both a map and structure first."; return }
        let atoms = selectedAtoms.isEmpty ? structure.atoms : selectedAtoms
        self.volume = VolumeProcessor().zoned(volume, around: atoms, radius: max(0.1, radius))
        statusMessage = "Map zoned within \(radius) Å of \(atoms.count) atoms"
        sceneRevision += 1
    }

    func segmentMap(threshold: Float?) {
        guard let volume else { errorMessage = "Open a map first."; return }
        let level = threshold ?? settings.mapThreshold
        volumeSegments = VolumeProcessor().segments(volume, threshold: level)
        let volumeTotal = volumeSegments.reduce(Float.zero) { $0 + $1.volume }
        analysisReport = String(format: "%d regions at level %.5g · total %.2f Å³\n%@", volumeSegments.count, level, volumeTotal,
            volumeSegments.prefix(20).map { String(format: "Region %d · %d voxels · %.2f Å³ · peak %.5g", $0.id + 1, $0.voxelCount, $0.volume, $0.peakValue) }.joined(separator: "\n"))
        statusMessage = "Map segmentation complete"
    }

    func setMapReference() {
        guard let volume else { errorMessage = "Open a map first."; return }
        referenceVolume = volume
        statusMessage = "Map reference saved: \(volume.name)"
    }

    func differenceFromMapReference() {
        guard let volume, let referenceVolume else { errorMessage = "Save a map reference, then open the comparison map."; return }
        guard let difference = VolumeProcessor().difference(volume, referenceVolume) else {
            errorMessage = "Difference maps currently require identical grid dimensions."
            return
        }
        self.volume = difference
        settings.mapThreshold = difference.suggestedContour
        statusMessage = "Difference map created"
        sceneRevision += 1
    }

    func fitStructureToMap() {
        guard var structure, let volume,
              let result = VolumeProcessor().fitAtoms(structure.atoms, to: volume) else {
            errorMessage = "Open both a structure and map first."
            return
        }
        for index in structure.atoms.indices {
            structure.atoms[index].position = structure.atoms[index].position + result.translation
        }
        self.structure = structure
        asymmetricUnit = structure
        analysisReport = String(
            format: "Atom-to-map translation (%.3f, %.3f, %.3f) Å · score %.5g",
            result.translation.x, result.translation.y, result.translation.z, result.score
        )
        statusMessage = "Structure fitted to map"
        sceneRevision += 1
    }

    func rigidFitStructureToMap() {
        guard var structure, let volume,
              let result = VolumeProcessor().rigidFitAtoms(structure.atoms, to: volume) else {
            errorMessage = "Open both a structure and map first."
            return
        }
        for index in structure.atoms.indices {
            structure.atoms[index].position = result.applying(to: structure.atoms[index].position)
        }
        self.structure = structure
        asymmetricUnit = structure
        analysisReport = String(
            format: "Rigid fit · rotation (%.1f°, %.1f°, %.1f°) · translation (%.3f, %.3f, %.3f) Å · score %.5g",
            result.rotationDegrees.x, result.rotationDegrees.y, result.rotationDegrees.z,
            result.translation.x, result.translation.y, result.translation.z, result.score
        )
        statusMessage = "Structure rigid-fitted to map"
        sceneRevision += 1
    }

    func fitMapToReference() {
        guard let volume, let referenceVolume,
              let result = VolumeProcessor().fitMap(volume, to: referenceVolume) else {
            errorMessage = "Save a reference map, then open the map to fit."
            return
        }
        self.volume = VolumeMap(
            name: "\(volume.name) · fitted",
            dimensions: volume.dimensions,
            origin: volume.origin + result.translation,
            spacing: volume.spacing,
            values: volume.values
        )
        analysisReport = String(
            format: "Map translation (%.3f, %.3f, %.3f) Å · correlation score %.5g",
            result.translation.x, result.translation.y, result.translation.z, result.score
        )
        statusMessage = "Map fitted to reference"
        sceneRevision += 1
    }

    func cropMap(_ values: [Int]) {
        guard let volume, values.count == 6,
              let crop = VolumeProcessor().cropped(
                volume,
                x: values[0]...values[1],
                y: values[2]...values[3],
                z: values[4]...values[5]
              ) else { errorMessage = "Usage: map crop x0 x1 y0 y1 z0 z1"; return }
        self.volume = crop
        settings.mapThreshold = crop.suggestedContour
        statusMessage = "Map cropped — \(volumeDescription)"
        sceneRevision += 1
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { statusMessage = "Nothing to undo"; return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
        statusMessage = "Undid last edit"
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { statusMessage = "Nothing to redo"; return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
        statusMessage = "Redid edit"
    }

    func deleteSelectedAtoms() {
        guard let structure, !selectedAtomIDs.isEmpty else { errorMessage = "Select atoms to delete."; return }
        applyEdit(MolecularEditor().deletingAtoms(Set(selectedAtomIDs), from: structure), message: "Deleted \(selectedAtomIDs.count) atoms")
    }

    func addBondFromSelection(order: Int = 1) {
        guard let structure, selectedAtomIDs.count == 2 else { errorMessage = "Select exactly two atoms."; return }
        applyEdit(MolecularEditor().addingBond(selectedAtomIDs[0], selectedAtomIDs[1], order: order, to: structure), message: "Bond added")
    }

    func deleteBondFromSelection() {
        guard let structure, selectedAtomIDs.count == 2 else { errorMessage = "Select exactly two atoms."; return }
        applyEdit(MolecularEditor().deletingBond(selectedAtomIDs[0], selectedAtomIDs[1], from: structure), message: "Bond deleted")
    }

    func mutateSelectedResidue(to residueName: String) {
        guard let structure, let atom = selectedAtoms.first else { errorMessage = "Select an atom in the residue to mutate."; return }
        let edited = MolecularEditor().mutatingResidue(
            chainID: atom.chainID,
            residueNumber: atom.residueNumber,
            to: residueName,
            in: structure
        )
        applyEdit(edited, message: "Mutated \(atom.chainID):\(atom.residueNumber) to \(residueName.uppercased())")
    }

    func renameChain(_ oldID: String, to newID: String) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        applyEdit(MolecularEditor().renamingChain(oldID, to: newID, in: structure), message: "Renamed chain \(oldID) to \(newID)")
    }

    func addAtom(element: String, position: Vector3) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let edited = MolecularEditor().addingAtom(to: structure, element: element, position: position)
        applyEdit(edited, message: "Added \(element.uppercased()) atom")
    }

    func prepareStructure(_ operation: String) {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let editor = MolecularEditor()
        let edited: MolecularStructure
        let message: String
        switch operation {
        case "hydrogens": edited = editor.addingHydrogens(to: structure); message = "Hydrogens added"
        case "charges": edited = editor.assigningSimpleCharges(to: structure); message = "Simple partial charges assigned"
        case "dockprep": edited = editor.dockPrepared(structure); message = "Dock Prep completed"
        case "minimize": edited = editor.minimized(structure); message = "Geometry minimized"
        default: return
        }
        applyEdit(edited, message: message)
    }

    func rotateSelectedBond(degrees: Float) {
        guard let structure, selectedAtomIDs.count >= 2 else { errorMessage = "Select the two atoms defining the rotatable bond."; return }
        let edited = MolecularEditor().rotatedAroundBond(selectedAtomIDs[0], selectedAtomIDs[1], degrees: degrees, in: structure)
        applyEdit(edited, message: "Rotated bond by \(degrees)°")
    }

    func tugSelection(by offset: Vector3) {
        guard let structure, !selectedAtomIDs.isEmpty else { errorMessage = "Select atoms to tug."; return }
        let edited = MolecularEditor().translated(Set(selectedAtomIDs), by: offset, in: structure)
        applyEdit(edited, message: "Moved \(selectedAtomIDs.count) selected atoms")
    }

    func applyRotamer(degrees: Float) {
        guard let structure, let selected = selectedAtoms.first else { errorMessage = "Select a residue first."; return }
        let residue = structure.atoms.filter { $0.chainID == selected.chainID && $0.residueNumber == selected.residueNumber }
        guard let ca = residue.first(where: { $0.name.uppercased() == "CA" }),
              let cb = residue.first(where: { $0.name.uppercased() == "CB" }) else {
            errorMessage = "The selected residue has no CA–CB rotamer axis."
            return
        }
        let edited = MolecularEditor().rotatedAroundBond(ca.id, cb.id, degrees: degrees, in: structure)
        applyEdit(edited, message: "Applied \(degrees)° side-chain rotamer")
    }

    func analyzeDockingPose() {
        guard let structure else { errorMessage = "Open a receptor–ligand structure first."; return }
        let ligandIDs = Set(MolecularSelectionEngine().atomIDs(in: structure, matching: .ligand))
        guard !ligandIDs.isEmpty else { errorMessage = "No ligand atoms were found."; return }
        let engine = MolecularAnalysisEngine()
        let contacts = engine.contacts(in: structure, cutoff: 4, maximum: 20_000).filter {
            ligandIDs.contains($0.atom1) != ligandIDs.contains($0.atom2)
        }
        let clashes = engine.clashes(in: structure, maximum: 10_000).filter {
            ligandIDs.contains($0.atom1) != ligandIDs.contains($0.atom2)
        }
        interactions = contacts + clashes
        selectedAtomIDs = Array(ligandIDs)
        analysisReport = "Docking pose · \(ligandIDs.count) ligand atoms · \(contacts.count) receptor contacts · \(clashes.count) clashes"
        statusMessage = "Docking pose analyzed"
        sceneRevision += 1
    }

    func modelMissingLoops() {
        guard let structure else { errorMessage = "Open a structure first."; return }
        let modeled = ComparativeModeler().fillingBackboneLoops(in: structure)
        guard modeled.atoms.count > structure.atoms.count else {
            statusMessage = "No numbered backbone gaps were found"
            return
        }
        applyEdit(modeled, message: "Modeled \(modeled.atoms.count - structure.atoms.count) backbone atoms")
    }

    func completeFromReferenceModel() {
        guard let structure, let referenceStructure else {
            errorMessage = "Save a reference template, then open the incomplete target model."
            return
        }
        guard let alignedTemplate = MolecularAnalysisEngine().superpose(referenceStructure, onto: structure)?.alignedStructure else {
            errorMessage = "At least three matching atoms are required to align the reference template."
            return
        }
        let modeled = ComparativeModeler().completing(structure, fromAlignedTemplate: alignedTemplate)
        guard modeled.atoms.count > structure.atoms.count else {
            statusMessage = "The reference has no missing atoms to add"
            return
        }
        applyEdit(modeled, message: "Added \(modeled.atoms.count - structure.atoms.count) atoms from the aligned reference")
    }

    private var currentSnapshot: Snapshot {
        Snapshot(structure: structure, asymmetricUnit: asymmetricUnit, volume: volume, settings: settings, selection: selectedAtomIDs)
    }

    private func recordUndo() {
        undoStack.append(currentSnapshot)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ snapshot: Snapshot) {
        structure = snapshot.structure
        asymmetricUnit = snapshot.asymmetricUnit
        volume = snapshot.volume
        settings = snapshot.settings
        selectedAtomIDs = snapshot.selection
        interactions = []
        cavities = []
        sceneRevision += 1
    }

    private func applyEdit(_ edited: MolecularStructure, message: String) {
        recordUndo()
        structure = edited
        asymmetricUnit = edited
        activeAlternateLocation = nil
        selectedAtomIDs = []
        interactions = []
        cavities = []
        statusMessage = message
        sceneRevision += 1
    }

    private func resetTrajectory() {
        trajectoryPlaybackTask?.cancel()
        trajectoryPlaybackTask = nil
        trajectory = nil
        trajectoryFrameIndex = 0
        isTrajectoryPlaying = false
    }

    func executeCommand() {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        commandHistory.append(command)
        commandText = ""
        if commandInputMode == .copilot {
            Task { await executeCopilotRequest(command) }
        } else {
            copilotPlan = nil
            executeScript(command)
        }
    }

    func executeScript(_ script: String) {
        let commands = script
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        for command in commands { execute(command) }
    }

    func dismissCopilotPlan() {
        copilotPlan = nil
    }

    private func executeCopilotRequest(_ request: String) async {
        let localPlan = CopilotInterpreter().plan(request)
        var plan = localPlan
        let endpointText = copilotBackendURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpointText.isEmpty, let endpoint = URL(string: endpointText) {
            let taskID = beginTask("Copilot", detail: "Planning a typed command sequence")
            isLoading = true
            defer { isLoading = false }
            do {
                let context = CopilotWorkspaceContext(
                    structureName: structure?.name,
                    atomCount: structure?.atoms.count ?? 0,
                    chainIDs: structure?.chainIDs ?? [],
                    mapName: volume?.name,
                    selectedAtomCount: selectedAtomIDs.count
                )
                plan = try await CopilotBackendClient().plan(
                    endpoint: endpoint,
                    request: request,
                    context: context,
                    bearerToken: copilotAccessToken
                )
                finishTask(taskID, state: .completed, detail: "Validated \(plan.commands.count) command(s)")
            } catch {
                finishTask(taskID, state: .failed, detail: error.localizedDescription)
                if localPlan.isActionable {
                    plan = localPlan
                    statusMessage = "Copilot service unavailable; used on-device planning"
                } else {
                    errorMessage = error.localizedDescription
                    return
                }
            }
        }
        copilotPlan = plan
        guard plan.isActionable else {
            statusMessage = "Copilot needs a supported viewing request"
            return
        }
        for command in plan.commands {
            execute(command)
        }
        statusMessage = plan.summary
    }

    func setCopilotBackendURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        copilotBackendURLString = trimmed
        UserDefaults.standard.set(trimmed, forKey: "MoleculePad.CopilotBackendURL")
        statusMessage = trimmed.isEmpty ? "Using on-device Copilot" : "Secure Copilot endpoint saved"
    }

    func setCopilotAccessToken(_ value: String) {
        copilotAccessToken = value.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(copilotAccessToken, for: "copilot-access-token")
        statusMessage = copilotAccessToken.isEmpty ? "Copilot access token removed" : "Copilot access token saved in Keychain"
    }

    func setComputeProviderURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        computeProviderURLString = trimmed
        UserDefaults.standard.set(trimmed, forKey: "MoleculePad.ComputeProviderURL")
        statusMessage = trimmed.isEmpty ? "Molecular compute disabled" : "Molecular compute endpoint saved"
    }

    func setComputeProviderAccessToken(_ value: String) {
        computeProviderAccessToken = value.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(computeProviderAccessToken, for: "compute-access-token")
        statusMessage = computeProviderAccessToken.isEmpty ? "Compute access token removed" : "Compute access token saved in Keychain"
    }

    func runQuickCommand(_ command: MoleculePadQuickCommand) {
        executeScript(command.script)
        statusMessage = "Ran \(command.title)"
    }

    func removeQuickCommand(id: UUID) {
        quickCommands.removeAll { $0.id == id }
        statusMessage = "Quick button removed"
    }

    func addCanvasStroke(_ points: [CanvasPoint]) {
        guard points.count >= 2 else { return }
        canvasStrokes.append(CanvasStroke(points: points))
        statusMessage = "Annotation stroke added"
    }

    func clearCanvasAnnotations() {
        canvasStrokes = []
        statusMessage = "2D annotations cleared"
    }

    private func addCustomPseudobond(group: String) {
        guard selectedAtomIDs.count == 2 else {
            errorMessage = "Select exactly two atoms to create a pseudobond."
            return
        }
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        customPseudobonds.append(CustomPseudobond(
            atom1: selectedAtomIDs[0], atom2: selectedAtomIDs[1],
            group: name.isEmpty ? "Custom" : name
        ))
        sceneRevision += 1
        statusMessage = "Pseudobond added to \(name.isEmpty ? "Custom" : name)"
    }

    func runPluginCommand(_ command: MoleculePadPluginCommand, pluginName: String) {
        executeScript(command.script)
        statusMessage = "Ran \(command.title) from \(pluginName)"
    }

    func removePlugin(id: String) {
        installedPlugins.removeAll { $0.id == id }
        statusMessage = "Plug-in removed"
    }

    func clearFinishedTasks() {
        taskItems.removeAll { $0.state != .running }
    }

    private func addQuickCommand(title: String, script: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let statements = MoleculePadPluginLoader.statements(in: script)
        guard !title.isEmpty, !statements.isEmpty,
              statements.allSatisfy(CopilotInterpreter().isAllowedCommand) else {
            errorMessage = "Quick buttons may only run allow-listed MoleculePad commands."
            return
        }
        quickCommands.removeAll { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        quickCommands.append(MoleculePadQuickCommand(title: title, script: statements.joined(separator: "; ")))
        statusMessage = "Quick button \(title) saved"
    }

    private func beginTask(_ title: String, detail: String) -> UUID {
        let id = UUID()
        taskItems.insert(WorkspaceTaskItem(id: id, title: title, state: .running, detail: detail, startedAt: Date()), at: 0)
        if taskItems.count > 30 { taskItems.removeLast(taskItems.count - 30) }
        return id
    }

    private func finishTask(_ id: UUID, state: WorkspaceTaskState, detail: String) {
        guard let index = taskItems.firstIndex(where: { $0.id == id }) else { return }
        taskItems[index].state = state
        taskItems[index].detail = detail
    }

    func execute(_ command: String) {
        let parts = command.lowercased().split(separator: " ").map(String.init)
        guard let verb = parts.first else { return }
        if let expansion = aliases[verb] {
            let suffix = parts.dropFirst().joined(separator: " ")
            executeScript(suffix.isEmpty ? expansion : "\(expansion) \(suffix)")
            return
        }
        switch verb {
        case "open" where parts.count == 2, "fetch" where parts.count == 2:
            let identifier = parts[1]
            if identifier.hasPrefix("emd-") || identifier.hasPrefix("emd_") {
                Task { await fetchEMDB(id: identifier) }
            } else {
                Task { await fetchPDB(id: identifier) }
            }
        case "alphafold" where parts.count == 2:
            Task { await fetchAlphaFold(id: parts[1]) }
        case "blast" where parts.count == 1 || (parts.count == 2 && parts[1] == "protein"):
            Task { await runProteinBLAST() }
        case "similar" where parts.count == 1 || (parts.count == 2 && parts[1] == "current"):
            Task { await runRCSBStructureSimilarity() }
        case "similar" where parts.count == 2:
            Task { await runRCSBStructureSimilarity(pdbID: parts[1]) }
        case "foldseek":
            Task { await runMolecularCompute(.foldseek) }
        case "compute" where parts.count == 2:
            if let operation = MolecularComputeOperation(rawValue: parts[1]), operation != .foldseek {
                Task { await runMolecularCompute(operation) }
            } else { errorMessage = "Compute operations: esmfold, openfold, boltz" }
        case "style" where parts.count >= 2:
            let value = parts.dropFirst().joined(separator: "")
            let mapping: [String: MolecularRepresentation] = [
                "ball": .ballAndStick, "ball&stick": .ballAndStick, "ballandstick": .ballAndStick,
                "spacefill": .spacefill, "spheres": .spacefill,
                "sticks": .sticks, "cartoon": .cartoon, "ribbon": .cartoon,
                "backbone": .backbone, "nucleotide": .nucleotides, "nucleotides": .nucleotides,
                "glycan": .glycans, "glycans": .glycans, "thermal": .thermal,
                "ellipsoid": .thermal, "ellipsoids": .thermal
            ]
            if let representation = mapping[value] {
                settings.representation = representation
                sceneRevision += 1
                statusMessage = "Style: \(representation.rawValue)"
            } else { errorMessage = "Styles: ball, spacefill, sticks, cartoon, backbone, nucleotides, glycans, thermal" }
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
        case "label" where parts.count == 2:
            let mapping: [String: MolecularLabelStyle] = [
                "none": .none, "off": .none, "selected": .selected,
                "atoms": .atoms, "residues": .residues, "chains": .chains
            ]
            if let style = mapping[parts[1]] {
                settings.labelStyle = style
                sceneRevision += 1
                statusMessage = "Labels: \(style.rawValue)"
            } else { errorMessage = "Labels: none, selected, atoms, residues, or chains" }
        case "lighting" where parts.count == 2:
            if let preset = LightingPreset(rawValue: parts[1].capitalized) {
                settings.lightingPreset = preset
                sceneRevision += 1
                statusMessage = "Lighting: \(preset.rawValue)"
            } else { errorMessage = "Lighting: studio, soft, flat, or dramatic" }
        case "view" where parts.count == 2:
            if let direction = ViewDirection(rawValue: parts[1].capitalized) {
                settings.viewDirection = direction
                sceneRevision += 1
                statusMessage = "View: \(direction.rawValue)"
            } else { errorMessage = "Views: front, back, left, right, top, or bottom" }
        case "axes" where parts.count == 2 && ["show", "hide"].contains(parts[1]):
            settings.showAxes = parts[1] == "show"
            sceneRevision += 1
        case "scalebar" where parts.count == 2 && ["show", "hide"].contains(parts[1]):
            settings.showScaleBar = parts[1] == "show"
            sceneRevision += 1
        case "arrow" where parts.count == 2 && ["show", "hide"].contains(parts[1]):
            settings.showSelectionArrow = parts[1] == "show"
            sceneRevision += 1
        case "clip" where parts.count == 3 && parts[1] == "near":
            if let value = Double(parts[2]), value >= 0.001 {
                settings.nearClip = value
                sceneRevision += 1
            } else { errorMessage = "Usage: clip near 0.1" }
        case "clip" where parts.count == 3 && parts[1] == "far":
            if let value = Double(parts[2]), value > settings.nearClip {
                settings.farClip = value
                sceneRevision += 1
            } else { errorMessage = "The far clip must be beyond the near clip." }
        case "surface" where parts.count == 3 && parts[1] == "level":
            if let value = Float(parts[2]) {
                settings.mapThreshold = value
                settings.showMap = true
                sceneRevision += 1
            } else { errorMessage = "Usage: surface level 0.8" }
        case "map" where parts.count == 3 && parts[1] == "style":
            let mapping: [String: VolumeDisplayStyle] = [
                "surface": .surface, "isosurface": .surface, "volume": .volume,
                "solid": .volume, "slices": .slices, "slice": .slices
            ]
            if let style = mapping[parts[2]] {
                settings.volumeDisplayStyle = style
                settings.showMap = true
                sceneRevision += 1
                statusMessage = "Map display: \(style.rawValue)"
            } else { errorMessage = "Map styles: surface, volume, or slices" }
        case "map" where parts.count == 3 && parts[1] == "smooth":
            smoothMap(radius: Int(parts[2]) ?? 1)
        case "map" where parts.count == 3 && parts[1] == "sharpen":
            sharpenMap(amount: Float(parts[2]) ?? 1)
        case "map" where parts.count == 3 && parts[1] == "zone":
            if let radius = Float(parts[2]) { zoneMap(radius: radius) }
            else { errorMessage = "Usage: map zone 4" }
        case "map" where parts.count == 2 && parts[1] == "stats":
            reportMapStatistics()
        case "map" where parts.count == 2 && parts[1] == "segment":
            segmentMap(threshold: nil)
        case "map" where parts.count == 3 && parts[1] == "segment":
            segmentMap(threshold: Float(parts[2]))
        case "map" where parts.count == 3 && parts[1] == "reference" && ["set", "save"].contains(parts[2]):
            setMapReference()
        case "map" where parts.count == 2 && parts[1] == "difference":
            differenceFromMapReference()
        case "map" where parts.count == 8 && parts[1] == "crop":
            cropMap(parts.dropFirst(2).compactMap(Int.init))
        case "fit" where parts.count == 2 && ["map", "atoms", "structure"].contains(parts[1]):
            fitStructureToMap()
        case "fit" where parts.count == 3 && parts[1] == "map" && ["rotate", "rigid"].contains(parts[2]):
            rigidFitStructureToMap()
        case "fit" where parts.count == 2 && ["maps", "map-to-map"].contains(parts[1]):
            fitMapToReference()
        case "undo":
            undo()
        case "redo":
            redo()
        case "delete" where parts.count == 2 && ["selected", "selection", "atoms"].contains(parts[1]):
            deleteSelectedAtoms()
        case "bond" where parts.count >= 2 && parts[1] == "add":
            addBondFromSelection(order: parts.count == 3 ? Int(parts[2]) ?? 1 : 1)
        case "bond" where parts.count == 2 && parts[1] == "delete":
            deleteBondFromSelection()
        case "mutate" where parts.count == 2:
            mutateSelectedResidue(to: parts[1])
        case "chain" where parts.count == 4 && parts[1] == "rename" && parts[2] == "to":
            guard let oldID = selectedAtoms.first?.chainID else { errorMessage = "Select an atom in the chain to rename."; return }
            renameChain(oldID, to: parts[3])
        case "chain" where parts.count == 4 && parts[1] == "rename":
            renameChain(parts[2], to: parts[3])
        case "atom" where parts.count == 6 && parts[1] == "add",
             "addatom" where parts.count == 5:
            let offset = verb == "atom" ? 2 : 1
            if let x = Float(parts[offset + 1]), let y = Float(parts[offset + 2]), let z = Float(parts[offset + 3]) {
                addAtom(element: parts[offset], position: Vector3(x: x, y: y, z: z))
            } else { errorMessage = "Usage: atom add C 0 0 0" }
        case "addh", "hydrogens":
            prepareStructure("hydrogens")
        case "charges":
            prepareStructure("charges")
        case "dockprep":
            prepareStructure("dockprep")
        case "minimize":
            prepareStructure("minimize")
        case "torsion" where parts.count == 2:
            if let degrees = Float(parts[1]) { rotateSelectedBond(degrees: degrees) }
            else { errorMessage = "Usage: torsion 60" }
        case "rotamer" where parts.count == 2:
            if let degrees = Float(parts[1]) { applyRotamer(degrees: degrees) }
            else { errorMessage = "Usage: rotamer 60" }
        case "tug" where parts.count == 4:
            if let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                tugSelection(by: Vector3(x: x, y: y, z: z))
            } else { errorMessage = "Usage: tug 1 0 0" }
        case "dock" where parts.count == 2 && parts[1] == "analyze":
            analyzeDockingPose()
        case "model" where parts.count == 2 && ["loops", "gaps"].contains(parts[1]):
            modelMissingLoops()
        case "model" where parts.count == 2 && ["reference", "template"].contains(parts[1]):
            completeFromReferenceModel()
        case "alias" where parts.count >= 3:
            aliases[parts[1]] = parts.dropFirst(2).joined(separator: " ")
            statusMessage = "Alias \(parts[1]) saved"
        case "unalias" where parts.count == 2:
            aliases.removeValue(forKey: parts[1])
            statusMessage = "Alias \(parts[1]) removed"
        case "button" where parts.count >= 4 && parts[1] == "add":
            let payload = String(command.dropFirst("button add".count))
            let fields = payload.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if fields.count == 2 { addQuickCommand(title: fields[0], script: fields[1]) }
            else { errorMessage = "Usage: button add Ribbon = style cartoon" }
        case "button" where parts.count >= 3 && parts[1] == "delete":
            let title = parts.dropFirst(2).joined(separator: " ")
            quickCommands.removeAll { $0.title.lowercased() == title }
            statusMessage = "Quick button \(title) removed"
        case "pseudobond" where parts.count >= 2 && parts[1] == "add":
            addCustomPseudobond(group: parts.count > 2 ? parts.dropFirst(2).joined(separator: " ") : "Custom")
        case "pseudobond" where parts.count == 2 && parts[1] == "clear":
            customPseudobonds = []
            sceneRevision += 1
            statusMessage = "Custom pseudobonds cleared"
        case "annotate" where parts.count == 2 && ["start", "on"].contains(parts[1]):
            isDrawingAnnotations = true
            statusMessage = "Draw over the viewport with Apple Pencil or touch"
        case "annotate" where parts.count == 2 && ["stop", "off"].contains(parts[1]):
            isDrawingAnnotations = false
            statusMessage = "Annotation drawing stopped"
        case "annotate" where parts.count == 2 && parts[1] == "clear":
            clearCanvasAnnotations()
        case "scene" where parts.count >= 3 && parts[1] == "save":
            let name = parts.dropFirst(2).joined(separator: " ")
            savedScenes[name] = settings
            statusMessage = "Scene \(name) saved"
        case "scene" where parts.count >= 3 && parts[1] == "show":
            let name = parts.dropFirst(2).joined(separator: " ")
            if let scene = savedScenes[name] {
                settings = scene
                statusMessage = "Scene \(name) restored"
                sceneRevision += 1
            } else { errorMessage = "Scene \(name) was not found." }
        case "scene" where parts.count >= 3 && parts[1] == "delete":
            let name = parts.dropFirst(2).joined(separator: " ")
            savedScenes.removeValue(forKey: name)
            statusMessage = "Scene \(name) deleted"
        case "presentation" where parts.count == 2 && ["start", "on", "show"].contains(parts[1]):
            isPresentationMode = true
            showInspector = false
            statusMessage = "Presentation mode"
        case "presentation" where parts.count == 2 && ["stop", "off", "exit"].contains(parts[1]):
            isPresentationMode = false
            statusMessage = "Presentation mode ended"
        case "surface" where parts.count == 2 && ["show", "hide"].contains(parts[1]):
            settings.showMolecularSurface = parts[1] == "show"
            sceneRevision += 1
            statusMessage = settings.showMolecularSurface ? "Molecular surface shown" : "Molecular surface hidden"
        case "surface" where parts.count == 3 && parts[1] == "style":
            if let style = MolecularSurfaceStyle(rawValue: parts[2].capitalized) {
                settings.molecularSurfaceStyle = style
                settings.showMolecularSurface = true
                sceneRevision += 1
                statusMessage = "Surface style: \(style.rawValue)"
            } else { errorMessage = "Surface styles: solid or mesh" }
        case "surface" where parts.count == 3 && parts[1] == "color":
            let mapping: [String: MolecularSurfaceColorMode] = [
                "uniform": .uniform, "element": .element, "chain": .chain,
                "residue": .residue, "bfactor": .bFactor, "b-factor": .bFactor,
                "charge": .charge
            ]
            if let mode = mapping[parts[2]] {
                settings.molecularSurfaceColorMode = mode
                settings.showMolecularSurface = true
                sceneRevision += 1
                statusMessage = "Surface color: \(mode.rawValue)"
            } else { errorMessage = "Surface colors: uniform, element, chain, residue, bfactor, charge" }
        case "surface" where parts.count == 3 && parts[1] == "opacity":
            if let raw = Double(parts[2]) {
                settings.molecularSurfaceOpacity = min(1, max(0.05, raw > 1 ? raw / 100 : raw))
                settings.showMolecularSurface = true
                sceneRevision += 1
            } else { errorMessage = "Usage: surface opacity 0.7" }
        case "surface" where parts.count == 3 && parts[1] == "probe":
            if let value = Float(parts[2]), (0...5).contains(value) {
                settings.molecularSurfaceProbeRadius = value
                settings.showMolecularSurface = true
                sceneRevision += 1
            } else { errorMessage = "Use a probe radius from 0 to 5 Å." }
        case "trajectory" where parts.count == 2 && parts[1] == "play":
            guard trajectory != nil else { errorMessage = "Open a multi-model PDB trajectory first."; return }
            setTrajectoryPlayback(true)
            statusMessage = "Trajectory playing"
        case "trajectory" where parts.count == 2 && ["pause", "stop"].contains(parts[1]):
            setTrajectoryPlayback(false)
            statusMessage = "Trajectory paused"
        case "trajectory" where parts.count == 2 && parts[1] == "next":
            stepTrajectory()
        case "trajectory" where parts.count == 2 && ["previous", "prev"].contains(parts[1]):
            stepTrajectory(-1)
        case "trajectory" where parts.count == 3 && parts[1] == "frame":
            if let frame = Int(parts[2]), frame > 0 { setTrajectoryFrame(frame - 1) }
            else { errorMessage = "Usage: trajectory frame 12" }
        case "assembly" where parts.count == 2 && ["asymmetric", "asu", "none"].contains(parts[1]):
            showAsymmetricUnit()
        case "assembly" where parts.count == 2:
            showBiologicalAssembly(parts[1])
        case "altloc" where parts.count == 2 && ["primary", "default", "none"].contains(parts[1]):
            showAlternateLocation(nil)
        case "altloc" where parts.count == 2:
            showAlternateLocation(parts[1])
        case "hbonds", "hbond":
            calculateInteractions(.hydrogenBond)
        case "contacts":
            calculateInteractions(.contact)
        case "clashes":
            calculateInteractions(.clash)
        case "interactions" where parts.count == 2 && parts[1] == "clear":
            clearInteractions()
        case "measure" where parts.count == 2:
            reportGeometry(parts[1])
        case "cavities", "cavity":
            reportCavities()
        case "interfaces", "interface":
            reportInterfaces()
        case "sequence":
            reportSequences()
        case "conservation":
            reportConservation()
        case "reference" where parts.count == 2 && ["set", "save"].contains(parts[1]):
            setReferenceStructure()
        case "reference" where parts.count == 2 && parts[1] == "clear":
            referenceStructure = nil
            statusMessage = "Reference cleared"
        case "rmsd" where parts.count == 2 && parts[1] == "reference":
            compareWithReference(applyAlignment: false)
        case "rmsd" where parts.count == 2 && ["trajectory", "frame"].contains(parts[1]):
            compareTrajectoryFrame()
        case "match" where parts.count == 2 && parts[1] == "reference":
            compareWithReference(applyAlignment: true)
        case "align" where parts.count == 4 && parts[1] == "chains":
            alignSequences(chain: parts[2], chain: parts[3])
        case "hide" where parts.count == 2:
            setVisibility(parts[1], visible: false)
        case "show" where parts.count == 2:
            setVisibility(parts[1], visible: true)
        case "clear":
            clearSelection()
        case "select" where parts.count >= 2:
            if parts[1] == "clear" || parts[1] == "none" {
                clearSelection()
            } else if let query = selectionQuery(from: parts) {
                applySelection(query)
            } else {
                errorMessage = "Selections: all, chain A, residue 42, resname LYS, element O, atom CA, ligand, water, clear"
            }
        case "help":
            statusMessage = "alias name command · button add Title = command · scene save|show name · scripts accept newline/semicolon commands · undo · delete selected · dockprep · minimize · torsion 60"
        default:
            errorMessage = "Unknown command. Type help for supported commands."
        }
    }

    private func setVisibility(_ target: String, visible: Bool) {
        if ["atoms", "structure", "model"].contains(target) {
            settings.showAtoms = visible
        } else if ["surface", "molsurface"].contains(target) {
            settings.showMolecularSurface = visible
        } else if ["map", "volume", "density"].contains(target) {
            settings.showMap = visible
        } else {
            errorMessage = "Choose atoms, surface, or map."
            return
        }
        sceneRevision += 1
    }

    private func selectionQuery(from parts: [String]) -> MolecularSelectionQuery? {
        switch parts[1] {
        case "all", "everything":
            return .all
        case "chain" where parts.count == 3:
            return .chain(parts[2])
        case "residue" where parts.count == 3,
             "resid" where parts.count == 3:
            if let number = Int(parts[2]) { return .residueNumber(number) }
            return .residueName(parts[2])
        case "resname" where parts.count == 3:
            return .residueName(parts[2])
        case "element" where parts.count == 3:
            return .element(parts[2])
        case "atom" where parts.count == 3,
             "atomname" where parts.count == 3:
            return .atomName(parts[2])
        case "ligand", "ligands":
            return .ligand
        case "water", "waters", "solvent":
            return .water
        default:
            return nil
        }
    }

    private func applySelection(_ query: MolecularSelectionQuery) {
        guard let structure else {
            errorMessage = "Open a structure before selecting atoms."
            return
        }
        let atomIDs = MolecularSelectionEngine().atomIDs(in: structure, matching: query)
        guard !atomIDs.isEmpty else {
            selectedAtomIDs = []
            statusMessage = "Selection matched no atoms"
            sceneRevision += 1
            return
        }
        selectedAtomIDs = atomIDs
        statusMessage = "Selected \(atomIDs.count) atom\(atomIDs.count == 1 ? "" : "s")"
        sceneRevision += 1
    }

    func encodedSession() throws -> Data {
        let appearance = sessionAppearance(from: settings)
        let scenes = savedScenes.keys.sorted().compactMap { name in
            savedScenes[name].map { SessionScene(name: name, appearance: sessionAppearance(from: $0)) }
        }
        return try SessionCodec().encode(MoleculePadSession(
            structure: structure,
            volume: volume.map(SessionVolume.init),
            selection: selectedAtomIDs,
            appearance: appearance,
            aliases: aliases,
            scenes: scenes,
            plugins: installedPlugins,
            quickCommands: quickCommands,
            customPseudobonds: customPseudobonds,
            canvasStrokes: canvasStrokes
        ))
    }

    private func restoreSession(_ session: MoleculePadSession) throws {
        structure = session.structure
        asymmetricUnit = session.structure
        volume = session.volume?.volumeMap
        selectedAtomIDs = session.selection
        settings = renderSettings(from: session.appearance)
        aliases = session.aliases
        savedScenes = Dictionary(uniqueKeysWithValues: session.scenes.map { ($0.name, renderSettings(from: $0.appearance)) })
        installedPlugins = session.plugins ?? []
        quickCommands = session.quickCommands ?? []
        customPseudobonds = session.customPseudobonds ?? []
        canvasStrokes = session.canvasStrokes ?? []
        interactions = []
        cavities = []
        resetTrajectory()
        sceneRevision += 1
    }

    private func sessionAppearance(from value: RenderSettings) -> SessionAppearance {
        SessionAppearance(
            representation: value.representation.rawValue,
            colorMode: value.colorMode.rawValue,
            surfaceStyle: value.molecularSurfaceStyle.rawValue,
            surfaceColorMode: value.molecularSurfaceColorMode.rawValue,
            labelStyle: value.labelStyle.rawValue,
            lightingPreset: value.lightingPreset.rawValue,
            viewDirection: value.viewDirection.rawValue,
            volumeDisplayStyle: value.volumeDisplayStyle.rawValue,
            atomScale: value.atomScale,
            bondScale: value.bondScale,
            showAtoms: value.showAtoms,
            showMolecularSurface: value.showMolecularSurface,
            surfaceOpacity: value.molecularSurfaceOpacity,
            surfaceProbeRadius: value.molecularSurfaceProbeRadius,
            showMap: value.showMap,
            mapThreshold: value.mapThreshold,
            mapOpacity: value.mapOpacity,
            mapWireframe: value.mapWireframe,
            showAxes: value.showAxes,
            showScaleBar: value.showScaleBar,
            showSelectionArrow: value.showSelectionArrow,
            nearClip: value.nearClip,
            farClip: value.farClip,
            molecularSurfaceColor: rgba(value.molecularSurfaceColor),
            mapColor: rgba(value.mapColor),
            labelColor: rgba(value.labelColor),
            backgroundColor: rgba(value.backgroundColor)
        )
    }

    private func renderSettings(from value: SessionAppearance) -> RenderSettings {
        var result = RenderSettings()
        result.representation = MolecularRepresentation(rawValue: value.representation) ?? result.representation
        result.colorMode = AtomColorMode(rawValue: value.colorMode) ?? result.colorMode
        result.molecularSurfaceStyle = MolecularSurfaceStyle(rawValue: value.surfaceStyle) ?? result.molecularSurfaceStyle
        result.molecularSurfaceColorMode = value.surfaceColorMode.flatMap(MolecularSurfaceColorMode.init(rawValue:)) ?? result.molecularSurfaceColorMode
        result.labelStyle = MolecularLabelStyle(rawValue: value.labelStyle) ?? result.labelStyle
        result.lightingPreset = LightingPreset(rawValue: value.lightingPreset) ?? result.lightingPreset
        result.viewDirection = ViewDirection(rawValue: value.viewDirection) ?? result.viewDirection
        result.volumeDisplayStyle = VolumeDisplayStyle(rawValue: value.volumeDisplayStyle) ?? result.volumeDisplayStyle
        result.atomScale = value.atomScale; result.bondScale = value.bondScale; result.showAtoms = value.showAtoms
        result.showMolecularSurface = value.showMolecularSurface; result.molecularSurfaceOpacity = value.surfaceOpacity
        result.molecularSurfaceProbeRadius = value.surfaceProbeRadius; result.showMap = value.showMap
        result.mapThreshold = value.mapThreshold; result.mapOpacity = value.mapOpacity; result.mapWireframe = value.mapWireframe
        result.showAxes = value.showAxes; result.showScaleBar = value.showScaleBar; result.showSelectionArrow = value.showSelectionArrow
        result.nearClip = value.nearClip; result.farClip = value.farClip
        result.molecularSurfaceColor = color(value.molecularSurfaceColor, fallback: result.molecularSurfaceColor)
        result.mapColor = color(value.mapColor, fallback: result.mapColor)
        result.labelColor = color(value.labelColor, fallback: result.labelColor)
        result.backgroundColor = color(value.backgroundColor, fallback: result.backgroundColor)
        return result
    }

    private func rgba(_ color: Color) -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [Double(red), Double(green), Double(blue), Double(alpha)]
    }

    private func color(_ values: [Double], fallback: Color) -> Color {
        guard values.count >= 4 else { return fallback }
        return Color(red: values[0], green: values[1], blue: values[2], opacity: values[3])
    }

    private var volumeDescription: String {
        guard let d = volume?.dimensions else { return "0 voxels" }
        return "\(d.x) × \(d.y) × \(d.z) voxels"
    }

    private func normalizedEMDBID(_ rawID: String) -> String {
        rawID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "EMD-", with: "")
            .replacingOccurrences(of: "EMD_", with: "")
    }

    private func isCompressedMap(_ url: URL) -> Bool {
        let lowercasedName = url.lastPathComponent.lowercased()
        return [".map.gz", ".mrc.gz", ".ccp4.gz"].contains { lowercasedName.hasSuffix($0) }
    }
}
