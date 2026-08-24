import Foundation
import Testing
@testable import MoleculePadCore

@Suite struct DCDParserTests {
    @Test func parsesLittleEndianFramesAgainstTopology() throws {
        let topology = MolecularStructure(
            name: "Topology",
            atoms: [
                Atom(id: 0, serial: 1, name: "C", element: "C", residueName: "LIG", residueNumber: 1, chainID: "A", position: .zero),
                Atom(id: 1, serial: 2, name: "O", element: "O", residueName: "LIG", residueNumber: 1, chainID: "A", position: .zero)
            ],
            bonds: [Bond(atom1: 0, atom2: 1)]
        )
        var header = Data("CORD".utf8)
        header.append(int32(2))
        header.append(Data(repeating: 0, count: 76))
        let title = int32(1) + padded("MoleculePad DCD test", count: 80)
        var data = record(header) + record(title) + record(int32(2))
        data += record(floats([1, 2])) + record(floats([3, 4])) + record(floats([5, 6]))
        data += record(floats([7, 8])) + record(floats([9, 10])) + record(floats([11, 12]))

        let trajectory = try DCDParser().parse(data, topology: topology)
        #expect(trajectory.frameCount == 2)
        #expect(trajectory.frames[0].atoms[1].position == Vector3(x: 2, y: 4, z: 6))
        #expect(trajectory.frames[1].atoms[0].position == Vector3(x: 7, y: 9, z: 11))
        #expect(trajectory.frames[1].bonds.count == 1)
    }

    @Test func rejectsMismatchedTopology() throws {
        var header = Data("CORD".utf8)
        header.append(int32(1))
        header.append(Data(repeating: 0, count: 76))
        let data = record(header) + record(int32(0)) + record(int32(2))
        let topology = MolecularStructure(
            name: "One atom",
            atoms: [Atom(id: 0, serial: 1, name: "C", element: "C", residueName: "LIG", residueNumber: 1, chainID: "A", position: .zero)],
            bonds: []
        )
        #expect(throws: MolecularError.self) { try DCDParser().parse(data, topology: topology) }
    }

    private func record(_ payload: Data) -> Data { int32(Int32(payload.count)) + payload + int32(Int32(payload.count)) }
    private func int32(_ value: Int32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: 4)
    }
    private func floats(_ values: [Float]) -> Data {
        values.reduce(into: Data()) { output, input in
            var bits = input.bitPattern.littleEndian
            output.append(Data(bytes: &bits, count: 4))
        }
    }
    private func padded(_ string: String, count: Int) -> Data {
        var result = Data(string.utf8.prefix(count))
        if result.count < count { result.append(Data(repeating: 0, count: count - result.count)) }
        return result
    }
}
