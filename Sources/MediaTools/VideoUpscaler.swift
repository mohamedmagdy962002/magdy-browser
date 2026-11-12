import AVFoundation
import CoreImage
import Foundation

/// Re-encodes a video at a higher resolution using a Lanczos resample.
final class VideoUpscaler {
    enum UpscaleError: LocalizedError {
        case noVideoTrack
        case cannotCreateWriter
        case cannotAddOutput
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "This file has no video track."
            case .cannotCreateWriter: return "Could not open the output file."
            case .cannotAddOutput: return "Could not read the video track."
            case .encodingFailed(let message): return message
            }
        }
    }

    private static let context = CIContext()

    static func upscale(
        source: URL,
        destination: URL,
        scale: Double,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, UpscaleError>) -> Void
    ) {
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else {
            completion(.failure(.noVideoTrack))
            return
        }

        let naturalSize = track.naturalSize
        let targetSize = CGSize(
            width: max(2, (naturalSize.width * scale).rounded()),
            height: max(2, (naturalSize.height * scale).rounded())
        )
        let duration = asset.duration.seconds

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            completion(.failure(.cannotAddOutput))
            return
        }
        let videoOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            completion(.failure(.cannotAddOutput))
            return
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        } catch {
            completion(.failure(.cannotCreateWriter))
            return
        }

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(targetSize.width),
                AVVideoHeightKey: Int(targetSize.height)
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = track.preferredTransform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(targetSize.width),
                kCVPixelBufferHeightKey as String: Int(targetSize.height)
            ]
        )

        guard writer.canAdd(videoInput) else {
            completion(.failure(.cannotCreateWriter))
            return
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if let audioOutput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            completion(.failure(.encodingFailed(writer.error?.localizedDescription ?? "Writer failed to start.")))
            return
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            completion(.failure(.encodingFailed(reader.error?.localizedDescription ?? "Reader failed to start.")))
            return
        }

        let queue = DispatchQueue(label: "com.magdy.upscale")
        var frameIndex: Int64 = 0

        videoInput.requestMediaDataWhenReady(on: queue) {
            while videoInput.isReadyForMoreMediaData {
                guard let sample = videoOutput.copyNextSampleBuffer() else {
                    videoInput.markAsFinished()
                    // Do not cancel the reader: the audio pass-through still needs it.
                    break
                }
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                guard let scaled = VideoUpscaler.resample(imageBuffer: imageBuffer, to: targetSize) else { continue }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                if adaptor.append(scaled, withPresentationTime: presentationTime) {
                    frameIndex += 1
                }
                if duration > 0 {
                    let ratio = presentationTime.seconds / duration
                    progress(min(1, max(0, ratio)))
                }
            }
        }

        // Audio passthrough: copy compressed samples straight across.
        if let audioOutput, let audioInput {
            let audioQueue = DispatchQueue(label: "com.magdy.upscale.audio")
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        break
                    }
                    if !audioInput.append(sample) { break }
                }
            }
        }

        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(destination))
            } else {
                completion(.failure(.encodingFailed(writer.error?.localizedDescription ?? "Encoding failed.")))
            }
        }
    }

    private static func resample(imageBuffer: CVImageBuffer, to size: CGSize) -> CVPixelBuffer? {
        var scaledBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &scaledBuffer
        )
        guard status == kCVReturnSuccess, let scaledBuffer else { return nil }

        let image = CIImage(cvPixelBuffer: imageBuffer)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(Double(size.width / max(1, image.extent.width)), forKey: "inputScale")
        filter.setValue(1.0, forKey: "inputAspectRatio")
        guard let output = filter.outputImage else { return nil }

        context.render(
            output,
            to: scaledBuffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return scaledBuffer
    }
}
