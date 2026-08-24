import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let moleculePadSession = UTType(exportedAs: "app.moleculepad.session", conformingTo: .json)
}

struct MoleculePadSessionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.moleculePadSession, .json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
