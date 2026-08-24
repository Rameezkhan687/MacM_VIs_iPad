import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showImporter = false
    @State private var showDatabaseSheet = false
    @State private var showHelp = false
    @State private var showWorkspaceTools = false
    @State private var showSessionExporter = false
    @State private var sessionDocument: MoleculePadSessionDocument?
    @State private var showBinaryExporter = false
    @State private var binaryDocument: BinaryFileDocument?
    @State private var binaryContentType: UTType = .png
    @State private var binaryFilename = "MoleculePad Image.png"
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ModelSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
        } detail: {
            ZStack {
                MolecularSceneView(
                    structure: workspace.structure,
                    volume: workspace.volume,
                    settings: workspace.settings,
                    selectedAtomIDs: workspace.selectedAtomIDs,
                    interactions: workspace.interactions,
                    cavities: workspace.cavities,
                    customPseudobonds: workspace.customPseudobonds,
                    revision: workspace.sceneRevision,
                    onSelectAtom: { workspace.selectAtom($0, additive: true) }
                )
                .ignoresSafeArea(edges: .bottom)

                AnnotationCanvasOverlay()
                    .ignoresSafeArea(edges: .bottom)

                if !workspace.isPresentationMode {
                    VStack(spacing: 0) {
                        ViewportHUD()
                        Spacer()
                        CommandBar(showHelp: $showHelp)
                    }
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                workspace.execute("presentation stop")
                            } label: {
                                Label("Exit presentation", systemImage: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                    .padding()
                }

                if workspace.structure == nil && workspace.volume == nil {
                    EmptyWorkspaceView(showImporter: $showImporter, showDatabaseSheet: $showDatabaseSheet)
                }

                if workspace.showInspector && !workspace.isPresentationMode {
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
        .onChange(of: workspace.isPresentationMode) { _, presenting in
            withAnimation(.snappy) { columnVisibility = presenting ? .detailOnly : .all }
        }
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
        .fileExporter(
            isPresented: $showSessionExporter,
            document: sessionDocument,
            contentType: .moleculePadSession,
            defaultFilename: "MoleculePad Session"
        ) { result in
            if case .failure(let error) = result { workspace.errorMessage = error.localizedDescription }
            sessionDocument = nil
        }
        .fileExporter(
            isPresented: $showBinaryExporter,
            document: binaryDocument,
            contentType: binaryContentType,
            defaultFilename: binaryFilename
        ) { result in
            if case .failure(let error) = result { workspace.errorMessage = error.localizedDescription }
            binaryDocument = nil
        }
        .sheet(isPresented: $showDatabaseSheet) { OpenDatabaseSheet() }
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .sheet(isPresented: $showWorkspaceTools) { WorkspaceToolsSheet() }
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
            Button { showDatabaseSheet = true } label: {
                Label("Open database entry", systemImage: "externaldrive.badge.icloud")
            }
            Button { showWorkspaceTools = true } label: {
                Label("Automation and plug-ins", systemImage: "puzzlepiece.extension")
            }
            Button {
                do {
                    sessionDocument = MoleculePadSessionDocument(data: try workspace.encodedSession())
                    showSessionExporter = true
                } catch {
                    workspace.errorMessage = error.localizedDescription
                }
            } label: {
                Label("Save session", systemImage: "square.and.arrow.down")
            }
            Menu {
                Button {
                    exportImage()
                } label: {
                    Label("PNG Image", systemImage: "photo")
                }
                Button {
                    exportScene()
                } label: {
                    Label("3D Scene Archive", systemImage: "cube.transparent")
                }
                Button {
                    exportPDB()
                } label: {
                    Label("PDB Coordinates", systemImage: "atom")
                }
                .disabled(workspace.structure == nil)
                Button {
                    exportMovie()
                } label: {
                    Label("Trajectory Movie", systemImage: "film")
                }
                .disabled(workspace.trajectory == nil)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            Menu {
                Picker("Representation", selection: $workspace.settings.representation) {
                    ForEach(MolecularRepresentation.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Picker("Color", selection: $workspace.settings.colorMode) {
                    ForEach(AtomColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Picker("Labels", selection: $workspace.settings.labelStyle) {
                    ForEach(MolecularLabelStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Lighting", selection: $workspace.settings.lightingPreset) {
                    ForEach(LightingPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("View", selection: $workspace.settings.viewDirection) {
                    ForEach(ViewDirection.allCases) { Text($0.rawValue).tag($0) }
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
            Button {
                workspace.execute("presentation start")
            } label: {
                Label("Present", systemImage: "rectangle.inset.filled.and.person.filled")
            }
            Menu {
                Button(workspace.isDrawingAnnotations ? "Stop Drawing" : "Start Drawing") {
                    workspace.execute(workspace.isDrawingAnnotations ? "annotate stop" : "annotate start")
                }
                Button("Clear 2D Annotations", role: .destructive) {
                    workspace.clearCanvasAnnotations()
                }
                .disabled(workspace.canvasStrokes.isEmpty)
            } label: {
                Label("Annotate", systemImage: "pencil.tip.crop.circle")
            }
            Button(action: workspace.undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
            Button(action: workspace.redo) { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    private var supportedTypes: [UTType] {
        ["pdb", "ent", "cif", "mmcif", "sdf", "mol", "mol2", "xyz", "dcd", "mrc", "map", "ccp4", "nii", "nrrd", "dcm", "dicom", "gz", "moleculepad", "molcmd", "cxc", "molplugin"]
            .compactMap { UTType(filenameExtension: $0) } + [.moleculePadSession, .data]
    }

    private func exportImage() {
        do {
            binaryDocument = BinaryFileDocument(data: try SceneExportService().png(
                structure: workspace.structure,
                volume: workspace.volume,
                settings: workspace.settings,
                selection: workspace.selectedAtomIDs,
                interactions: workspace.interactions,
                cavities: workspace.cavities,
                customPseudobonds: workspace.customPseudobonds
            ))
            binaryContentType = .png
            binaryFilename = "MoleculePad Image.png"
            showBinaryExporter = true
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }

    private func exportScene() {
        do {
            binaryDocument = BinaryFileDocument(data: try SceneExportService().sceneArchive(
                structure: workspace.structure,
                volume: workspace.volume,
                settings: workspace.settings,
                selection: workspace.selectedAtomIDs,
                interactions: workspace.interactions,
                cavities: workspace.cavities,
                customPseudobonds: workspace.customPseudobonds
            ))
            binaryContentType = .moleculePadScene
            binaryFilename = "MoleculePad Scene.scn"
            showBinaryExporter = true
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }

    private func exportPDB() {
        guard let structure = workspace.structure else { return }
        binaryDocument = BinaryFileDocument(data: StructureFileWriter().pdb(structure))
        binaryContentType = .plainText
        binaryFilename = "\(structure.name).pdb"
        showBinaryExporter = true
    }

    private func exportMovie() {
        guard let trajectory = workspace.trajectory else { return }
        workspace.isLoading = true
        workspace.statusMessage = "Rendering trajectory movie…"
        Task {
            defer { workspace.isLoading = false }
            do {
                let data = try await SceneExportService().movie(
                    trajectory: trajectory,
                    settings: workspace.settings
                )
                binaryDocument = BinaryFileDocument(data: data)
                binaryContentType = .mpeg4Movie
                binaryFilename = "MoleculePad Trajectory.mp4"
                showBinaryExporter = true
                workspace.statusMessage = "Trajectory movie ready"
            } catch {
                workspace.errorMessage = error.localizedDescription
                workspace.statusMessage = "Movie export failed"
            }
        }
    }
}

private struct AnnotationCanvasOverlay: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var activePoints: [CanvasPoint] = []

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in workspace.canvasStrokes {
                    draw(stroke.points, color: color(stroke.color), width: stroke.width, in: &context, size: size)
                }
                draw(activePoints, color: .yellow, width: 3, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard workspace.isDrawingAnnotations,
                              proxy.size.width > 0, proxy.size.height > 0 else { return }
                        activePoints.append(CanvasPoint(
                            x: value.location.x / proxy.size.width,
                            y: value.location.y / proxy.size.height
                        ))
                    }
                    .onEnded { _ in
                        guard workspace.isDrawingAnnotations else { return }
                        workspace.addCanvasStroke(activePoints)
                        activePoints = []
                    }
            )
            .allowsHitTesting(workspace.isDrawingAnnotations)
            .accessibilityLabel("2D annotation canvas")
        }
    }

    private func draw(
        _ points: [CanvasPoint], color: Color, width: Double,
        in context: inout GraphicsContext, size: CGSize
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func color(_ components: [Float]) -> Color {
        guard components.count >= 4 else { return .yellow }
        return Color(
            red: Double(components[0]), green: Double(components[1]),
            blue: Double(components[2]), opacity: Double(components[3])
        )
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
                        subtitle: workspace.trajectory.map {
                            "\(structure.atoms.count) atoms · frame \(workspace.trajectoryFrameIndex + 1)/\($0.frameCount)"
                        } ?? "\(structure.atoms.count) atoms · \(structure.bonds.count) bonds",
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
                    Text("Tap up to four atoms, or select groups with Terminal or Copilot")
                        .foregroundStyle(.secondary)
                } else {
                    if workspace.selectedAtoms.count > 8 {
                        Label("\(workspace.selectedAtoms.count) atoms selected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.cyan)
                    }
                    ForEach(Array(workspace.selectedAtoms.prefix(8))) { atom in
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
                    if let angle = workspace.measuredAngle {
                        Label(String(format: "%.2f° angle", angle), systemImage: "angle")
                            .foregroundStyle(.yellow)
                    }
                    if let torsion = workspace.measuredTorsion {
                        Label(String(format: "%.2f° torsion", torsion), systemImage: "rotate.3d")
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
                    Text("Display").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Labels", selection: $workspace.settings.labelStyle) {
                        ForEach(MolecularLabelStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    ColorPicker("Label color", selection: $workspace.settings.labelColor)
                    Picker("Lighting", selection: $workspace.settings.lightingPreset) {
                        ForEach(LightingPreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Saved view", selection: $workspace.settings.viewDirection) {
                        ForEach(ViewDirection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Toggle("Coordinate axes", isOn: $workspace.settings.showAxes)
                    Toggle("Ångström scale bar", isOn: $workspace.settings.showScaleBar)
                    Toggle("Selection arrow", isOn: $workspace.settings.showSelectionArrow)
                    LabeledContent("Near clip") {
                        Slider(value: $workspace.settings.nearClip, in: 0.001...5)
                            .frame(width: 125)
                    }
                    LabeledContent("Far clip") {
                        Slider(value: $workspace.settings.farClip, in: 100...20_000)
                            .frame(width: 125)
                    }
                }

                Divider()

                if let source = workspace.asymmetricUnit, !source.alternateConformations.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Alternate locations").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker(
                            "Coordinates",
                            selection: Binding(
                                get: { workspace.activeAlternateLocation ?? "__primary__" },
                                set: { workspace.showAlternateLocation($0 == "__primary__" ? nil : $0) }
                            )
                        ) {
                            Text("Primary").tag("__primary__")
                            ForEach(source.alternateConformations) { conformation in
                                Text("Location \(conformation.id)").tag(conformation.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()
                }

                if let source = workspace.asymmetricUnit, !source.biologicalAssemblies.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Biological assemblies").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Button("Asymmetric unit") { workspace.showAsymmetricUnit() }
                            .buttonStyle(.bordered)
                        ForEach(source.biologicalAssemblies) { assembly in
                            Button {
                                workspace.showBiologicalAssembly(assembly.id)
                            } label: {
                                HStack {
                                    Text("Assembly \(assembly.id)")
                                    Spacer()
                                    Text("\(assembly.instances.count) copies")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()
                }

                if let trajectory = workspace.trajectory {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Trajectory").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(workspace.trajectoryFrameIndex + 1) / \(trajectory.frameCount)")
                                .font(.caption.monospacedDigit())
                        }
                        Slider(
                            value: Binding(
                                get: { Double(workspace.trajectoryFrameIndex) },
                                set: { workspace.setTrajectoryFrame(Int($0.rounded())) }
                            ),
                            in: 0...Double(max(0, trajectory.frameCount - 1)),
                            step: 1
                        )
                        HStack {
                            Button { workspace.stepTrajectory(-1) } label: { Image(systemName: "backward.frame.fill") }
                            Button { workspace.setTrajectoryPlayback(!workspace.isTrajectoryPlaying) } label: {
                                Image(systemName: workspace.isTrajectoryPlaying ? "pause.fill" : "play.fill")
                            }
                            Button { workspace.stepTrajectory() } label: { Image(systemName: "forward.frame.fill") }
                            Spacer()
                            Text("Multi-model PDB")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Molecular surface").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $workspace.settings.showMolecularSurface).labelsHidden()
                    }
                    Picker("Style", selection: $workspace.settings.molecularSurfaceStyle) {
                        ForEach(MolecularSurfaceStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Color by", selection: $workspace.settings.molecularSurfaceColorMode) {
                        ForEach(MolecularSurfaceColorMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Opacity") {
                        Slider(value: $workspace.settings.molecularSurfaceOpacity, in: 0.05...1)
                            .frame(width: 130)
                    }
                    LabeledContent("Probe") {
                        HStack(spacing: 5) {
                            Slider(
                                value: Binding(
                                    get: { Double(workspace.settings.molecularSurfaceProbeRadius) },
                                    set: { workspace.settings.molecularSurfaceProbeRadius = Float($0) }
                                ),
                                in: 0...3,
                                step: 0.1
                            )
                            Text(String(format: "%.1f Å", workspace.settings.molecularSurfaceProbeRadius))
                                .font(.caption.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                        }
                        .frame(width: 158)
                    }
                    if workspace.settings.molecularSurfaceColorMode == .uniform {
                        ColorPicker("Surface color", selection: $workspace.settings.molecularSurfaceColor)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Density map").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $workspace.settings.showMap).labelsHidden()
                    }
                    Picker("Display", selection: $workspace.settings.volumeDisplayStyle) {
                        ForEach(VolumeDisplayStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
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
                    if workspace.settings.volumeDisplayStyle == .slices {
                        LabeledContent("X slice") { Slider(value: $workspace.settings.sliceX, in: 0...1).frame(width: 130) }
                        LabeledContent("Y slice") { Slider(value: $workspace.settings.sliceY, in: 0...1).frame(width: 130) }
                        LabeledContent("Z slice") { Slider(value: $workspace.settings.sliceZ, in: 0...1).frame(width: 130) }
                    }
                    HStack(spacing: 6) {
                        Button("Stats") { workspace.reportMapStatistics() }
                        Button("Segment") { workspace.segmentMap(threshold: nil) }
                        Button("Fit atoms") { workspace.fitStructureToMap() }
                    }
                    .buttonStyle(.bordered)
                    Button("Rigid fit atoms (translate + rotate)") { workspace.rigidFitStructureToMap() }
                        .buttonStyle(.bordered)
                    if let reference = workspace.referenceVolume {
                        Label("Map reference: \(reference.name)", systemImage: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.mint)
                    }
                    if let metadata = workspace.dicomMetadata {
                        DisclosureGroup("DICOM metadata") {
                            VStack(alignment: .leading, spacing: 5) {
                                if let value = metadata.modality { LabeledContent("Modality", value: value) }
                                if let value = metadata.seriesDescription { LabeledContent("Series", value: value) }
                                if let value = metadata.studyDate { LabeledContent("Study date", value: value) }
                                if let value = metadata.patientName { LabeledContent("Patient", value: value) }
                                if let value = metadata.patientID { LabeledContent("Patient ID", value: value) }
                                LabeledContent("Frames", value: "\(metadata.numberOfFrames)")
                                if let value = metadata.transferSyntaxUID { LabeledContent("Transfer syntax", value: value) }
                            }
                            .font(.caption)
                            .textSelection(.enabled)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Build & refine").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Button("Add H") { workspace.prepareStructure("hydrogens") }
                        Button("Dock Prep") { workspace.prepareStructure("dockprep") }
                        Button("Minimize") { workspace.prepareStructure("minimize") }
                    }
                    .buttonStyle(.bordered)
                    HStack(spacing: 6) {
                        Button("Add bond") { workspace.addBondFromSelection() }
                        Button("Delete bond") { workspace.deleteBondFromSelection() }
                        Button("Delete atoms", role: .destructive) { workspace.deleteSelectedAtoms() }
                    }
                    .buttonStyle(.bordered)
                    Button("Analyze ligand docking pose") { workspace.analyzeDockingPose() }
                        .buttonStyle(.bordered)
                    HStack(spacing: 6) {
                        Button("Model loops") { workspace.modelMissingLoops() }
                        Button("Complete from reference") { workspace.completeFromReferenceModel() }
                    }
                    .buttonStyle(.bordered)
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
                    if let angle = workspace.measuredAngle {
                        LabeledContent("Angle", value: String(format: "%.3f°", angle))
                            .foregroundStyle(.yellow)
                    }
                    if let torsion = workspace.measuredTorsion {
                        LabeledContent("Torsion", value: String(format: "%.3f°", torsion))
                            .foregroundStyle(.yellow)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Analysis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !workspace.interactions.isEmpty {
                            Button("Clear") { workspace.clearInteractions() }
                                .font(.caption)
                        }
                    }
                    HStack(spacing: 6) {
                        Button("H-bonds") { workspace.calculateInteractions(.hydrogenBond) }
                        Button("Contacts") { workspace.calculateInteractions(.contact) }
                        Button("Clashes") { workspace.calculateInteractions(.clash) }
                    }
                    .buttonStyle(.bordered)
                    HStack(spacing: 6) {
                        Button("Cavities") { workspace.reportCavities() }
                        Button("Interfaces") { workspace.reportInterfaces() }
                        Button("Sequence") { workspace.reportSequences() }
                    }
                    .buttonStyle(.bordered)
                    Button("RCSB 3D Similarity") {
                        Task { await workspace.runRCSBStructureSimilarity() }
                    }
                    .buttonStyle(.bordered)
                    if let reference = workspace.referenceStructure {
                        Label("Reference: \(reference.name)", systemImage: "scope")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                    }
                    if let report = workspace.analysisReport {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
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
        VStack(spacing: 0) {
            if !workspace.quickCommands.isEmpty || !workspace.installedPlugins.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspace.quickCommands) { command in
                            Button(command.title) { workspace.runQuickCommand(command) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        ForEach(workspace.installedPlugins) { plugin in
                            ForEach(plugin.commands) { command in
                                Button {
                                    workspace.runPluginCommand(command, pluginName: plugin.name)
                                } label: {
                                    Label(command.title, systemImage: command.symbol ?? "puzzlepiece.extension")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
            }
            if let plan = workspace.copilotPlan {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(plan.summary)
                            .font(.callout)
                        if plan.isActionable {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(plan.commands, id: \.self) { command in
                                        Text(command)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.cyan)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.cyan.opacity(0.12), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    Button(action: workspace.dismissCopilotPlan) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
            }

            HStack(spacing: 10) {
                Picker("Input mode", selection: $workspace.commandInputMode) {
                    ForEach(CommandInputMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode == .copilot ? "sparkles" : "terminal")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                TextField(
                    workspace.commandInputMode == .copilot
                        ? "Ask in plain language — try: show 1CRN as a cartoon"
                        : "Command — try: open 1crn",
                    text: $workspace.commandText
                )
                .font(workspace.commandInputMode == .terminal ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(workspace.commandInputMode == .copilot ? .sentences : .never)
                .autocorrectionDisabled(workspace.commandInputMode == .terminal)
                .onSubmit(workspace.executeCommand)

                Button(action: workspace.executeCommand) {
                    Image(systemName: workspace.commandInputMode == .copilot ? "arrow.up.circle.fill" : "return")
                }
                .disabled(workspace.commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct EmptyWorkspaceView: View {
    @Binding var showImporter: Bool
    @Binding var showDatabaseSheet: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 58, weight: .thin))
                .foregroundStyle(.cyan)
            Text("Start exploring").font(.largeTitle.bold())
            Text("Open a structure or density map from Files, or download an entry from PDB, EMDB, or AlphaFold DB.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack {
                Button("Open File") { showImporter = true }.buttonStyle(.borderedProminent)
                Button("Open Database") { showDatabaseSheet = true }.buttonStyle(.bordered)
            }
        }
        .padding(36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
}

private struct OpenDatabaseSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var source = DatabaseSource.pdb
    @State private var pdbID = ""
    @State private var emdbID = ""
    @State private var alphaFoldID = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Database", selection: $source) {
                    ForEach(DatabaseSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Section {
                    if source == .pdb {
                        TextField("PDB ID (for example 1CRN)", text: $pdbID)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    } else if source == .emdb {
                        TextField("EMDB ID (for example EMD-1001)", text: $emdbID)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                    } else {
                        TextField("UniProt accession (for example P07550)", text: $alphaFoldID)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    Text(source.explanation)
                }

                if source == .emdb {
                    Section {
                        Label("EM maps can be large. MoleculePad downsamples them during import to keep touch interaction responsive.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Open Database Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        let selectedSource = source
                        let identifier = switch source {
                        case .pdb: pdbID
                        case .emdb: emdbID
                        case .alphaFold: alphaFoldID
                        }
                        dismiss()
                        Task {
                            switch selectedSource {
                            case .pdb: await workspace.fetchPDB(id: identifier)
                            case .emdb: await workspace.fetchEMDB(id: identifier)
                            case .alphaFold: await workspace.fetchAlphaFold(id: identifier)
                            }
                        }
                    }
                    .disabled(!isValidIdentifier)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValidIdentifier: Bool {
        let rawValue = switch source {
        case .pdb: pdbID
        case .emdb: emdbID
        case .alphaFold: alphaFoldID
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .pdb { return value.count == 4 }
        if source == .alphaFold {
            return value.range(of: #"^[A-Za-z0-9]{6,12}(?:-\d+)?$"#, options: .regularExpression) != nil
        }
        let digits = value.uppercased()
            .replacingOccurrences(of: "EMD-", with: "")
            .replacingOccurrences(of: "EMD_", with: "")
        return (4...6).contains(digits.count) && digits.allSatisfy(\.isNumber)
    }
}

private enum DatabaseSource: String, CaseIterable, Identifiable {
    case pdb
    case emdb
    case alphaFold

    var id: Self { self }
    var title: String {
        switch self { case .pdb: "PDB"; case .emdb: "EMDB"; case .alphaFold: "AlphaFold" }
    }
    var explanation: String {
        switch self {
        case .pdb: "Downloads atomic coordinates directly from RCSB PDB."
        case .emdb: "Downloads the primary map directly from the EMBL-EBI EMDB archive."
        case .alphaFold: "Uses the official AlphaFold DB API to download the current predicted model for a UniProt accession."
        }
    }
}

private struct WorkspaceToolsSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var backendURL = ""
    @State private var computeURL = ""
    @State private var copilotToken = ""
    @State private var computeToken = ""
    @State private var batchScript = "style cartoon; color chain"
    @State private var showBatchImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-server.example/api/copilot", text: $backendURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Optional endpoint access token", text: $copilotToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Use On-Device") {
                            backendURL = ""
                            workspace.setCopilotBackendURL("")
                        }
                        Spacer()
                        Button("Save") {
                            workspace.setCopilotBackendURL(backendURL)
                            workspace.setCopilotAccessToken(copilotToken)
                        }
                            .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Copilot service")
                } footer: {
                    Text("MoleculePad sends the request and a small model summary to your HTTPS endpoint. API keys stay on your server. Returned commands are checked against the local allow-list before anything runs.")
                }

                Section {
                    TextField("https://your-server.example/api/molecular-compute", text: $computeURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Optional endpoint access token", text: $computeToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Disable") {
                            computeURL = ""
                            workspace.setComputeProviderURL("")
                        }
                        Spacer()
                        Button("Save") {
                            workspace.setComputeProviderURL(computeURL)
                            workspace.setComputeProviderAccessToken(computeToken)
                        }
                            .buttonStyle(.borderedProminent)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Button("Foldseek") { Task { await workspace.runMolecularCompute(.foldseek) } }
                            Button("ESMFold") { Task { await workspace.runMolecularCompute(.esmfold) } }
                            Button("OpenFold") { Task { await workspace.runMolecularCompute(.openfold) } }
                            Button("Boltz") { Task { await workspace.runMolecularCompute(.boltz) } }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Molecular compute provider")
                } footer: {
                    Text("The endpoint owns GPU jobs and credentials. MoleculePad sends a sequence for predictions or PDB coordinates for Foldseek, then validates and opens the returned HTTPS result.")
                }

                Section("Quick buttons") {
                    if workspace.quickCommands.isEmpty {
                        Text("Create one in Terminal with: button add Ribbon = style cartoon")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workspace.quickCommands) { command in
                        HStack {
                            Button(command.title) { workspace.runQuickCommand(command) }
                            Spacer()
                            Text(command.script)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button(role: .destructive) { workspace.removeQuickCommand(id: command.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    TextField("Commands separated by semicolons", text: $batchScript, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...5)
                    Button("Choose Files and Run Batch") { showBatchImporter = true }
                        .buttonStyle(.borderedProminent)
                } header: {
                    Text("Batch processing")
                } footer: {
                    Text("Each selected file is opened in order and receives the same allow-listed command script. Progress appears in the task manager; the final model stays open.")
                }

                Section("Installed plug-ins") {
                    if workspace.installedPlugins.isEmpty {
                        Text("Open a signed-off declarative .molplugin manifest with the main Open button. Plug-ins can add safe command buttons but cannot execute native code.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workspace.installedPlugins) { plugin in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(plugin.name).font(.headline)
                                    Text("Version \(plugin.version) · \(plugin.commands.count) command(s)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) { workspace.removePlugin(id: plugin.id) }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(plugin.commands) { command in
                                        Button(command.title) {
                                            workspace.runPluginCommand(command, pluginName: plugin.name)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    if workspace.taskItems.isEmpty {
                        Text("Downloads, searches, and server Copilot requests will appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workspace.taskItems) { item in
                        HStack(alignment: .top) {
                            Image(systemName: taskSymbol(item.state))
                                .foregroundStyle(taskColor(item.state))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text("\(item.state.rawValue) · \(item.detail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Task manager")
                        Spacer()
                        if workspace.taskItems.contains(where: { $0.state != .running }) {
                            Button("Clear Finished") { workspace.clearFinishedTasks() }
                                .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Automation & Plug-ins")
            .toolbar { Button("Done") { dismiss() } }
            .onAppear {
                backendURL = workspace.copilotBackendURLString
                computeURL = workspace.computeProviderURLString
                copilotToken = workspace.copilotAccessToken
                computeToken = workspace.computeProviderAccessToken
            }
            .fileImporter(
                isPresented: $showBatchImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): Task { await workspace.runBatch(urls, script: batchScript) }
                case .failure(let error): workspace.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func taskSymbol(_ state: WorkspaceTaskState) -> String {
        switch state {
        case .running: "clock.arrow.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func taskColor(_ state: WorkspaceTaskState) -> Color {
        switch state {
        case .running: .cyan
        case .completed: .green
        case .failed: .red
        }
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
                    Label("Tap two, three, or four atoms for distance, angle, or torsion", systemImage: "ruler")
                }
                Section("Commands") {
                    command("open 1crn", "Fetch a PDB structure")
                    command("open emd-1001", "Fetch an EMDB density map")
                    command("alphafold P07550", "Fetch the current AlphaFold DB prediction")
                    command("blast protein", "Run the first chain through NCBI protein BLAST")
                    command("similar current", "Find globally similar structures with RCSB")
                    command("foldseek", "Search with the configured Foldseek provider")
                    command("compute esmfold", "Predict the current sequence with a configured provider")
                    command("style cartoon", "Show helices, sheet arrows, and coils")
                    command("style spacefill", "Change representation")
                    command("color chain", "Color atoms by chain")
                    command("label residues", "Add camera-facing residue labels")
                    command("lighting dramatic", "Switch lighting preset")
                    command("view top", "Use a saved orthographic direction")
                    command("axes show", "Show coordinate axes")
                    command("scalebar show", "Show an Ångström scale reference")
                    command("arrow show", "Draw an arrow between two selected atoms")
                    command("clip near 0.1", "Set the camera near clipping plane")
                    command("surface show", "Build a solvent-accessible molecular surface")
                    command("surface style mesh", "Show the molecular surface as a mesh")
                    command("surface color bfactor", "Color the surface by an atomic property")
                    command("surface opacity 0.7", "Adjust molecular-surface transparency")
                    command("surface level 0.8", "Set the map contour")
                    command("map style volume", "Show a solid density-volume cloud")
                    command("map style slices", "Show orthogonal map slices")
                    command("map smooth 1", "Apply a separable box/Gaussian-like filter")
                    command("map sharpen 1", "Apply unsharp-mask sharpening")
                    command("map zone 4", "Keep map values near selected atoms")
                    command("map stats", "Report map statistics")
                    command("map segment", "Find connected regions above the contour")
                    command("map reference set", "Save the current grid for comparison")
                    command("map difference", "Subtract the saved map grid")
                    command("fit map", "Optimize structure translation into density")
                    command("fit map rigid", "Optimize structure rotation and translation into density")
                    command("fit maps", "Translate the map onto its saved reference")
                    command("trajectory play", "Animate a multi-model PDB")
                    command("trajectory frame 12", "Jump to a coordinate frame")
                    command("assembly 1", "Build a deposited biological assembly")
                    command("assembly asymmetric", "Return to the asymmetric unit")
                    command("altloc B", "Switch to alternate-location coordinates")
                    command("altloc primary", "Return to primary coordinates")
                    command("hide map", "Hide the density map")
                    command("show atoms", "Show the atomic model")
                    command("select chain A", "Select every atom in chain A")
                    command("select residue 42", "Select a residue by number")
                    command("select element O", "Select atoms by element")
                    command("select ligand", "Select non-water heteroatoms")
                    command("hbonds", "Find and display hydrogen-bond pseudobonds")
                    command("contacts", "Find close nonbonded contacts")
                    command("clashes", "Find van der Waals overlaps")
                    command("cavities", "Detect and display enclosed cavities")
                    command("interfaces", "Analyze contacts between chains")
                    command("measure area", "Estimate area for the selection or model")
                    command("measure centroid", "Report a geometric centroid")
                    command("measure plane", "Fit a plane through selected atoms")
                    command("sequence", "Extract polymer sequences")
                    command("conservation", "Calculate chain-sequence conservation")
                    command("align chains A B", "Globally align two chain sequences")
                    command("reference set", "Save the current structure for comparison")
                    command("rmsd reference", "Fit and report RMSD against the reference")
                    command("match reference", "Superpose the current structure onto the reference")
                    command("undo / redo", "Move through molecular edit history")
                    command("delete selected", "Delete selected atoms")
                    command("bond add", "Add a bond between two selected atoms")
                    command("mutate ALA", "Rename the selected residue")
                    command("atom add C 0 0 0", "Build an atom at Cartesian coordinates")
                    command("addh", "Add simple polar hydrogens")
                    command("charges", "Assign simple partial charges")
                    command("dockprep", "Remove waters, add hydrogens, and assign charges")
                    command("minimize", "Relax bond lengths")
                    command("torsion 60", "Rotate around the first two selected atoms")
                    command("rotamer 60", "Rotate the selected side chain")
                    command("tug 1 0 0", "Move selected atoms by an Ångström vector")
                    command("dock analyze", "Report ligand contacts and clashes")
                    command("model loops", "Build backbone atoms across numbered residue gaps")
                    command("model reference", "Complete aligned atoms from the saved reference")
                    command("pseudobond add", "Connect the first two selected atoms")
                    command("annotate start", "Draw a touch or Apple Pencil overlay")
                    command("alias ribbon style cartoon", "Create a reusable command alias")
                    command("button add Ribbon :: style cartoon", "Create a reusable quick button")
                    command("scene save overview", "Save all current visual settings")
                    command("presentation start", "Enter a clean full-screen presentation")
                }
                Section("Copilot examples") {
                    command("Download 1CRN and show it as a cartoon", "Fetch and restyle a structure")
                    command("Color every chain differently", "Use plain-language coloring")
                    command("Show a transparent molecular surface as a mesh", "Build and style a molecular surface")
                    command("Hide the map and clear my selection", "Perform multiple actions at once")
                    command("Select chain A", "Select a molecular group using everyday language")
                    Text("Copilot only runs MoleculePad’s supported, allow-listed commands. Switch to Terminal for exact command syntax.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Supported files") {
                    Text("PDB/mmCIF structures, SDF/MOL, MOL2, XYZ and DCD trajectories, MRC/CCP4 maps, NIfTI/NRRD/DICOM medical volumes, MoleculePad sessions (.moleculepad), declarative plug-ins (.molplugin), and command scripts (.molcmd/.cxc). Large maps are downsampled on import for interactive performance.")
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
