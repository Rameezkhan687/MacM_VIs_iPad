import Foundation

public struct CustomPseudobond: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let atom1: Int
    public let atom2: Int
    public var group: String
    public var color: [Float]

    public init(
        id: UUID = UUID(), atom1: Int, atom2: Int,
        group: String = "Custom", color: [Float] = [0.95, 0.45, 0.1, 1]
    ) {
        self.id = id
        self.atom1 = atom1
        self.atom2 = atom2
        self.group = group
        self.color = color
    }
}

public struct CanvasPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }
}

public struct CanvasStroke: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var points: [CanvasPoint]
    public var color: [Float]
    public var width: Double

    public init(
        id: UUID = UUID(), points: [CanvasPoint],
        color: [Float] = [1, 0.75, 0.1, 1], width: Double = 3
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.width = width
    }
}
