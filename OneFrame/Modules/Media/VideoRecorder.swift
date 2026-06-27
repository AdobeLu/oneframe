//
//  VideoRecorder.swift
//  OneFrame
//
//  视频录制器 - AVAssetWriter 逐帧合成视频
//  性能优化: pixelBufferPool 复用 + CPU 直写 CGImage → 零 GPU 开销
//

import AVFoundation
import UIKit

final class VideoRecorder {

    // MARK: - Properties

    private let outputSize: CGSize
    private var assetWriter: AVAssetWriter?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var isWriting = false
    /// writer 已就绪可写入帧（startWriting + startSession 完成后置 true）
    private var isWriterReady = false
    private var currentAudioTime: CMTime = .zero

    /// 录制开始的墙上时钟，视频时戳 = 真实时间差（不依赖帧计数，跳帧也不影响速度）
    private var recordStartDate: Date?

    private let writeQueue = DispatchQueue(label: "com.oneframe.video.write")

    // 输出路径
    private(set) var outputURL: URL?

    // MARK: - Init

    init(size: CGSize) {
        self.outputSize = size
    }

    // MARK: - Public

    /// 异步启动写入器，writer 就绪后回调（不阻塞调用线程）
    func startWriting(completion: @escaping (Result<Void, Error>) -> Void) {
        writeQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let fileName = "video_\(Date().timeIntervalSince1970).mp4"
                let directory = MediaStorageManager.shared.videosDirectory
                let url = directory.appendingPathComponent(fileName)
                self.outputURL = url

                // 删除旧文件
                try? FileManager.default.removeItem(at: url)

                self.assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

                // 视频编码设置
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: self.outputSize.width,
                    AVVideoHeightKey: self.outputSize.height
                ]

                let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                vInput.expectsMediaDataInRealTime = true
                self.videoInput = vInput

                let pixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: self.outputSize.width,
                    kCVPixelBufferHeightKey as String: self.outputSize.height,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]

                self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: vInput,
                    sourcePixelBufferAttributes: pixelBufferAttributes
                )

                guard let writer = self.assetWriter, writer.canAdd(vInput) else {
                    throw VideoRecorderError.cannotAddInput
                }

                writer.add(vInput)

                // 音频输入
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44100
                ]
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                aInput.expectsMediaDataInRealTime = true
                if writer.canAdd(aInput) {
                    writer.add(aInput)
                    self.audioInput = aInput
                }

                // ⚠️ startWriting() 初始化编码器，耗时 1-2 秒，必须在后台线程调用
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)

                self.currentAudioTime = .zero
                self.recordStartDate = Date()
                self.isWriterReady = true
                self.isWriting = true

                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// 写入音频样本（重新打时间戳，对齐视频时间线 .zero 起点）
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, isWriterReady,
              let input = audioInput,
              input.isReadyForMoreMediaData else {
            return
        }

        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: currentAudioTime,
            decodeTimeStamp: .invalid
        )

        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: [timing],
            sampleBufferOut: &newBuffer
        )

        if let newBuffer = newBuffer {
            input.append(newBuffer)
            currentAudioTime = CMTimeAdd(currentAudioTime, duration)
        }
    }

    /// 写入视频帧（调用线程同步执行，CPU 直写 pixelBuffer，零 GPU 路径）
    func appendFrame(_ cgImage: CGImage) {
        guard isWriting, isWriterReady,
              let adaptor = pixelBufferAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else {
            return
        }

        // 墙上时钟时间戳 → 跳帧不影响视频速度
        let elapsed = Date().timeIntervalSince(recordStartDate ?? Date())
        let pts = CMTime(seconds: elapsed, preferredTimescale: 600)

        // 从 adaptor 内置 pool 复用 pixelBuffer（零内存分配）
        var pixelBuffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        }

        guard let buffer = pixelBuffer else { return }

        // CPU 直写 CGImage 位图 → pixelBuffer（无 GPU 路径）
        CVPixelBufferLockBaseAddress(buffer, [])

        let cgWidth = CVPixelBufferGetWidth(buffer)
        let cgHeight = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        if let baseAddr = CVPixelBufferGetBaseAddress(buffer) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue

            if let ctx = CGContext(
                data: baseAddr,
                width: cgWidth,
                height: cgHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgWidth, height: cgHeight))
            }
        }

        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: pts)
    }

    func finishWriting(completion: @escaping (URL?) -> Void) {
        guard let writer = assetWriter, isWriting else {
            completion(nil)
            return
        }

        isWriting = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting {
            let url = writer.status == .completed ? self.outputURL : nil

            if let videoURL = url {
                self.generateThumbnail(for: videoURL)
            }

            DispatchQueue.main.async {
                completion(url)
            }
        }
    }

    // MARK: - Private

    private func generateThumbnail(for videoURL: URL) {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)

        let time = CMTime(value: 0, timescale: 1)

        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
            guard result == .succeeded, let cgImage = cgImage else { return }

            let uiImage = UIImage(cgImage: cgImage)
            let thumbData = uiImage.jpegData(compressionQuality: 0.7)

            let thumbURL = videoURL
                .deletingPathExtension()
                .appendingPathExtension("thumb.jpg")

            try? thumbData?.write(to: thumbURL)

            MediaStorageManager.shared.addMediaEntry(
                type: .video,
                originalURL: videoURL,
                thumbnailURL: thumbURL
            )
        }
    }
}

enum VideoRecorderError: Error {
    case cannotAddInput
}
