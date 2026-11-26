import AVFoundation
import CoreImage
import Foundation

final class VideoUpscaler {
    enum UpscaleError: LocalizedError {
        case noVideoTrack
        case cannotCreateWriter
        case cannotAddOutput
        case encodingFailed(String)
        case invalidScale
        case invalidDimensions
        case invalidOutputName
        case frameProcessingFailed
        case cancelled
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "This file has no video track."
            case .cannotCreateWriter: return "Could not open the output file."
            case .cannotAddOutput: return "Could not read the video track."
            case .encodingFailed(let message): return message
            case .invalidScale: return "Choose a valid upscale factor."
            case .invalidDimensions: return "The video dimensions are invalid or too small."
            case .invalidOutputName: return "The output file name is invalid."
            case .frameProcessingFailed: return "Could not process a video frame."
            case .cancelled: return "Upscaling was cancelled."
            case .missingOutput: return "The upscaled video is missing."
            }
        }
    }

    private static let context = CIContext()
    private static let maxOutputDimension: CGFloat = 4096
    private static let maxOutputPixels: Double = 8_388_608

    static func upscale(
        source: URL,
        destination: URL,
        scale: Double,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, UpscaleError>) -> Void
    ) {
        _ = startUpscale(source: source, destination: destination, scale: scale, progress: progress, completion: completion)
    }

    @discardableResult
    static func startUpscale(
        source: URL,
        destination: URL,
        scale: Double,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, UpscaleError>) -> Void
    ) -> () -> Void {
        let operation: UpscaleOperation
        do {
            operation = UpscaleOperation(destination: try reserveOutput(at: destination), completion: completion)
        } catch let error as UpscaleError {
            completion(.failure(error))
            return {}
        } catch {
            completion(.failure(.cannotCreateWriter))
            return {}
        }

        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else {
            operation.fail(.noVideoTrack)
            return { operation.cancel() }
        }

        let targetSize: CGSize
        do {
            targetSize = try outputSize(for: track.naturalSize, scale: scale)
        } catch let error as UpscaleError {
            operation.fail(error)
            return { operation.cancel() }
        } catch {
            operation.fail(.invalidDimensions)
            return { operation.cancel() }
        }
        let duration = asset.duration.seconds

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            operation.fail(.cannotAddOutput)
            return { operation.cancel() }
        }
        let videoOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            operation.fail(.cannotAddOutput)
            return { operation.cancel() }
        }
        reader.add(videoOutput)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: operation.destination, fileType: .mp4)
            operation.claimOutput()
        } catch {
            operation.fail(.cannotCreateWriter)
            return { operation.cancel() }
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
            operation.fail(.cannotCreateWriter)
            return { operation.cancel() }
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            writerInput.expectsMediaDataInRealTime = false
            if reader.canAdd(readerOutput), writer.canAdd(writerInput) {
                reader.add(readerOutput)
                writer.add(writerInput)
                audioOutput = readerOutput
                audioInput = writerInput
            }
        }

        operation.configure(reader: reader, writer: writer, inputCount: audioInput == nil ? 1 : 2)
        guard writer.startWriting() else {
            operation.fail(.encodingFailed(writer.error?.localizedDescription ?? "Writer failed to start."))
            return { operation.cancel() }
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            operation.fail(.encodingFailed(reader.error?.localizedDescription ?? "Reader failed to start."))
            return { operation.cancel() }
        }

        let queue = DispatchQueue(label: "com.magdy.upscale")
        videoInput.requestMediaDataWhenReady(on: queue) {
            while videoInput.isReadyForMoreMediaData {
                guard operation.isActive else { return }
                guard let sample = videoOutput.copyNextSampleBuffer() else {
                    if reader.status == .failed {
                        operation.fail(.encodingFailed(reader.error?.localizedDescription ?? "Reader failed."))
                    } else if reader.status == .cancelled {
                        operation.fail(.cancelled)
                    } else {
                        videoInput.markAsFinished()
                        if operation.inputDidFinish() { operation.finishWriting() }
                    }
                    return
                }
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    operation.fail(.frameProcessingFailed)
                    return
                }
                guard let scaled = VideoUpscaler.resample(imageBuffer: imageBuffer, to: targetSize) else {
                    operation.fail(.frameProcessingFailed)
                    return
                }
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                guard adaptor.append(scaled, withPresentationTime: presentationTime) else {
                    operation.fail(.encodingFailed(writer.error?.localizedDescription ?? "Could not append a video frame."))
                    return
                }
                if duration > 0 {
                    let ratio = presentationTime.seconds / duration
                    progress(min(1, max(0, ratio)))
                }
            }
        }

        if let audioOutput, let audioInput {
            audioInput.requestMediaDataWhenReady(on: queue) {
                while audioInput.isReadyForMoreMediaData {
                    guard operation.isActive else { return }
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        if reader.status == .failed {
                            operation.fail(.encodingFailed(reader.error?.localizedDescription ?? "Reader failed."))
                        } else if reader.status == .cancelled {
                            operation.fail(.cancelled)
                        } else {
                            audioInput.markAsFinished()
                            if operation.inputDidFinish() { operation.finishWriting() }
                        }
                        return
                    }
                    guard audioInput.append(sample) else {
                        operation.fail(.encodingFailed(writer.error?.localizedDescription ?? "Could not append audio."))
                        return
                    }
                }
            }
        }

        return { operation.cancel() }
    }

    private static func outputSize(for naturalSize: CGSize, scale: Double) throws -> CGSize {
        guard scale.isFinite, scale >= 1,
              naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0 else {
            throw UpscaleError.invalidScale
        }
        let requestedWidth = max(2, (naturalSize.width * CGFloat(scale)).rounded())
        let requestedHeight = max(2, (naturalSize.height * CGFloat(scale)).rounded())
        guard requestedWidth.isFinite, requestedHeight.isFinite else { throw UpscaleError.invalidDimensions }

        let pixelRatio = maxOutputPixels / (Double(requestedWidth) * Double(requestedHeight))
        let limit = min(
            1.0,
            Double(maxOutputDimension) / Double(requestedWidth),
            Double(maxOutputDimension) / Double(requestedHeight),
            pixelRatio
        )
        var width = CGFloat((Double(requestedWidth) * limit / 2).rounded(.down) * 2)
        var height = CGFloat((Double(requestedHeight) * limit / 2).rounded(.down) * 2)
        width = min(maxOutputDimension, max(2, width))
        height = min(maxOutputDimension, max(2, height))
        guard Double(width) * Double(height) <= maxOutputPixels else { throw UpscaleError.invalidDimensions }
        return CGSize(width: width, height: height)
    }

    private static func reserveOutput(at requested: URL) throws -> URL {
        let name = requested.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw UpscaleError.invalidOutputName
        }
        let folder = requested.deletingLastPathComponent()
        let candidate = folder.appendingPathComponent(
            DownloadDestinationAllocator.availableName(name, in: folder, reserve: true)
        ).standardizedFileURL
        return candidate
    }

    fileprivate static func releaseOutput(_ url: URL) {
        DownloadDestinationAllocator.release(url)
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

private final class UpscaleOperation {
    private let lock = NSLock()
    fileprivate let destination: URL
    private let completion: (Result<URL, VideoUpscaler.UpscaleError>) -> Void
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?
    private var remainingInputs = 0
    private var completed = false
    private var finishing = false
    private var ownsOutput = false

    init(destination: URL, completion: @escaping (Result<URL, VideoUpscaler.UpscaleError>) -> Void) {
        self.destination = destination
        self.completion = completion
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !completed
    }

    func claimOutput() {
        lock.lock()
        ownsOutput = true
        lock.unlock()
    }

    func configure(reader: AVAssetReader, writer: AVAssetWriter, inputCount: Int) {
        lock.lock()
        self.reader = reader
        self.writer = writer
        remainingInputs = inputCount
        lock.unlock()
    }

    func inputDidFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed, !finishing else { return false }
        remainingInputs -= 1
        guard remainingInputs == 0 else { return false }
        finishing = true
        return true
    }

    func finishWriting() {
        lock.lock()
        guard !completed, finishing, let writer else {
            lock.unlock()
            return
        }
        lock.unlock()
        writer.finishWriting { [self] in
            writerDidFinish()
        }
    }

    func cancel() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let reader = self.reader
        let writer = self.writer
        self.reader = nil
        self.writer = nil
        lock.unlock()
        if reader?.status == .reading { reader?.cancelReading() }
        if writer?.status == .writing { writer?.cancelWriting() }
        cleanup()
        completion(.failure(.cancelled))
    }

    func fail(_ error: VideoUpscaler.UpscaleError) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let reader = self.reader
        let writer = self.writer
        self.reader = nil
        self.writer = nil
        lock.unlock()
        if reader?.status == .reading { reader?.cancelReading() }
        if writer?.status == .writing { writer?.cancelWriting() }
        cleanup()
        completion(.failure(error))
    }

    private func writerDidFinish() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let status = writer?.status ?? .failed
        let error = writer?.error
        self.reader = nil
        self.writer = nil
        lock.unlock()

        guard status == .completed else {
            cleanup()
            let failure: VideoUpscaler.UpscaleError = status == .cancelled
                ? .cancelled : .encodingFailed(error?.localizedDescription ?? "Encoding failed.")
            completion(.failure(failure))
            return
        }
        var isDirectory: ObjCBool = false
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              size > 0 else {
            cleanup()
            completion(.failure(.missingOutput))
            return
        }
        VideoUpscaler.releaseOutput(destination)
        completion(.success(destination))
    }

    private func cleanup() {
        lock.lock()
        let shouldRemove = ownsOutput
        ownsOutput = false
        lock.unlock()
        if shouldRemove { try? FileManager.default.removeItem(at: destination) }
        VideoUpscaler.releaseOutput(destination)
    }
}
