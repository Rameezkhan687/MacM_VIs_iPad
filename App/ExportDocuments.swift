import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let moleculePadScene = UTType(exportedAs: "app.moleculepad.scene", conformingTo: .data)
}

struct BinaryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .mpeg4Movie, .moleculePadScene, .plainText, .data] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let value = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
