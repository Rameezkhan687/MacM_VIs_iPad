import Testing
@testable import MoleculePadCore

struct MolecularSurfaceGridBuilderTests {
    @Test func buildsSignedDistanceGrid() throws {
        let grid = try #require(MolecularSurfaceGridBuilder().build(
            structure: SampleData.miniProtein,
            maximumDimension: 32
        ))

        #expect(grid.dimensions.x <= 32)
        #expect(grid.dimensions.y <= 32)
        #expect(grid.dimensions.z <= 32)
        #expect(grid.minimum < 0)
        #expect(grid.maximum > 0)
        #expect(grid.values.contains { $0 >= 0 })
        #expect(grid.values.contains { $0 < 0 })
    }
}
