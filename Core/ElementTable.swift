import Foundation

public enum ElementTable {
    private static let radii: [String: Float] = [
        "H": 1.20, "C": 1.70, "N": 1.55, "O": 1.52, "F": 1.47,
        "P": 1.80, "S": 1.80, "CL": 1.75, "FE": 1.80, "MG": 1.73,
        "ZN": 1.39, "CA": 1.94, "NA": 2.27, "K": 2.75
    ]

    private static let covalentRadii: [String: Float] = [
        "H": 0.31, "C": 0.76, "N": 0.71, "O": 0.66, "F": 0.57,
        "P": 1.07, "S": 1.05, "CL": 1.02, "FE": 1.32, "MG": 1.41,
        "ZN": 1.22, "CA": 1.76, "NA": 1.66, "K": 2.03
    ]

    public static func normalized(_ element: String) -> String {
        element.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func vanDerWaalsRadius(for element: String) -> Float {
        radii[normalized(element)] ?? 1.70
    }

    public static func covalentRadius(for element: String) -> Float {
        covalentRadii[normalized(element)] ?? 0.77
    }

    public static func inferredElement(atomName: String) -> String {
        let letters = atomName.filter(\.isLetter).uppercased()
        if letters.count >= 2 {
            let two = String(letters.prefix(2))
            if radii[two] != nil { return two }
        }
        return String(letters.prefix(1))
    }
}
