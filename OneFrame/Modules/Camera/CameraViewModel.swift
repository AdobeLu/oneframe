//
//  CameraViewModel.swift
//  OneFrame
//
//  相机 ViewModel - 整合效果管线与采集管理
//

import CoreImage
import AVFoundation
import UIKit
import Metal

final class CameraViewModel {

    // MARK: - Dependencies

    private let pipeline = EffectPipeline()

    // MARK: - State

    /// 最新处理后的合成帧
    private(set) var latestProcessedImage: CIImage?

    /// 最新已渲染的合成帧（UIImage，已脱离 CVPixelBuffer 依赖，线程安全读取）
    private(set) var latestRenderedImage: UIImage?

    /// 最新前后帧
    private(set) var latestBackImage: CIImage?
    private(set) var latestFrontImage: CIImage?

    /// 是否开启画中画
    var isPIPEnabled = true {
        didSet { DispatchQueue.main.async { self.onPIPStateChange?(self.isPIPEnabled) } }
    }

    /// 是否交换前后摄像头（前置变全屏背景，后置变 PIP 小窗）
    var isCameraSwapped = false {
        didSet { DispatchQueue.main.async { self.onCameraSwapChange?(self.isCameraSwapped) } }
    }

    /// 是否正在录制
    private(set) var isRecording = false

    // 录制相关
    private var videoRecorder: VideoRecorder?
    private var audioSampleBuffers: [CMSampleBuffer] = []
    private var currentRecordingURL: URL?

    // MARK: - Callbacks

    var onProcessedFrameUpdate: ((UIImage) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?
    var onPIPStateChange: ((Bool) -> Void)?
    var onCameraSwapChange: ((Bool) -> Void)?

    /// 复用的 CIContext（Metal 加速），避免每帧创建
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.workingColorSpace: NSNull()])
        }
        return CIContext(options: [.workingColorSpace: NSNull()])
    }()

    /// 渲染互斥锁：防止上一帧渲染未完成时新帧又提交到 GPU，导致管线堆积掉帧
    private let renderLock = NSLock()
    private var isRendering = false

    // MARK: - Frame Processing

    /// 处理前后摄像头帧
    /// 注意: CIImage(cvPixelBuffer:) 不会拷贝缓冲区，因此必须在采集回调线程同步处理
    func processFrames(
        backPixelBuffer: CVPixelBuffer,
        frontPixelBuffer: CVPixelBuffer,
        pipConfig: Compositor.PIPConfig? = nil
    ) {
        // 渲染互斥：如果上一帧还在处理中，跳过本帧（防止 GPU 过载管线堆积）
        renderLock.lock()
        if isRendering {
            renderLock.unlock()
            return
        }
        isRendering = true
        renderLock.unlock()

        defer {
            renderLock.lock()
            isRendering = false
            renderLock.unlock()
        }

        let backImage = CIImage(cvPixelBuffer: backPixelBuffer)
        let frontImage = CIImage(cvPixelBuffer: frontPixelBuffer)

        latestBackImage = backImage
        latestFrontImage = frontImage

        // 根据交换模式和 PIP 开关决定前后景关系
        let foreground: CIImage?
        let background: CIImage

        if isCameraSwapped {
            // 交换模式：前置全屏背景，后置 PIP 前景
            background = frontImage
            foreground = isPIPEnabled ? backImage : nil
        } else {
            // 正常模式：后置全屏背景，前置 PIP 前景
            background = backImage
            foreground = isPIPEnabled ? frontImage : nil
        }

        let processed = pipeline.processFrame(
            background: background,
            foreground: foreground,
            pipConfig: pipConfig
        )

        latestProcessedImage = processed

        // 使用共享 CIContext 生成 UI 用的 UIImage（避免每帧创建 CIContext）
        if let cgImage = ciContext.createCGImage(processed, from: processed.extent) {
            let uiImage = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
            // 缓存已渲染的 UIImage，脱离 CVPixelBuffer 依赖
            // 这样快速拍照时不会因 CVPixelBuffer 被回收而渲染出黑屏
            latestRenderedImage = uiImage
            DispatchQueue.main.async { [weak self] in
                self?.onProcessedFrameUpdate?(uiImage)
            }
        }

        // 如果正在录制，写入帧
        if isRecording {
            videoRecorder?.appendFrame(processed)
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() -> UIImage? {
        // 优先使用已渲染的 UIImage（脱离 CVPixelBuffer 依赖，避免快速连拍黑屏）
        // latestRenderedImage 在每帧同步渲染时缓存，不依赖原始 CVPixelBuffer 的生命周期
        if let rendered = latestRenderedImage {
            return rendered
        }

        // 降级兜底：如果没有缓存帧（极少见场景），尝试从 CIImage 链渲染
        guard let processed = latestProcessedImage else { return nil }
        guard let cgImage = ciContext.createCGImage(processed, from: processed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    // MARK: - Video Recording

    func startRecording() throws {
        guard !isRecording else { return }

        videoRecorder = VideoRecorder(
            size: pipeline.compositor.canvasSize
        )

        try videoRecorder?.startWriting()
        isRecording = true
        audioSampleBuffers.removeAll()

        DispatchQueue.main.async { [weak self] in
            self?.onRecordingStateChange?(true)
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let recorder = videoRecorder else {
            completion(nil)
            return
        }

        isRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.onRecordingStateChange?(false)
        }

        recorder.finishWriting { [weak self] url in
            self?.currentRecordingURL = url
            completion(url)
        }
    }

    // MARK: - Effects Control

    var filterEffect: FilterEffect { pipeline.filterEffect }
    var frameEffect: FrameEffect { pipeline.frameEffect }
    var watermarkEffect: WatermarkEffect { pipeline.watermarkEffect }
    var mosaicEffect: MosaicEffect { pipeline.mosaicEffect }
    var compositor: Compositor { pipeline.compositor }

    func setFilter(_ filter: FilterType) {
        pipeline.filterEffect.setFilter(filter)
    }

    func setFrame(_ frame: FrameStyle) {
        pipeline.frameEffect.setFrame(frame)
    }

    func setAppNameWatermarkRemoved(_ removed: Bool) {
        pipeline.setAppNameWatermarkRemoved(removed)
    }

    func setInfoWatermarkHidden(_ hidden: Bool) {
        pipeline.setInfoWatermarkHidden(hidden)
    }

    func addMosaicRegion(normalizedRect: CGRect) -> MosaicRegion {
        pipeline.mosaicEffect.addRegion(normalizedRect: normalizedRect)
    }

    func removeMosaicRegion(id: String) {
        pipeline.mosaicEffect.removeRegion(id: id)
    }

    func clearMosaicRegions() {
        pipeline.mosaicEffect.removeAllRegions()
    }
}
