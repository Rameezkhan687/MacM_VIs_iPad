import SwiftUI

enum MolecularRepresentation: String, CaseIterable, Identifiable {
    case ballAndStick = "Ball & Stick"
    case spacefill = "Spacefill"
    case sticks = "Sticks"
    case cartoon = "Cartoon"
    case backbone = "Backbone"
    case nucleotides = "Nucleotides"
    case glycans = "Glycans"
    case thermal = "B-Factor Ellipsoids"

    var id: Self { self }
}

enum AtomColorMode: String, CaseIterable, Identifiable {
    case element = "Element"
    case chain = "Chain"
    case residue = "Residue"
    case monochrome = "Mono"

    var id: Self { self }
}

enum MolecularSurfaceStyle: String, CaseIterable, Identifiable {
    case solid = "Solid"
    case mesh = "Mesh"
    case dots = "Dots"

    var id: Self { self }
}

enum MolecularSurfaceColorMode: String, CaseIterable, Identifiable {
    case uniform = "Uniform"
    case element = "Element"
    case chain = "Chain"
    case residue = "Residue"
    case bFactor = "B-Factor"
    case charge = "Charge"

    var id: Self { self }
}

enum MolecularLabelStyle: String, CaseIterable, Identifiable {
    case none = "None"
    case selected = "Selected"
    case atoms = "Atoms"
    case residues = "Residues"
    case chains = "Chains"

    var id: Self { self }
}

enum LightingPreset: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case soft = "Soft"
    case flat = "Flat"
    case dramatic = "Dramatic"

    var id: Self { self }
}

enum ViewDirection: String, CaseIterable, Identifiable {
    case front = "Front"
    case back = "Back"
    case left = "Left"
    case right = "Right"
    case top = "Top"
    case bottom = "Bottom"

    var id: Self { self }
}

enum VolumeDisplayStyle: String, CaseIterable, Identifiable {
    case surface = "Isosurface"
    case volume = "Solid Volume"
    case slices = "Orthogonal Slices"

    var id: Self { self }
}

struct RenderSettings: Equatable {
    var representation: MolecularRepresentation = .ballAndStick
    var colorMode: AtomColorMode = .element
    var atomScale: Double = 1
    var bondScale: Double = 1
    var showAtoms = true
    var showMolecularSurface = false
    var molecularSurfaceStyle: MolecularSurfaceStyle = .solid
    var molecularSurfaceColorMode: MolecularSurfaceColorMode = .uniform
    var molecularSurfaceOpacity: Double = 0.72
    var molecularSurfaceColor = Color(red: 0.38, green: 0.72, blue: 0.94)
    var molecularSurfaceProbeRadius: Float = 1.4
    var labelStyle: MolecularLabelStyle = .none
    var labelColor = Color.white
    var showAxes = false
    var showScaleBar = false
    var showSelectionArrow = false
    var lightingPreset: LightingPreset = .studio
    var viewDirection: ViewDirection = .front
    var showMap = true
    var volumeDisplayStyle: VolumeDisplayStyle = .surface
    var mapThreshold: Float = 0
    var mapOpacity: Double = 0.52
    var mapWireframe = false
    var mapColor = Color(red: 0.14, green: 0.78, blue: 0.94)
    var sliceX: Double = 0.5
    var sliceY: Double = 0.5
    var sliceZ: Double = 0.5
    var backgroundColor = Color(red: 0.025, green: 0.035, blue: 0.055)
    var nearClip: Double = 0.1
    var farClip: Double = 10_000
}
