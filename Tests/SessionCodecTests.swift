import Foundation
import Testing
@testable import MoleculePadCore

@Suite struct SessionCodecTests {
    @Test func roundTripsStructureVolumeAndWorkspaceState() throws {
        let structure = MolecularStructure(
            name: "Session model",
            atoms: [Atom(
                id: 0, serial: 1, name: "CA", element: "C",
                residueName: "GLY", residueNumber: 1, chainID: "A",
                position: Vector3(x: 1, y: 2, z: 3), partialCharge: 0.2
            )],
            bonds: []
        )
        let volume = VolumeMap(
            name: "Session map",
            dimensions: (2, 1, 1),
            origin: .zero,
            spacing: Vector3(x: 1, y: 1, z: 1),
            values: [0, 2]
        )
        let appearance = SessionAppearance(
            representation: "Cartoon", colorMode: "Chain", surfaceStyle: "Mesh",
            labelStyle: "Residues", lightingPreset: "Studio", viewDirection: "Top",
            volumeDisplayStyle: "Isosurface", atomScale: 1, bondScale: 1,
            showAtoms: true, showMolecularSurface: true, surfaceOpacity: 0.7,
            surfaceProbeRadius: 1.4, showMap: true, mapThreshold: 1,
            mapOpacity: 0.5, mapWireframe: false, showAxes: true,
            showScaleBar: true, showSelectionArrow: false, nearClip: 0.1,
            farClip: 10_000, molecularSurfaceColor: [0, 1, 1, 1],
            mapColor: [0, 1, 0, 1], labelColor: [1, 1, 1, 1],
            backgroundColor: [0, 0, 0, 1]
        )
        let session = MoleculePadSession(
            structure: structure,
            volume: SessionVolume(volume),
            selection: [0],
            appearance: appearance,
            aliases: ["ribbon": "style cartoon"],
            scenes: [SessionScene(name: "top", appearance: appearance)]
        )

        let codec = SessionCodec()
        let restored = try codec.decode(codec.encode(session))
        #expect(restored.structure?.atoms.first?.partialCharge == 0.2)
        #expect(restored.volume?.volumeMap?.values == [0, 2])
        #expect(restored.selection == [0])
        #expect(restored.aliases["ribbon"] == "style cartoon")
        #expect(restored.scenes.first?.name == "top")
    }

    @Test func rejectsUnsupportedVersion() throws {
        let appearance = SessionAppearance(
            representation: "Cartoon", colorMode: "Chain", surfaceStyle: "Solid",
            labelStyle: "None", lightingPreset: "Studio", viewDirection: "Front",
            volumeDisplayStyle: "Isosurface", atomScale: 1, bondScale: 1,
            showAtoms: true, showMolecularSurface: false, surfaceOpacity: 0.7,
            surfaceProbeRadius: 1.4, showMap: true, mapThreshold: 0,
            mapOpacity: 0.5, mapWireframe: false, showAxes: false,
            showScaleBar: false, showSelectionArrow: false, nearClip: 0.1,
            farClip: 10_000, molecularSurfaceColor: [], mapColor: [],
            labelColor: [], backgroundColor: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(MoleculePadSession(
            formatVersion: 99, structure: nil, volume: nil,
            selection: [], appearance: appearance
        ))
        #expect(throws: MolecularError.self) { try SessionCodec().decode(data) }
    }
}
