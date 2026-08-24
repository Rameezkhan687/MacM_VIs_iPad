import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showImporter = false
    @State private var showFetchSheet = false
    @State private var showHelp = false

    var body: some View {
        NavigationSplitView {
            ModelSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
        } detail: {
            ZStack {
                MolecularSceneView(
                    structure: workspace.structure,
                    volume: workspace.volume,
                    settings: workspace.settings,
                    selectedAtomIDs: workspace.selectedAtomIDs,
                    revision: workspace.sceneRevision,
                    onSelectAtom: { workspace.selectAtom($0, additive: true) }
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    ViewportHUD()
                    Spacer()
                    CommandBar(showHelp: $showHelp)
                }

                if workspace.structure == nil && workspace.volume == nil {
                    EmptyWorkspaceView(showImporter: $showImporter, showFetchSheet: $showFetchSheet)
                }

                if workspace.showInspector {
                    HStack {
                        Spacer()
                        InspectorPanel()
                            .padding(.trailing, 12)
                            .padding(.top, 54)
                            .padding(.bottom, 62)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if workspace.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .padding(22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .toolbar { toolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): workspace.openFiles(urls)
            case .failure(let error): workspace.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showFetchSheet) { FetchPDBSheet() }
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .alert("MoleculePad", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "Unknown error")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showImporter = true } label: {
                Label("Open file", systemImage: "folder.badge.plus")
            }
            Button { showFetchSheet = true } label: {
                Label("Fetch PDB", systemImage: "arrow.down.circle")
            }
            Menu {
                Picker("Representation", selection: $workspace.settings.representation) {
                    ForEach(MolecularRepresentation.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Picker("Color", selection: $workspace.settings.colorMode) {
                    ForEach(AtomColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Appearance", systemImage: "paintpalette")
            }
            Button {
                withAnimation(.snappy) { workspace.showInspector.toggle() }
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button { workspace.sceneRevision += 1 } label: {
                Label("Refresh scene", systemImage: "view.3d")
            }
        }
    }

    private var supportedTypes: [UTType] {
        ["pdb", "ent", "mrc", "map", "ccp4"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }
}

private struct ModelSidebar: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        List {
            Section("Models") {
                if let structure = workspace.structure {
                    LayerRow(
                        icon: "atom",
                        color: .cyan,
                        title: structure.name,
                        subtitle: "\(structure.atoms.count) atoms · \(structure.bonds.count) bonds",
                        isVisible: $workspace.settings.showAtoms,
                        onClose: workspace.closeStructure
                    )
                }
                if let volume = workspace.volume {
                    let d = volume.dimensions
                    LayerRow(
                        icon: "square.3.layers.3d",
                        color: .mint,
                        title: volume.name,
                        subtitle: "\(d.x) × \(d.y) × \(d.z) map",
                        isVisible: $workspace.settings.showMap,
                        onClose: workspace.closeMap
                    )
                }
                if workspace.structure == nil && workspace.volume == nil {
                    ContentUnavailableView("No models", systemImage: "cube.transparent", description: Text("Open a PDB or density map."))
                }
            }

            if let structure = workspace.structure {
                Section("Chains") {
                    ForEach(structure.chainIDs, id: \.self) { chain in
                        Label(chain.isEmpty ? "Unlabeled chain" : "Chain \(chain)", systemImage: "link")
                    }
                }
            }

            Section("Selection") {
                if workspace.selectedAtoms.isEmpty {
                    Text("Tap atoms to inspect or measure")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workspace.selectedAtoms) { atom in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(atom.name) · \(atom.element)")
                                .font(.body.weight(.semibold))
                            Text("\(atom.residueName) \(atom.residueNumber) · Chain \(atom.chainID.isEmpty ? "—" : atom.chainID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let distance = workspace.measuredDistance {
                        Label(String(format: "%.2f Å", distance), systemImage: "ruler")
                            .foregroundStyle(.yellow)
                    }
                    Button("Clear selection", action: workspace.clearSelection)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MoleculePad")
    }
}

private struct LayerRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isVisible: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { isVisible.toggle() } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
            Menu {
                Button("Close", role: .destructive, action: onClose)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct ViewportHUD: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(workspace.isLoading ? .orange : .green).frame(width: 7, height: 7)
                Text(workspace.statusMessage)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Label("Drag rotate · Pinch zoom · Two-finger pan", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(12)
    }
}

private struct InspectorPanel: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Inspector", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    Button { workspace.showInspector = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Structure").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Representation", selection: $workspace.settings.representation) {
                        ForEach(MolecularRepresentation.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Color by", selection: $workspace.settings.colorMode) {
                        ForEach(AtomColorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Atom size") {
                        Slider(value: $workspace.settings.atomScale, in: 0.45...1.8)
                            .frame(width: 130)
                    }
                    LabeledContent("Bond size") {
                        Slider(value: $workspace.settings.bondScale, in: 0.4...2)
                            .frame(width: 130)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Density map").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $workspace.settings.showMap).labelsHidden()
                    }
                    LabeledContent("Level") {
                        TextField("Contour", value: $workspace.settings.mapThreshold, format: .number.precision(.fractionLength(3)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 92)
                    }
                    if let volume = workspace.volume {
                        Slider(
                            value: Binding(
                                get: { Double(workspace.settings.mapThreshold) },
                                set: { workspace.settings.mapThreshold = Float($0) }
                            ),
                            in: Double(volume.minimum)...Double(max(volume.minimum + 0.001, volume.maximum))
                        )
                    }
                    LabeledContent("Opacity") {
                        Slider(value: $workspace.settings.mapOpacity, in: 0.08...1)
                            .frame(width: 130)
                    }
                    Toggle("Wireframe", isOn: $workspace.settings.mapWireframe)
                    ColorPicker("Map color", selection: $workspace.settings.mapColor)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Selection").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let atom = workspace.selectedAtoms.last {
                        LabeledContent("Atom", value: atom.name)
                        LabeledContent("Element", value: atom.element)
                        LabeledContent("Residue", value: "\(atom.residueName) \(atom.residueNumber)")
                        LabeledContent("B-factor", value: String(format: "%.2f", atom.bFactor))
                    } else {
                        Text("Tap an atom in the viewport.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let distance = workspace.measuredDistance {
                        LabeledContent("Distance", value: String(format: "%.3f Å", distance))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 292)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        .onChange(of: workspace.settings) { _, _ in workspace.sceneRevision += 1 }
    }
}

private struct CommandBar: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Binding var showHelp: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right.2").foregroundStyle(.cyan)
            TextField("Command — try: open 1crn", text: $workspace.commandText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(workspace.executeCommand)
            Button(action: workspace.executeCommand) {
                Image(systemName: "return")
            }
            .disabled(workspace.commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct EmptyWorkspaceView: View {
    @Binding var showImporter: Bool
    @Binding var showFetchSheet: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 58, weight: .thin))
                .foregroundStyle(.cyan)
            Text("Start exploring").font(.largeTitle.bold())
            Text("Open a structure or density map from Files, or fetch a structure from the Protein Data Bank.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack {
                Button("Open File") { showImporter = true }.buttonStyle(.borderedProminent)
                Button("Fetch PDB") { showFetchSheet = true }.buttonStyle(.bordered)
            }
        }
        .padding(36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
}

private struct FetchPDBSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var pdbID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("PDB ID (for example 1CRN)", text: $pdbID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Downloads the standard PDB file directly from RCSB.org.")
                }
            }
            .navigationTitle("Fetch Structure")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fetch") {
                        let id = pdbID
                        dismiss()
                        Task { await workspace.fetchPDB(id: id) }
                    }
                    .disabled(pdbID.trimmingCharacters(in: .whitespacesAndNewlines).count != 4)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Touch controls") {
                    Label("One-finger drag rotates", systemImage: "hand.draw")
                    Label("Pinch zooms", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Two-finger drag pans", systemImage: "hand.point.up.left")
                    Label("Tap one or two atoms to inspect and measure", systemImage: "ruler")
                }
                Section("Commands") {
                    command("open 1crn", "Fetch a PDB structure")
                    command("style spacefill", "Change representation")
                    command("color chain", "Color atoms by chain")
                    command("surface level 0.8", "Set the map contour")
                    command("hide map", "Hide the density map")
                    command("show atoms", "Show the atomic model")
                }
                Section("Supported files") {
                    Text("PDB structures and MRC/CCP4 density maps. Large maps are downsampled on import for interactive performance.")
                }
            }
            .navigationTitle("MoleculePad Help")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func command(_ syntax: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(syntax).font(.system(.body, design: .monospaced)).foregroundStyle(.cyan)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }
    }
}
