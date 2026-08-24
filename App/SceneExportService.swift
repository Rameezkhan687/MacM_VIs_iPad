import AVFoundation
import CoreGraphics
import Foundation
import SceneKit
import UIKit

@MainActor
struct SceneExportService {
    func png(
        structure: MolecularStructure?, volume: VolumeMap?, settings: RenderSettings,
        selection: [Int], interactions: [MolecularInteraction], cavities: [MolecularCavity]
        , customPseudobonds: [CustomPseudobond] = []
    ) throws -> Data {
        let image = MolecularSceneBuilder.snapshot(
            structure: structure, volume: volume, settings: settings,
            selection: selection, interactions: interactions, cavities: cavities,
            customPseudobonds: customPseudobonds
        )
        guard let data = image.pngData() else {
            throw MolecularError.invalidStructure("The viewport image could not be encoded.")
        }
        return data
    }

    func sceneArchive(
        structure: MolecularStructure?, volume: VolumeMap?, settings: RenderSettings,
        selection: [Int], interactions: [MolecularInteraction], cavities: [MolecularCavity]
        , customPseudobonds: [CustomPseudobond] = []
    ) throws -> Data {
        let scene = MolecularSceneBuilder.exportScene(
            structure: structure, volume: volume, settings: settings,
            selection: selection, interactions: interactions, cavities: cavities,
            customPseudobonds: customPseudobonds
        )
        return try NSKeyedArchiver.archivedData(withRootObject: scene, requiringSecureCoding: true)
    }

    func movie(
        trajectory: MolecularTrajectory,
        settings: RenderSettings,
        interactions: [MolecularInteraction] = [],
        cavities: [MolecularCavity] = [],
        framesPerSecond: Int = 24
    ) async throws -> Data {
        guard !trajectory.frames.isEmpty else {
            throw MolecularError.invalidStructure("Open a trajectory before exporting a movie.")
        }
        let width = 1024
        let height = 1024
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoleculePad-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else {
            throw MolecularError.invalidStructure("The video encoder is unavailable.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? MolecularError.invalidStructure("Movie export could not start.")
        }
        writer.startSession(atSourceTime: .zero)

        for (index, structure) in trajectory.frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let image = MolecularSceneBuilder.snapshot(
                structure: structure, volume: nil, settings: settings, selection: [],
                interactions: interactions, cavities: cavities,
                size: CGSize(width: width, height: height)
            )
            guard let buffer = pixelBuffer(from: image, width: width, height: height),
                  adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: CMTimeScale(framesPerSecond))) else {
                writer.cancelWriting()
                throw writer.error ?? MolecularError.invalidStructure("A trajectory frame could not be encoded.")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? MolecularError.invalidStructure("Movie export failed.")
        }
        return try Data(contentsOf: outputURL)
    }

    private func pixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes, &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ), let cgImage = image.cgImage else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
