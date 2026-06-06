//
//  VideoRecorder.swift
//  OneFrame
//
//  视频录制器 - AVAssetWriter 逐帧合成视频
//

import AVFoundation
import CoreImage
import UIKit

final class VideoRecorder {

    // MARK: - Properties

    private let outputSize: CGSize
    private var assetWriter: AVAssetWriter?
    private var pixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
    private var videoInput: AVAssetWriterInput?
    private var isWriting = false
    private var currentFrameTime: CMTime = .zero
    private let frameRate: Int32 = 30
    private var frameDuration: CMTime { CMTime(value: 1, timescale: frameRate) }

    private let writeQueue = DispatchQueue(label: "com.oneframe.video.write")
    private let ciContext: CIContext

    // 输出路径
    private(set) var outputURL: URL?

    // MARK: - Init

    init(size: CGSize) {
        self.outputSize = size
        self.ciContext = CIContext(options: [
            .workingColorSpace: NSNull()
        ])
    }

    // MARK: - Public

    func startWriting() throws {
        let fileName = "video_\(Date().timeIntervalSince1970).mp4"
        let directory = MediaStorageManager.shared.videosDirectory
        let url = directory.appendingPathComponent(fileName)
        outputURL = url

        // 删除旧文件
        try? FileManager.default.removeItem(at: url)

        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // 视频编码设置
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]

        pixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard let writer = assetWriter, writer.canAdd(videoInput!) else {
            throw VideoRecorderError.cannotAddInput
        }

        writer.add(videoInput!)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        currentFrameTime = .zero
        isWriting = true
    }

    func appendFrame(_ ciImage: CIImage) {
        guard isWriting,
              let writer = assetWriter,
              writer.status == .writing,
              let input = videoInput,
              input.isReadyForMoreMediaData else {
            return
        }

        writeQueue.async { [weak self] in
            guard let self = self else { return }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(self.outputSize.width),
                Int(self.outputSize.height),
                kCVPixelFormatType_32BGRA,
                [
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ] as CFDictionary,
                &pixelBuffer
            )

            guard let buffer = pixelBuffer else { return }

            // 渲染 CIImage 到 PixelBuffer
            self.ciContext.render(
                ciImage.cropped(to: CGRect(origin: .zero, size: self.outputSize)),
                to: buffer
            )

            let time = self.currentFrameTime
            self.currentFrameTime = CMTimeAdd(time, self.frameDuration)

            self.pixelBufferInput?.append(buffer, withPresentationTime: time)
        }
    }

    func finishWriting(completion: @escaping (URL?) -> Void) {
        guard let writer = assetWriter, isWriting else {
            completion(nil)
            return
        }

        isWriting = false

        videoInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            let url = writer.status == .completed ? self?.outputURL : nil

            if let videoURL = url {
                // 生成视频缩略图
                self?.generateThumbnail(for: videoURL)
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
