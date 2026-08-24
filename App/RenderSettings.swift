import SwiftUI

enum MolecularRepresentation: String, CaseIterable, Identifiable {
    case ballAndStick = "Ball & Stick"
    case spacefill = "Spacefill"
    case sticks = "Sticks"
    case cartoon = "Cartoon"
    case backbone = "Backbone"

    var id: Self { self }
}

enum AtomColorMode: String, CaseIterable, Identifiable {
    case element = "Element"
    case chain = "Chain"
    case residue = "Residue"
    case monochrome = "Mono"

    var id: Self { self }
}

struct RenderSettings: Equatable {
    var representation: MolecularRepresentation = .ballAndStick
    var colorMode: AtomColorMode = .element
    var atomScale: Double = 1
    var bondScale: Double = 1
    var showAtoms = true
    var showMap = true
    var mapThreshold: Float = 0
    var mapOpacity: Double = 0.52
    var mapWireframe = false
    var mapColor = Color(red: 0.14, green: 0.78, blue: 0.94)
    var backgroundColor = Color(red: 0.025, green: 0.035, blue: 0.055)
    var nearClip: Double = 0.1
}
