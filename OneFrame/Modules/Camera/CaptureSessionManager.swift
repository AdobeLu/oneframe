//
//  CaptureSessionManager.swift
//  OneFrame
//
//  双摄像头采集管理器 - AVCaptureMultiCamSession
//  支持自动微距模式：靠近被摄物体时自动切换到超广角镜头
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
    /// 采集会话被中断（如其他 App 占用摄像头）
    func captureSessionManager(_ manager: CaptureSessionManager, wasInterrupted reason: AVCaptureSession.InterruptionReason)
    /// 采集会话中断结束
    func captureSessionManagerInterruptionEnded(_ manager: CaptureSessionManager)
    /// 采集会话发生运行时错误
    func captureSessionManager(_ manager: CaptureSessionManager, didReceiveRuntimeError error: Error)
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

/// 微距状态
enum MacroState {
    /// 设备不支持微距（无超广角镜头）
    case unavailable
    /// 支持微距但未激活（使用广角镜头）
    case inactive
    /// 微距已激活（使用超广角镜头）
    case active
}

final class CaptureSessionManager: NSObject {

    weak var delegate: CaptureSessionManagerDelegate?

    // MARK: - Session & Queues
    private(set) var multiCamSession: AVCaptureMultiCamSession?
    private let sessionQueue = DispatchQueue(label: "com.oneframe.capture.session")
    private let backVideoQueue = DispatchQueue(label: "com.oneframe.capture.back.video", qos: .userInitiated)
    private let frontVideoQueue = DispatchQueue(label: "com.oneframe.capture.front.video", qos: .userInitiated)

    // 后置广角摄像头（主摄像头）
    private var backCamera: AVCaptureDevice?
    private var backDeviceInput: AVCaptureDeviceInput?
    private var backVideoOutput: AVCaptureVideoDataOutput?

    // 后置超广角摄像头（微距用）
    private var ultraWideCamera: AVCaptureDevice?
    private var ultraWideDeviceInput: AVCaptureDeviceInput?
    private var ultraWideVideoOutput: AVCaptureVideoDataOutput?

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

    // MARK: - Macro (微距) Properties

    /// 当前微距状态
    private(set) var macroState: MacroState = .unavailable {
        didSet {
            guard macroState != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onMacroStateChange?(self?.macroState ?? .unavailable)
            }
        }
    }

    /// 是否启用自动微距（用户可开关）
    var isAutoMacroEnabled = true {
        didSet {
            if !isAutoMacroEnabled && macroState == .active {
                deactivateMacro()
            }
        }
    }

    /// 微距状态变化回调（主线程）
    var onMacroStateChange: ((MacroState) -> Void)?

    /// 是否由自动检测触发的微距（而非手动）
    private var macroActivatedAutomatically = false

    /// KVO: 对焦位置观察
    private var lensPositionObservation: NSKeyValueObservation?

    /// 微距检测冷却时间（避免频繁切换）
    private static let macroCooldownInterval: TimeInterval = 1.0

    /// 上次微距状态切换时间
    private var lastMacroToggleTime: Date = .distantPast

    /// 连续近距离帧计数（需要持续多帧才触发，避免抖动）
    private var consecutiveCloseFrames = 0
    private static let closeFramesRequired = 3

    /// 连续远距离帧计数
    private var consecutiveFarFrames = 0
    private static let farFramesRequired = 6

    /// 微距检测阈值：超广角镜头 lensPosition 超过此值判定为近距离对焦
    /// 超广角最近对焦 ~2cm，靠近物体 5-15cm 时 lensPosition 约 0.65-0.85
    private static let macroLensPositionThreshold: Float = 0.65

    /// 诊断帧计数器（仅 DEBUG 模式输出日志）
    #if DEBUG
    private var diagnosticFrameCounter = 0
    #endif

    /// 是否有超广角可用（MultiCam 中同时添加了超广角物理镜头）
    var hasUltraWideCamera: Bool {
        return ultraWideCamera != nil
    }

    // MARK: - Setup

    func setupSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            print("MultiCam not supported on this device")
            return
        }

        // ⚠️ 将音频配置和 session 配置全部放到后台线程
        // configureAudioSession 中的 setActive(true) 可能阻塞主线程
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureAudioSession()
            self.configureSession()
        }
    }

    /// 配置 AVAudioSession，确保麦克风可正常使用
    /// ⚠️ 必须在后台线程调用，避免 setActive() 阻塞主线程
    /// （当其他 App 如微信占用音频资源时，此调用可能耗时较长）
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
            )
            // setActive 告知系统本 App 需要使用音频，但不强制抢占
            // 使用 notifyOthersOnDeactivation 让微信等 App 知道我们在请求音频
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSession configuration error: \(error)")
        }
    }

    // MARK: - Session Interruption Observation

    /// 注册采集会话中断通知（如其他 App 占用摄像头 / 音频）
    private var sessionRuntimeErrorObservation: NSKeyValueObservation?
    private var wasInterruptedNotificationObserver: NSObjectProtocol?
    private var interruptionEndedNotificationObserver: NSObjectProtocol?

    private func addSessionObservers() {
        guard let session = multiCamSession else { return }

        // AVCaptureSession 运行时错误
        sessionRuntimeErrorObservation = session.observe(\.isRunning, options: []) { [weak self] _, _ in
            // isRunning 变化时不做特殊处理，由 start/stop 方法维护
        }

        // 会话中断通知
        wasInterruptedNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self = self,
                  let reasonKey = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
                  let reason = AVCaptureSession.InterruptionReason(rawValue: reasonKey) else { return }

            print("CaptureSession interrupted, reason: \(reason.rawValue)")
            self.isSessionRunning = false

            if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                print("⚠️ 摄像头被其他 App 占用（非系统中断）")
            }

            DispatchQueue.main.async {
                self.delegate?.captureSessionManager(self, wasInterrupted: reason)
            }
        }

        // 中断结束通知
        interruptionEndedNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            print("CaptureSession interruption ended, resuming...")
            // ⚠️ MultiCamSession.startRunning() 启动三路摄像头需 1-2s，
            //    必须放后台队列执行，否则阻塞主线程（StoreKit 弹窗 dismiss 后卡 5s 的元凶）
            self.sessionQueue.async {
                if let session = self.multiCamSession, !session.isRunning {
                    session.startRunning()
                    self.isSessionRunning = session.isRunning
                }
                DispatchQueue.main.async {
                    self.delegate?.captureSessionManagerInterruptionEnded(self)
                }
            }
        }

        // 运行时错误通知
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self = self,
                  let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error else { return }
            print("CaptureSession runtime error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.delegate?.captureSessionManager(self, didReceiveRuntimeError: error)
            }
        }
    }

    private func removeSessionObservers() {
        sessionRuntimeErrorObservation?.invalidate()
        sessionRuntimeErrorObservation = nil
        if let observer = wasInterruptedNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            wasInterruptedNotificationObserver = nil
        }
        if let observer = interruptionEndedNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionEndedNotificationObserver = nil
        }
    }

    // MARK: - Deinit

    deinit {
        lensPositionObservation?.invalidate()
        removeSessionObservers()
    }

    private func configureSession() {
        multiCamSession = AVCaptureMultiCamSession()

        guard let session = multiCamSession else { return }

        // 注册中断监听（必须在 startRunning 之前注册）
        addSessionObservers()

        session.beginConfiguration()

        // 1. 配置后置广角摄像头（主摄像头，始终在 Session 中）
        if let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = wideCamera
            do {
                let input = try AVCaptureDeviceInput(device: wideCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    backDeviceInput = input
                }

                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                output.setSampleBufferDelegate(self, queue: backVideoQueue)
                // 当渲染管线来不及处理时，自动丢弃积压的旧帧（防止掉帧雪崩）
                output.alwaysDiscardsLateVideoFrames = true
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

        // 2. 尝试配置后置超广角摄像头（微距用，与广角同时运行）
        if let uwCamera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            ultraWideCamera = uwCamera
            do {
                let input = try AVCaptureDeviceInput(device: uwCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    ultraWideDeviceInput = input

                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    ]
                    output.setSampleBufferDelegate(self, queue: backVideoQueue)
                    output.alwaysDiscardsLateVideoFrames = true
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        ultraWideVideoOutput = output
                        if let connection = output.connection(with: .video) {
                            connection.videoOrientation = .portrait
                            connection.isVideoMirrored = false
                        }
                        print("Macro: ultra-wide camera added to MultiCam session")
                    }
                } else {
                    // 超广角无法添加到 MultiCam（带宽不足或设备限制），清理
                    session.removeInput(input)
                    ultraWideCamera = nil
                    ultraWideDeviceInput = nil
                    print("Macro: ultra-wide camera cannot be added (bandwidth limit or device constraint)")
                }
            } catch {
                print("Ultra-wide camera setup error: \(error)")
                ultraWideCamera = nil
                ultraWideDeviceInput = nil
            }
        } else {
            print("Macro: no ultra-wide camera available on this device")
        }

        // 3. 配置前置摄像头
        // 注意：MultiCamSession 可与其他 App 共享物理摄像头，但系统可能限制带宽。
        // 如果前置被微信占用，canAddInput 可能返回 false，此时降级到仅后置模式。
        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            self.frontCamera = frontCamera
            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    frontDeviceInput = input

                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    ]
                    output.setSampleBufferDelegate(self, queue: frontVideoQueue)
                    output.alwaysDiscardsLateVideoFrames = true
                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        frontVideoOutput = output
                        if let connection = output.connection(with: .video) {
                            connection.videoOrientation = .portrait
                            connection.isVideoMirrored = true
                        }
                    }
                } else {
                    // 前置摄像头被占用，降级：仅后置可用
                    self.frontCamera = nil
                    print("⚠️ Front camera unavailable (likely in use by another app), running with back camera only")
                }
            } catch {
                print("Front camera setup error: \(error)")
                self.frontCamera = nil
            }
        }

        // 4. 配置麦克风
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

        // 5. 配置微距自动检测（在 session 配置完成后）
        configureMacroDetection()
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.multiCamSession, !session.isRunning else { return }

            // configureAudioSession 已在 setupSession() 中完成（同串行队列保证先执行），
            // 不再重复调用 setActive(true)，避免每次启动额外 200-500ms 音频路由协商延迟
            session.startRunning()
            self.isSessionRunning = session.isRunning

            if !session.isRunning {
                print("⚠️ Failed to start capture session - camera may be in use")
            }
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
        activeBackDevice?.videoZoomFactor ?? 1.0
    }

    /// 最小缩放因子
    var minZoomFactor: CGFloat {
        backCamera?.minAvailableVideoZoomFactor ?? 1.0
    }

    /// 最大缩放因子
    var maxZoomFactor: CGFloat {
        backCamera?.activeFormat.videoMaxZoomFactor ?? 5.0
    }

    /// 当前活跃的后置设备（广角或超广角，取决于微距状态）
    private var activeBackDevice: AVCaptureDevice? {
        if macroState == .active, let uw = ultraWideCamera {
            return uw
        }
        return backCamera
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

            // 用户手动缩放时退出自动微距
            if macroState == .active && macroActivatedAutomatically {
                macroActivatedAutomatically = false
                if clamped >= 1.0 {
                    macroState = .inactive
                }
            }
        } catch {
            print("Zoom error: \(error)")
        }
    }

    // MARK: - Torch / Flash Control

    /// 当前手电筒模式
    private(set) var currentTorchMode: TorchMode = .auto

    /// 设置手电筒模式（仅应用于后置广角摄像头）
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

    // MARK: - Macro Detection (微距自动检测)

    /// 配置微距检测：监听超广角+广角的对焦位置变化
    /// MultiCam 模式下虚拟设备不可用，改为同时运行两个物理镜头，
    /// 根据对焦距离在两个输出之间动态切换
    private func configureMacroDetection() {
        // 检查是否有超广角可用
        guard ultraWideCamera != nil else {
            macroState = .unavailable
            print("Macro: no ultra-wide available, macro unavailable")
            return
        }

        macroState = .inactive

        // 优先监听超广角的 lensPosition（最近对焦距离 ~2cm，靠近时值变化大）
        // 如果超广角不可 KVO，回退到广角
        let observeDevice = ultraWideCamera ?? backCamera
        guard let device = observeDevice else { return }

        let deviceLabel = (observeDevice == ultraWideCamera) ? "ultra-wide" : "wide"
        print("Macro: enabled, monitoring lensPosition on \(deviceLabel) lens")

        lensPositionObservation?.invalidate()
        lensPositionObservation = device.observe(\.lensPosition, options: [.new]) { [weak self] device, _ in
            self?.handleLensPositionChange(device.lensPosition, device: device)
        }
    }

    /// 处理对焦位置变化
    /// 监听超广角镜头的原始 lensPosition (0~1)：
    ///   0.0 = 无穷远, 1.0 = 最近对焦 (~2cm)
    /// 靠近物体时 lensPosition 会显著升高
    /// 注意：不能用 minimumFocusDistance 算距离，MultiCam 中该值异常（返回 ~20m）
    private func handleLensPositionChange(_ position: Float, device: AVCaptureDevice) {
        guard isAutoMacroEnabled else { return }
        guard ultraWideCamera != nil else { return }

        // 超广角在 MultiCam 中 lensPosition 语义可能反转：距离越近值越低
        let isVeryClose = position < Self.macroLensPositionThreshold

        #if DEBUG
        diagnosticFrameCounter += 1
        if diagnosticFrameCounter % 15 == 0 {
            print("Macro[diag]: lensPos=\(String(format: "%.3f", position)) isClose=\(isVeryClose) threshold=\(String(format: "%.3f", Self.macroLensPositionThreshold)) closeF=\(consecutiveCloseFrames)/\(Self.closeFramesRequired) state=\(macroState)")
        }
        #endif

        switch macroState {
        case .active:
            if macroActivatedAutomatically {
                if isVeryClose {
                    consecutiveFarFrames = 0
                } else {
                    consecutiveFarFrames += 1
                    if consecutiveFarFrames >= Self.farFramesRequired {
                        deactivateMacro()
                    }
                }
            }

        case .inactive:
            if isVeryClose {
                consecutiveCloseFrames += 1
                if consecutiveCloseFrames >= Self.closeFramesRequired {
                    let now = Date()
                    if now.timeIntervalSince(lastMacroToggleTime) > Self.macroCooldownInterval {
                        activateMacro()
                    }
                }
            } else {
                consecutiveCloseFrames = 0
            }

        case .unavailable:
            break
        }
    }

    /// 激活微距：开始使用超广角摄像头的帧作为后置输出
    private func activateMacro() {
        guard ultraWideCamera != nil else { return }
        guard macroState != .active else { return }

        consecutiveCloseFrames = 0
        consecutiveFarFrames = 0
        macroActivatedAutomatically = true
        macroState = .active
        lastMacroToggleTime = Date()
        print("Macro: activated → using ultra-wide lens")
    }

    /// 退出微距：切回广角摄像头的帧作为后置输出
    private func deactivateMacro() {
        guard macroState == .active else { return }

        consecutiveFarFrames = 0
        consecutiveCloseFrames = 0
        macroActivatedAutomatically = false
        macroState = .inactive
        lastMacroToggleTime = Date()
        print("Macro: deactivated → using wide lens")
    }

    /// 程序化切换微距状态（供用户手动切换按钮调用）
    func toggleMacro() {
        switch macroState {
        case .active:
            deactivateMacro()
        case .inactive:
            consecutiveCloseFrames = Self.closeFramesRequired // 立即触发
            activateMacro()
        case .unavailable:
            break
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CaptureSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == backVideoOutput {
            // 广角摄像头帧：仅在非微距状态时转发
            if macroState != .active {
                forwardBackPixelBuffer(from: sampleBuffer)
            }
        } else if output == ultraWideVideoOutput {
            // 超广角摄像头帧：仅在微距状态时转发
            if macroState == .active {
                forwardBackPixelBuffer(from: sampleBuffer)
            }
        } else if output == frontVideoOutput {
            // 前置摄像头帧
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            delegate?.captureSessionManager(self, didOutputFrontPixelBuffer: pixelBuffer)
        } else if output == audioOutput {
            // 音频数据
            onAudioSampleBuffer?(sampleBuffer)
        }
    }

    /// 统一的后置帧转发逻辑（广角或超广角）
    private func forwardBackPixelBuffer(from sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 首次收到后置帧时确定输出尺寸
        if !backOutputSizeDetermined {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            backOutputSize = CGSize(width: width, height: height)
            backOutputSizeDetermined = true
            delegate?.captureSessionManager(self, didDetermineBackOutputSize: backOutputSize)
        }
        delegate?.captureSessionManager(self, didOutputBackPixelBuffer: pixelBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 帧丢失处理
    }
}
