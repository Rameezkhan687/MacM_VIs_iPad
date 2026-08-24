import Foundation

public struct SessionVolume: Codable, Sendable {
    public let name: String
    public let dimensions: [Int]
    public let origin: Vector3
    public let spacing: Vector3
    public let values: [Float]

    public init(_ volume: VolumeMap) {
        name = volume.name
        dimensions = [volume.dimensions.x, volume.dimensions.y, volume.dimensions.z]
        origin = volume.origin
        spacing = volume.spacing
        values = volume.values
    }

    public var volumeMap: VolumeMap? {
        guard dimensions.count == 3,
              dimensions.allSatisfy({ $0 > 0 }),
              dimensions.reduce(1, *) == values.count else { return nil }
        return VolumeMap(
            name: name,
            dimensions: (dimensions[0], dimensions[1], dimensions[2]),
            origin: origin,
            spacing: spacing,
            values: values
        )
    }
}

public struct SessionAppearance: Codable, Sendable {
    public var representation: String
    public var colorMode: String
    public var surfaceStyle: String
    public var surfaceColorMode: String?
    public var labelStyle: String
    public var lightingPreset: String
    public var viewDirection: String
    public var volumeDisplayStyle: String
    public var atomScale: Double
    public var bondScale: Double
    public var showAtoms: Bool
    public var showMolecularSurface: Bool
    public var surfaceOpacity: Double
    public var surfaceProbeRadius: Float
    public var showMap: Bool
    public var mapThreshold: Float
    public var mapOpacity: Double
    public var mapWireframe: Bool
    public var showAxes: Bool
    public var showScaleBar: Bool
    public var showSelectionArrow: Bool
    public var nearClip: Double
    public var farClip: Double
    public var molecularSurfaceColor: [Double]
    public var mapColor: [Double]
    public var labelColor: [Double]
    public var backgroundColor: [Double]

    public init(
        representation: String,
        colorMode: String,
        surfaceStyle: String,
        surfaceColorMode: String? = nil,
        labelStyle: String,
        lightingPreset: String,
        viewDirection: String,
        volumeDisplayStyle: String,
        atomScale: Double,
        bondScale: Double,
        showAtoms: Bool,
        showMolecularSurface: Bool,
        surfaceOpacity: Double,
        surfaceProbeRadius: Float,
        showMap: Bool,
        mapThreshold: Float,
        mapOpacity: Double,
        mapWireframe: Bool,
        showAxes: Bool,
        showScaleBar: Bool,
        showSelectionArrow: Bool,
        nearClip: Double,
        farClip: Double,
        molecularSurfaceColor: [Double],
        mapColor: [Double],
        labelColor: [Double],
        backgroundColor: [Double]
    ) {
        self.representation = representation; self.colorMode = colorMode; self.surfaceStyle = surfaceStyle
        self.surfaceColorMode = surfaceColorMode
        self.labelStyle = labelStyle; self.lightingPreset = lightingPreset; self.viewDirection = viewDirection
        self.volumeDisplayStyle = volumeDisplayStyle; self.atomScale = atomScale; self.bondScale = bondScale
        self.showAtoms = showAtoms; self.showMolecularSurface = showMolecularSurface
        self.surfaceOpacity = surfaceOpacity; self.surfaceProbeRadius = surfaceProbeRadius
        self.showMap = showMap; self.mapThreshold = mapThreshold; self.mapOpacity = mapOpacity
        self.mapWireframe = mapWireframe; self.showAxes = showAxes; self.showScaleBar = showScaleBar
        self.showSelectionArrow = showSelectionArrow; self.nearClip = nearClip; self.farClip = farClip
        self.molecularSurfaceColor = molecularSurfaceColor; self.mapColor = mapColor
        self.labelColor = labelColor; self.backgroundColor = backgroundColor
    }
}

public struct SessionScene: Codable, Sendable {
    public let name: String
    public let appearance: SessionAppearance

    public init(name: String, appearance: SessionAppearance) {
        self.name = name
        self.appearance = appearance
    }
}

public struct MoleculePadSession: Codable, Sendable {
    public let formatVersion: Int
    public let createdAt: Date
    public let structure: MolecularStructure?
    public let volume: SessionVolume?
    public let selection: [Int]
    public let appearance: SessionAppearance
    public let aliases: [String: String]
    public let scenes: [SessionScene]
    public let plugins: [MoleculePadPluginManifest]?
    public let quickCommands: [MoleculePadQuickCommand]?
    public let customPseudobonds: [CustomPseudobond]?
    public let canvasStrokes: [CanvasStroke]?

    public init(
        formatVersion: Int = 1,
        createdAt: Date = Date(),
        structure: MolecularStructure?,
        volume: SessionVolume?,
        selection: [Int],
        appearance: SessionAppearance,
        aliases: [String: String] = [:],
        scenes: [SessionScene] = [],
        plugins: [MoleculePadPluginManifest] = [],
        quickCommands: [MoleculePadQuickCommand] = [],
        customPseudobonds: [CustomPseudobond] = [],
        canvasStrokes: [CanvasStroke] = []
    ) {
        self.formatVersion = formatVersion; self.createdAt = createdAt; self.structure = structure
        self.volume = volume; self.selection = selection; self.appearance = appearance
        self.aliases = aliases; self.scenes = scenes
        self.plugins = plugins; self.quickCommands = quickCommands
        self.customPseudobonds = customPseudobonds; self.canvasStrokes = canvasStrokes
    }
}

public struct SessionCodec: Sendable {
    public init() {}

    public func encode(_ session: MoleculePadSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }

    public func decode(_ data: Data) throws -> MoleculePadSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(MoleculePadSession.self, from: data)
        guard session.formatVersion == 1 else {
            throw MolecularError.invalidStructure("Unsupported MoleculePad session version \(session.formatVersion).")
        }
        return session
    }
}
