import Testing
@testable import MoleculePadCore

struct VolumeProcessingTests {
    private let processor = VolumeProcessor()

    private var map: VolumeMap {
        var values = [Float](repeating: 0, count: 5 * 5 * 5)
        values[2 + 5 * (2 + 5 * 2)] = 10
        values[3 + 5 * (2 + 5 * 2)] = 8
        return VolumeMap(
            name: "Peak",
            dimensions: (5, 5, 5),
            origin: .zero,
            spacing: Vector3(x: 1, y: 1, z: 1),
            values: values
        )
    }

    @Test func calculatesStatisticsAndFilters() {
        let stats = processor.statistics(map)
        let smooth = processor.smoothed(map)
        let sharpen = processor.sharpened(map)

        #expect(stats.maximum == 10)
        #expect(stats.standardDeviation > 0)
        #expect(smooth.maximum < map.maximum)
        #expect(sharpen.maximum > map.maximum)
    }

    @Test func cropsZonesDifferencesAndSegments() throws {
        let crop = try #require(processor.cropped(map, x: 1...3, y: 1...3, z: 1...3))
        let atom = Atom(id: 0, serial: 1, name: "C", element: "C", residueName: "LIG", residueNumber: 1, chainID: "L", position: Vector3(x: 2, y: 2, z: 2))
        let zone = processor.zoned(map, around: [atom], radius: 1.2)
        let difference = processor.difference(map, map)
        let segments = processor.segments(map, threshold: 5, minimumVoxels: 1)

        #expect(crop.dimensions.x == 3)
        #expect(zone.maximum == 10)
        #expect(difference?.maximum == 0)
        #expect(segments.count == 1)
        #expect(segments[0].voxelCount == 2)
    }

    @Test func fitsAtomsToPeak() throws {
        let atom = Atom(id: 0, serial: 1, name: "C", element: "C", residueName: "LIG", residueNumber: 1, chainID: "L", position: Vector3(x: 1, y: 2, z: 2))
        let fit = try #require(processor.fitAtoms([atom], to: map))
        #expect(fit.translation.x > 0)
        #expect(fit.score > 0)
    }

    @Test func fitsTranslatedMap() throws {
        let moving = VolumeMap(
            name: "Moved",
            dimensions: map.dimensions,
            origin: Vector3(x: 2, y: 0, z: 0),
            spacing: map.spacing,
            values: map.values
        )
        let fit = try #require(processor.fitMap(moving, to: map))
        #expect(fit.translation.x < -1)
    }

    @Test func rigidFitReturnsRotationAndImprovesDensityScore() throws {
        var values = [Float](repeating: 0, count: 7 * 7 * 7)
        values[3 + 7 * (2 + 7 * 3)] = 10
        values[3 + 7 * (4 + 7 * 3)] = 10
        let target = VolumeMap(
            name: "Rotated target", dimensions: (7, 7, 7), origin: .zero,
            spacing: Vector3(x: 1, y: 1, z: 1), values: values
        )
        let atoms = [
            Atom(id: 0, serial: 1, name: "C1", element: "C", residueName: "LIG", residueNumber: 1, chainID: "L", position: Vector3(x: 2, y: 3, z: 3)),
            Atom(id: 1, serial: 2, name: "C2", element: "C", residueName: "LIG", residueNumber: 1, chainID: "L", position: Vector3(x: 4, y: 3, z: 3))
        ]
        let fit = try #require(processor.rigidFitAtoms(atoms, to: target))
        #expect(fit.score > 1)
        #expect(abs(fit.rotationDegrees.z) >= 45)
    }
}
