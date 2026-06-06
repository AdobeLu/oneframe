//
//  CaptureSessionManager.swift
//  OneFrame
//
//  双摄像头采集管理器 - AVCaptureMultiCamSession
//

import AVFoundation
import CoreImage

protocol CaptureSessionManagerDelegate: AnyObject {
    /// 收到后置摄像头帧
    func captureSessionManager(_ manager: CaptureSessionManager, didOutputBackPixelBuffer: CVPixelBuffer)
    /// 收到前置摄像头帧
    func captureSessionManager(_ manager: CaptureSessionManager, didOutputFrontPixelBuffer: CVPixelBuffer)
    /// 后置摄像头输出尺寸确定（首次收到帧时）
    func captureSessionManager(_ manager: CaptureSessionManager, didDetermineBackOutputSize size: CGSize)
}

/// 手电筒 / 闪光灯模式
enum TorchMode: Int, CaseIterable {
    case auto
    case on
    case off

    var sfSymbolName: String {
        switch self {
        case .auto:  return "bolt.badge.automatic"
        case .on:    return "bolt.fill"
        case .off:   return "bolt.slash.fill"
        }
    }

    var next: TorchMode {
        let all = TorchMode.allCases
        let idx = (all.firstIndex(of: self)! + 1) % all.count
        return all[idx]
    }
}

final class CaptureSessionManager: NSObject {

    weak var delegate: CaptureSessionManagerDelegate?

    // MARK: - Properties
    private(set) var multiCamSession: AVCaptureMultiCamSession?
    private let sessionQueue = DispatchQueue(label: "com.oneframe.capture.session")
    private let backVideoQueue = DispatchQueue(label: "com.oneframe.capture.back.video", qos: .userInitiated)
    private let frontVideoQueue = DispatchQueue(label: "com.oneframe.capture.front.video", qos: .userInitiated)

    // 后置摄像头
    private var backCamera: AVCaptureDevice?
    private var backDeviceInput: AVCaptureDeviceInput?
    private var backVideoOutput: AVCaptureVideoDataOutput?

    // 前置摄像头
    private var frontCamera: AVCaptureDevice?
    private var frontDeviceInput: AVCaptureDeviceInput?
    private var frontVideoOutput: AVCaptureVideoDataOutput?

    // 麦克风
    private var audioDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?

    private(set) var isSessionRunning = false

    /// 后置摄像头输出尺寸（首次收到帧后确定，用于取景框尺寸计算）
    private(set) var backOutputSize: CGSize = .zero
    private var backOutputSizeDetermined = false

    /// 是否支持多摄像头
    static var isMultiCamSupported: Bool {
        return AVCaptureMultiCamSession.isMultiCamSupported
    }

    // MARK: - Setup

    func setupSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            print("MultiCam not supported on this device")
            return
        }

        // 配置音频会话，避免 FigAudioSession err=-19224 (kAudioQueueErr_CannotStart)
        configureAudioSession()

        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    /// 配置 AVAudioSession，确保麦克风可正常使用
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {
            print("AudioSession configuration error: \(error)")
        }
    }

    private func configureSession() {
        multiCamSession = AVCaptureMultiCamSession()

        guard let session = multiCamSession else { return }

        session.beginConfiguration()

        // 配置后置摄像头
        if let backCamera = discoverCamera(position: .back) {
            self.backCamera = backCamera
            do {
                let input = try AVCaptureDeviceInput(device: backCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    backDeviceInput = input
                }

                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: backVideoQueue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    backVideoOutput = output
                    if let connection = output.connection(with: .video) {
                        connection.videoOrientation = .portrait
                        connection.isVideoMirrored = false
                    }
                }
            } catch {
                print("Back camera setup error: \(error)")
            }
        }

        // 配置前置摄像头
        if let frontCamera = discoverCamera(position: .front) {
            self.frontCamera = frontCamera
            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    frontDeviceInput = input
                }

                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: frontVideoQueue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    frontVideoOutput = output
                    if let connection = output.connection(with: .video) {
                        connection.videoOrientation = .portrait
                        connection.isVideoMirrored = true
                    }
                }
            } catch {
                print("Front camera setup error: \(error)")
            }
        }

        // 配置麦克风
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            self.audioDevice = audioDevice
            do {
                let input = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(input) {
                    session.addInput(input)
                    audioInput = input
                }

                let output = AVCaptureAudioDataOutput()
                output.setSampleBufferDelegate(self, queue: sessionQueue)
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    audioOutput = output
                }
            } catch {
                print("Audio setup error: \(error)")
            }
        }

        session.commitConfiguration()
    }

    private func discoverCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let session = self?.multiCamSession, !session.isRunning else { return }
            session.startRunning()
            self?.isSessionRunning = session.isRunning
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let session = self?.multiCamSession, session.isRunning else { return }
            session.stopRunning()
            self?.isSessionRunning = false
        }
    }

    // MARK: - Zoom Control

    /// 后置摄像头当前缩放因子 (1.0 = 无缩放)
    var currentZoomFactor: CGFloat {
        backCamera?.videoZoomFactor ?? 1.0
    }

    /// 最小缩放因子
    var minZoomFactor: CGFloat {
        backCamera?.minAvailableVideoZoomFactor ?? 1.0
    }

    /// 最大缩放因子
    var maxZoomFactor: CGFloat {
        backCamera?.activeFormat.videoMaxZoomFactor ?? 5.0
    }

    /// 设置后置摄像头缩放（平滑缩放，加锁保证线程安全）
    func zoom(to factor: CGFloat) {
        guard let device = backCamera else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, device.activeFormat.videoMaxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clamped, withRate: 32.0)
            device.unlockForConfiguration()
        } catch {
            print("Zoom error: \(error)")
        }
    }

    // MARK: - Torch / Flash Control

    /// 当前手电筒模式
    private(set) var currentTorchMode: TorchMode = .auto

    /// 设置手电筒模式（应用于当前活跃的后置摄像头）
    func setTorchMode(_ mode: TorchMode) {
        currentTorchMode = mode
        applyTorchMode()
    }

    private func applyTorchMode() {
        guard let device = backCamera, device.hasTorch, device.isTorchAvailable else { return }

        let avMode: AVCaptureDevice.TorchMode
        switch currentTorchMode {
        case .auto:
            avMode = .auto
        case .on:
            avMode = .on
        case .off:
            avMode = .off
        }

        do {
            try device.lockForConfiguration()
            if device.isTorchModeSupported(avMode) {
                device.torchMode = avMode
                if avMode == .on {
                    try device.setTorchModeOn(level: 1.0)
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch mode error: \(error)")
        }
    }

    // MARK: - Audio Buffer Forwarding

    /// 音频数据回调转发 - 由外部监听
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CaptureSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == backVideoOutput || output == frontVideoOutput {
            // 视频帧
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            if output == backVideoOutput {
                // 首次收到后置帧时确定输出尺寸
                if !backOutputSizeDetermined {
                    let width = CVPixelBufferGetWidth(pixelBuffer)
                    let height = CVPixelBufferGetHeight(pixelBuffer)
                    backOutputSize = CGSize(width: width, height: height)
                    backOutputSizeDetermined = true
                    delegate?.captureSessionManager(self, didDetermineBackOutputSize: backOutputSize)
                }
                delegate?.captureSessionManager(self, didOutputBackPixelBuffer: pixelBuffer)
            } else if output == frontVideoOutput {
                delegate?.captureSessionManager(self, didOutputFrontPixelBuffer: pixelBuffer)
            }
        } else if output == audioOutput {
            // 音频数据
            onAudioSampleBuffer?(sampleBuffer)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 帧丢失处理
    }
}
