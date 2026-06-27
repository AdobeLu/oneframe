//
//  CameraViewController.swift
//  OneFrame
//
//  相机主界面 - 预览/控制（整合效果管线）
//

import UIKit
import AVFoundation

@available(iOS 15.0, *)
final class CameraViewController: UIViewController {

    // MARK: - Properties

    private let captureSessionManager: CaptureSessionManager
    private let viewModel = CameraViewModel()

    /// 取景框和画布的固定宽高比（竖屏 3:4，与系统相机一致）
    private static let viewfinderRatio: CGFloat = 3.0 / 4.0

    // 预览视图
    private let previewContainer = UIView()
    private let pipOverlayView = PIPOverlayView()
    private let processedPreview = UIImageView()

    // 控制按钮
    private let shutterRingView = UIView()
    private let shutterButton = UIButton(type: .system)
    private let filterButton = UIButton(type: .system)
    private let frameButton = UIButton(type: .system)
    private let pipToggleButton = UIButton(type: .system)
    private let cameraSwitchButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let macroToggleButton = UIButton(type: .system)
    private let watermarkToggleButton = UIButton(type: .system)
    private let modeSegment = UISegmentedControl(items: [
        OWLocalized("camera.photo"),
        OWLocalized("camera.video")
    ])

    private var isPhotoMode = true {
        didSet { updateShutterButtonAppearance() }
    }

    // 帧缓存
    private var latestBackBuffer: CVPixelBuffer?
    private var latestFrontBuffer: CVPixelBuffer?
    /// 当前是否处于摄像头中断状态
    var isSessionInterrupted = false
    /// 摄像头被占用时显示的遮罩
    var cameraUnavailableOverlay: UIView?
    // 捏合缩放
    private var initialZoomFactor: CGFloat = 1.0

    // 缓存的 PIP 配置（主线程更新，后台线程安全读取）
    private var cachedPIPConfig = Compositor.PIPConfig()

    // 控制栏背景
    private let topBar = UIView()
    private let bottomBar = UIView()

    // 取景框动态约束
    private var previewTopConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    private var previewCenterXConstraint: NSLayoutConstraint?
    private var previewWidthConstraint: NSLayoutConstraint?

    // MARK: - Init

    init(captureSessionManager: CaptureSessionManager) {
        self.captureSessionManager = captureSessionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCaptureManager()
        setupViewModel()
        setupNotifications()

        // 请求定位权限获取水印信息
        LocationService.shared.requestPermission()
        LocationService.shared.startUpdating { _, _ in
            // 水印会自动根据位置更新
        }

        // 内购状态：同步 App 名称水印（"同框相机"）- 付费后移除
        viewModel.setAppNameWatermarkRemoved(IAPManager.shared.isWatermarkRemoved)

        // 信息水印（时间/地点/设备）初始可见，由用户开关按钮控制
        isInfoWatermarkVisible = true
        viewModel.setInfoWatermarkHidden(!isInfoWatermarkVisible)
        updateWatermarkButtonAppearance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSessionManager.startSession()

        // 重新同步内购状态（用户可能从设置页购买后返回）
        viewModel.setAppNameWatermarkRemoved(IAPManager.shared.isWatermarkRemoved)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 不在此处停止 session：tab 切换时也会触发 viewDidDisappear，
        // 每次 stop/start 循环中 MultiCamSession.startRunning() 需要 1-2 秒
        // 协调多路摄像头硬件资源，导致从设置页切回拍照时有明显黑屏延迟。
        // 统一由 SceneDelegate.sceneDidEnterBackground 在真后台时停止，
        // sceneDidBecomeActive / viewDidAppear 在回到前台时恢复。
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 先更新取景框约束，保证 containerSize 和 canvasSize 完全对齐
        updateViewfinderConstraints()
        view.layoutIfNeeded()

        // 固定 3:4 竖屏画布，画布尺寸 = 取景框像素尺寸（所看即所得）
        let scale = UIScreen.main.scale
        let containerSize = previewContainer.bounds.size
        let canvasWidth = containerSize.width * scale
        let canvasHeight = canvasWidth / Self.viewfinderRatio
        viewModel.compositor.updateCanvasSize(CGSize(width: canvasWidth, height: canvasHeight))

        pipOverlayView.resetPosition(to: containerSize)
        processedPreview.frame = previewContainer.bounds

        updateCachedPIPConfig(containerSize: containerSize)

    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Setup

    private func setupCaptureManager() {
        captureSessionManager.delegate = self
        captureSessionManager.setupSession()

        // 监听微距状态变化
        captureSessionManager.onMacroStateChange = { [weak self] state in
            self?.updateMacroButtonAppearance(for: state)
        }
    }

    private func setupViewModel() {
        viewModel.onProcessedFrameUpdate = { [weak self] image in
            self?.processedPreview.image = image
        }

        viewModel.onRecordingStateChange = { [weak self] isRecording in
            self?.updateRecordingUI(isRecording)
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        modeSegment.setTitle(OWLocalized("camera.photo"), forSegmentAt: 0)
        modeSegment.setTitle(OWLocalized("camera.video"), forSegmentAt: 1)
    }

    private func setupUI() {
        view.backgroundColor = .black

        // MARK: 预览容器（取景框 - 非全屏，根据摄像头宽高比自适应）
        previewContainer.backgroundColor = .clear
        previewContainer.clipsToBounds = true
        view.addSubview(previewContainer)
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        // 居中，宽高由 updateViewfinderConstraints 按 3:4 严格比例动态计算
        let topConstraint = previewContainer.topAnchor.constraint(equalTo: view.topAnchor)
        let heightConstraint = previewContainer.heightAnchor.constraint(equalToConstant: view.bounds.height)
        let centerXConstraint = previewContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        let widthConstraint = previewContainer.widthAnchor.constraint(equalToConstant: view.bounds.width)
        NSLayoutConstraint.activate([
            topConstraint,
            centerXConstraint,
            widthConstraint,
            heightConstraint
        ])
        previewTopConstraint = topConstraint
        previewHeightConstraint = heightConstraint
        previewCenterXConstraint = centerXConstraint
        previewWidthConstraint = widthConstraint

        // 处理后的预览画面（全屏）
        processedPreview.contentMode = .scaleAspectFill
        processedPreview.backgroundColor = .black
        processedPreview.frame = CGRect(origin: .zero, size: view.bounds.size)
        processedPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        previewContainer.addSubview(processedPreview)

        // PIP 小窗 - 仅做拖拽指示器，不显示实时预览
        pipOverlayView.isPreviewHidden = true
        pipOverlayView.resetPosition(to: view.bounds.size)
        pipOverlayView.onPositionChanged = { [weak self] in
            self?.updateCachedPIPConfig(containerSize: self?.previewContainer.bounds.size ?? .zero)
        }
        previewContainer.addSubview(pipOverlayView)

        // MARK: 顶部控制栏（纯黑）
        topBar.backgroundColor = .black
        view.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 100)
        ])

        // MARK: 底部控制栏（纯黑）
        bottomBar.backgroundColor = .black
        view.addSubview(bottomBar)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 160)
        ])

        // MARK: 模式切换分段控件
        modeSegment.selectedSegmentIndex = 0
        modeSegment.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.3)
        modeSegment.setTitleTextAttributes(
            [.foregroundColor: UIColor.white.withAlphaComponent(0.6), .font: UIFont.systemFont(ofSize: 13, weight: .medium)],
            for: .normal
        )
        modeSegment.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)],
            for: .selected
        )
        modeSegment.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        bottomBar.addSubview(modeSegment)
        modeSegment.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeSegment.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            modeSegment.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -24),
            modeSegment.widthAnchor.constraint(equalToConstant: 160),
            modeSegment.heightAnchor.constraint(equalToConstant: 32)
        ])

        // MARK: 快门按钮（系统风格：外圈 + 内按钮）
        // 外圈
        shutterRingView.backgroundColor = .clear
        shutterRingView.layer.cornerRadius = 40
        shutterRingView.layer.borderWidth = 4
        shutterRingView.layer.borderColor = UIColor.white.cgColor
        shutterRingView.isUserInteractionEnabled = false
        bottomBar.addSubview(shutterRingView)
        shutterRingView.translatesAutoresizingMaskIntoConstraints = false

        // 内按钮
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 32
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bottomBar.addSubview(shutterButton)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shutterRingView.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            shutterRingView.bottomAnchor.constraint(equalTo: modeSegment.topAnchor, constant: -20),
            shutterRingView.widthAnchor.constraint(equalToConstant: 80),
            shutterRingView.heightAnchor.constraint(equalToConstant: 80),

            shutterButton.centerXAnchor.constraint(equalTo: shutterRingView.centerXAnchor),
            shutterButton.centerYAnchor.constraint(equalTo: shutterRingView.centerYAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: 64),
            shutterButton.heightAnchor.constraint(equalToConstant: 64),
        ])

        // MARK: 功能按钮（滤镜/画框/切换后摄）统一配置
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let smallIconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        // MARK: 闪光灯按钮 - 取景框左上角
        let initialTorchMode = captureSessionManager.currentTorchMode
        flashButton.setImage(UIImage(systemName: initialTorchMode.sfSymbolName, withConfiguration: smallIconConfig), for: .normal)
        flashButton.tintColor = torchTintColor(for: initialTorchMode)
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        flashButton.layer.cornerRadius = 18
        flashButton.layer.shadowColor = UIColor.black.cgColor
        flashButton.layer.shadowOpacity = 0.3
        flashButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        flashButton.layer.shadowRadius = 4
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        previewContainer.addSubview(flashButton)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            flashButton.widthAnchor.constraint(equalToConstant: 36),
            flashButton.heightAnchor.constraint(equalToConstant: 36),
            flashButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            flashButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12)
        ])

        // MARK: 微距按钮 - 取景框左上角，闪光灯右侧
        macroToggleButton.isHidden = true // 不支持微距时隐藏
        macroToggleButton.addTarget(self, action: #selector(macroToggleTapped), for: .touchUpInside)
        previewContainer.addSubview(macroToggleButton)
        macroToggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            macroToggleButton.widthAnchor.constraint(equalToConstant: 36),
            macroToggleButton.heightAnchor.constraint(equalToConstant: 36),
            macroToggleButton.leadingAnchor.constraint(equalTo: flashButton.trailingAnchor, constant: 8),
            macroToggleButton.centerYAnchor.constraint(equalTo: flashButton.centerYAnchor)
        ])

        // MARK: 水印开关按钮 - 取景框左上角，微距按钮右侧
        watermarkToggleButton.setImage(UIImage(systemName: "info.circle", withConfiguration: smallIconConfig), for: .normal)
        watermarkToggleButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        watermarkToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        watermarkToggleButton.layer.cornerRadius = 18
        watermarkToggleButton.layer.shadowColor = UIColor.black.cgColor
        watermarkToggleButton.layer.shadowOpacity = 0.3
        watermarkToggleButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        watermarkToggleButton.layer.shadowRadius = 4
        watermarkToggleButton.addTarget(self, action: #selector(watermarkToggleTapped), for: .touchUpInside)
        previewContainer.addSubview(watermarkToggleButton)
        watermarkToggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            watermarkToggleButton.widthAnchor.constraint(equalToConstant: 36),
            watermarkToggleButton.heightAnchor.constraint(equalToConstant: 36),
            watermarkToggleButton.leadingAnchor.constraint(equalTo: macroToggleButton.trailingAnchor, constant: 8),
            watermarkToggleButton.centerYAnchor.constraint(equalTo: flashButton.centerYAnchor)
        ])

        // MARK: PIP 开关按钮 - 底部栏左侧
        pipToggleButton.setImage(UIImage(systemName: "pip.enter", withConfiguration: smallIconConfig), for: .normal)
        pipToggleButton.tintColor = .systemYellow
        pipToggleButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        pipToggleButton.layer.cornerRadius = 20
        pipToggleButton.layer.shadowColor = UIColor.black.cgColor
        pipToggleButton.layer.shadowOpacity = 0.3
        pipToggleButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        pipToggleButton.layer.shadowRadius = 4
        pipToggleButton.addTarget(self, action: #selector(pipToggleTapped), for: .touchUpInside)
        bottomBar.addSubview(pipToggleButton)
        pipToggleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pipToggleButton.widthAnchor.constraint(equalToConstant: 40),
            pipToggleButton.heightAnchor.constraint(equalToConstant: 40),
            pipToggleButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            pipToggleButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor)
        ])

        let styledButtons: [(button: UIButton, icon: String, action: Selector)] = [
            (filterButton, "camera.filters", #selector(filterTapped)),
            (frameButton, "rectangle.on.rectangle", #selector(frameTapped)),
            (cameraSwitchButton, "arrow.triangle.2.circlepath.camera", #selector(cameraSwitchTapped))
        ]

        for (btn, icon, action) in styledButtons {
            btn.setImage(UIImage(systemName: icon, withConfiguration: iconConfig), for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            btn.layer.cornerRadius = 20
            btn.layer.shadowColor = UIColor.black.cgColor
            btn.layer.shadowOpacity = 0.3
            btn.layer.shadowOffset = CGSize(width: 0, height: 1)
            btn.layer.shadowRadius = 4
            btn.addTarget(self, action: action, for: .touchUpInside)
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            bottomBar.addSubview(btn)
            btn.translatesAutoresizingMaskIntoConstraints = false
        }

        // 滤镜按钮 - 快门左侧
        NSLayoutConstraint.activate([
            filterButton.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -50),
            filterButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor)
        ])

        // 画框按钮 - 快门右侧
        NSLayoutConstraint.activate([
            frameButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 50),
            frameButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor)
        ])

        // 前后摄像头切换按钮 - 底部栏右侧
        cameraSwitchButton.tintColor = .white
        NSLayoutConstraint.activate([
            cameraSwitchButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            cameraSwitchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor)
        ])

        // MARK: 层级管理
        previewContainer.bringSubviewToFront(pipOverlayView)
        previewContainer.bringSubviewToFront(flashButton)
        previewContainer.bringSubviewToFront(watermarkToggleButton)
        view.bringSubviewToFront(topBar)
        view.bringSubviewToFront(bottomBar)

        // 捏合缩放手势（仅后置取景框生效）
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewContainer.addGestureRecognizer(pinch)
    }

    // MARK: - Helpers

    private func torchTintColor(for mode: TorchMode) -> UIColor {
        switch mode {
        case .auto: return .systemYellow
        case .on:   return .systemYellow
        case .off:  return UIColor.white.withAlphaComponent(0.5)
        }
    }

    private func updateShutterButtonAppearance() {
        let innerSize: CGFloat = isPhotoMode ? 64 : 30
        let innerRadius: CGFloat = isPhotoMode ? 32 : 8
        let ringRadius: CGFloat = isPhotoMode ? 40 : 8
        let ringSize: CGFloat = isPhotoMode ? 80 : 34

        UIView.animate(withDuration: 0.25) {
            self.shutterButton.backgroundColor = self.isPhotoMode ? .white : .red
            self.shutterButton.layer.cornerRadius = innerRadius

            self.shutterRingView.layer.cornerRadius = ringRadius
            self.shutterRingView.layer.borderColor = self.isPhotoMode
                ? UIColor.white.cgColor
                : UIColor.red.cgColor

            // 更新约束
            if let ringWidth = self.bottomBar.constraints.first(where: { ($0.firstItem as? UIView) == self.shutterRingView && $0.firstAttribute == .width }),
               let ringHeight = self.bottomBar.constraints.first(where: { ($0.firstItem as? UIView) == self.shutterRingView && $0.firstAttribute == .height }),
               let btnWidth = self.bottomBar.constraints.first(where: { ($0.firstItem as? UIView) == self.shutterButton && $0.firstAttribute == .width }),
               let btnHeight = self.bottomBar.constraints.first(where: { ($0.firstItem as? UIView) == self.shutterButton && $0.firstAttribute == .height }) {
                ringWidth.constant = ringSize
                ringHeight.constant = ringSize
                btnWidth.constant = innerSize
                btnHeight.constant = innerSize
            }
            self.bottomBar.layoutIfNeeded()
        }
    }

    // MARK: - Zoom

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialZoomFactor = captureSessionManager.currentZoomFactor
        case .changed:
            let targetZoom = initialZoomFactor * gesture.scale
            captureSessionManager.zoom(to: targetZoom)
        default:
            break
        }
    }

    private func updateRecordingUI(_ isRecording: Bool) {
        // 录制状态通过 updateShutterButtonAppearance 的 .red 色来体现
        // ringView 在录像时变红
        shutterRingView.layer.borderColor = isRecording
            ? UIColor.red.cgColor
            : UIColor.white.cgColor
    }

    /// 根据固定 3:4 比例调整取景框位置和高度
    /// 取景框上移 50pt，给底部水印留出显示空间
    private func updateViewfinderConstraints() {
        let viewWidth = view.bounds.width
        let viewHeight = view.bounds.height

        guard viewWidth > 0, viewHeight > 0 else { return }

        let topBarHeight: CGFloat = 100
        let bottomBarHeight: CGFloat = 160

        // bottomBar 锚定 safeAreaLayoutGuide.bottomAnchor，用 safeArea 计算顶部位置
        let safeAreaBottom = view.safeAreaLayoutGuide.layoutFrame.maxY
        let bottomBarTop = safeAreaBottom - bottomBarHeight
        let availableHeight = bottomBarTop - topBarHeight

        // 按 3:4 严格比例计算，高度受限时同步缩小宽度，避免 scaleAspectFill 裁切水印
        let idealHeight = viewWidth / Self.viewfinderRatio
        let previewHeight: CGFloat
        let previewWidth: CGFloat
        if idealHeight <= availableHeight {
            // 空间足够，宽度撑满
            previewHeight = idealHeight
            previewWidth = viewWidth
        } else {
            // 高度不够，按 3:4 比例缩小宽度
            previewHeight = availableHeight
            previewWidth = availableHeight * Self.viewfinderRatio
        }

        // 垂直居中后上移 50pt，露出底部水印
        let centerOffset = topBarHeight + (availableHeight - previewHeight) / 2
        let shiftUp: CGFloat = 50
        let topOffset = max(topBarHeight, centerOffset - shiftUp)

        previewTopConstraint?.constant = topOffset
        previewHeightConstraint?.constant = previewHeight
        previewWidthConstraint?.constant = previewWidth
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        isPhotoMode = modeSegment.selectedSegmentIndex == 0
    }

    @objc private func shutterTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if isPhotoMode {
            capturePhoto()
        } else {
            toggleVideoRecording()
        }
    }

    private func capturePhoto() {
        guard let image = viewModel.capturePhoto() else { return }

        // 保存到沙盒
        if PhotoCapture.saveToSandbox(image: image) != nil {
            // 1. 取景框白色闪烁动效
            showCaptureFlash()

            // 2. 缩略图从取景框缩放到左下角，3秒后消失
            showCaptureThumbnail(image: image)
        }
    }

    // MARK: - Capture Feedback Animations

    /// 取景框白色闪烁
    private func showCaptureFlash() {
        let flash = UIView()
        flash.backgroundColor = .white
        flash.alpha = 0
        flash.isUserInteractionEnabled = false
        previewContainer.addSubview(flash)
        flash.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            flash.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            flash.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            flash.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            flash.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
        ])
        previewContainer.layoutIfNeeded()

        UIView.animateKeyframes(withDuration: 0.4, delay: 0, options: .calculationModeCubic) {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.3) {
                flash.alpha = 0.7
            }
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                flash.alpha = 0
            }
        } completion: { _ in
            flash.removeFromSuperview()
        }
    }

    /// 缩略图从取景框全屏缩放至取景框左下角，3 秒后淡出消失
    private func showCaptureThumbnail(image: UIImage) {
        let thumbView = UIImageView(image: image)
        thumbView.contentMode = .scaleAspectFill
        thumbView.clipsToBounds = true
        thumbView.layer.cornerRadius = 6
        thumbView.layer.borderWidth = 2
        thumbView.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor

        // 初始 frame = 取景框全屏
        let startFrame = previewContainer.bounds
        thumbView.frame = startFrame

        // thumbView 添加到 previewContainer 内，坐标系一致
        previewContainer.addSubview(thumbView)

        // 目标 frame = 取景框左下角小缩略图（与地点水印位置一致）
        let targetSize = CGSize(width: 60, height: 80)
        let margin: CGFloat = 12
        let targetX = margin
        let targetY = previewContainer.bounds.height - targetSize.height - margin

        UIView.animateKeyframes(withDuration: 0.5, delay: 0, options: .calculationModeCubic) {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.6) {
                thumbView.frame = CGRect(
                    x: targetX,
                    y: targetY,
                    width: targetSize.width,
                    height: targetSize.height
                )
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                thumbView.alpha = 0.85
            }
        } completion: { _ in
            // 3 秒后淡出消失
            UIView.animate(withDuration: 0.4, delay: 3.0, options: .curveEaseOut) {
                thumbView.alpha = 0
                thumbView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            } completion: { _ in
                thumbView.removeFromSuperview()
            }
        }
    }

    private func toggleVideoRecording() {
        if viewModel.isRecording {
            viewModel.stopRecording { url in
                if let url = url {
                    print("Video saved at: \(url)")
                }
            }
        } else {
            do {
                try viewModel.startRecording()
            } catch {
                let alert = UIAlertController(title: nil, message: "Failed to start recording", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func filterTapped() {
        let alert = UIAlertController(title: OWLocalized("camera.filter"), message: nil, preferredStyle: .actionSheet)

        for filter in FilterType.allCases {
            let action = UIAlertAction(title: filter.rawValue, style: .default) { [weak self] _ in
                self?.viewModel.setFilter(filter)
            }
            if filter == viewModel.filterEffect.currentFilter {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: OWLocalized("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func frameTapped() {
        let alert = UIAlertController(title: OWLocalized("camera.frame"), message: nil, preferredStyle: .actionSheet)

        for frame in FrameStyle.allCases {
            let action = UIAlertAction(title: frame.rawValue, style: .default) { [weak self] _ in
                self?.viewModel.setFrame(frame)
            }
            if frame == viewModel.frameEffect.currentFrame {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: OWLocalized("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func pipToggleTapped() {
        viewModel.isPIPEnabled.toggle()

        let iconName = viewModel.isPIPEnabled ? "pip.enter" : "pip.exit"
        pipToggleButton.setImage(UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        pipToggleButton.tintColor = viewModel.isPIPEnabled ? .systemYellow : UIColor.white.withAlphaComponent(0.5)

        // PIP 关闭时隐藏小窗指示器
        pipOverlayView.isHidden = !viewModel.isPIPEnabled
    }

    @objc private func cameraSwitchTapped() {
        viewModel.isCameraSwapped.toggle()

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        let iconName = viewModel.isCameraSwapped
            ? "arrow.triangle.2.circlepath.camera.fill"
            : "arrow.triangle.2.circlepath.camera"
        cameraSwitchButton.setImage(UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)), for: .normal)
        cameraSwitchButton.tintColor = viewModel.isCameraSwapped ? .systemYellow : .white
    }

    @objc private func flashTapped() {
        let nextMode = captureSessionManager.currentTorchMode.next
        captureSessionManager.setTorchMode(nextMode)

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        updateFlashButtonAppearance(for: nextMode)
    }

    @objc private func watermarkToggleTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // 仅切换时间/地点/设备信息水印，不影响"同框相机"品牌水印
        isInfoWatermarkVisible.toggle()
        viewModel.setInfoWatermarkHidden(!isInfoWatermarkVisible)
        updateWatermarkButtonAppearance()
    }

    /// 时间/地点/设备信息水印是否可见（用户手动开关，免费功能）
    private var isInfoWatermarkVisible = true

    private func updateWatermarkButtonAppearance() {
        let iconName = isInfoWatermarkVisible ? "info.circle" : "info.circle.fill"
        watermarkToggleButton.setImage(
            UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
            for: .normal
        )
        watermarkToggleButton.tintColor = isInfoWatermarkVisible
            ? UIColor.white.withAlphaComponent(0.8)
            : UIColor.white.withAlphaComponent(0.35)
    }

    private func updateFlashButtonAppearance(for mode: TorchMode) {
        flashButton.setImage(
            UIImage(systemName: mode.sfSymbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)),
            for: .normal
        )
        flashButton.tintColor = torchTintColor(for: mode)
    }

    // MARK: - Macro (微距)

    @objc private func macroToggleTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        captureSessionManager.toggleMacro()
    }

    private func updateMacroButtonAppearance(for state: MacroState) {
        let smallIconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        switch state {
        case .unavailable:
            // 不支持微距：隐藏按钮并收缩宽度，让水印按钮紧贴闪光灯
            macroToggleButton.isHidden = true
            if let widthConstraint = macroToggleButton.constraints.first(where: { $0.firstAttribute == .width }) {
                widthConstraint.constant = 0
            }

        case .inactive:
            // 支持微距但未激活：半透明白色图标
            macroToggleButton.isHidden = false
            if let widthConstraint = macroToggleButton.constraints.first(where: { $0.firstAttribute == .width }) {
                widthConstraint.constant = 36
            }
            macroToggleButton.setImage(UIImage(systemName: "camera.macro", withConfiguration: smallIconConfig), for: .normal)
            macroToggleButton.tintColor = UIColor.white.withAlphaComponent(0.5)
            macroToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
            macroToggleButton.layer.cornerRadius = 18
            macroToggleButton.layer.shadowColor = UIColor.black.cgColor
            macroToggleButton.layer.shadowOpacity = 0.3
            macroToggleButton.layer.shadowOffset = CGSize(width: 0, height: 1)
            macroToggleButton.layer.shadowRadius = 4

        case .active:
            // 微距已激活：黄色高亮图标
            macroToggleButton.isHidden = false
            if let widthConstraint = macroToggleButton.constraints.first(where: { $0.firstAttribute == .width }) {
                widthConstraint.constant = 36
            }
            macroToggleButton.setImage(UIImage(systemName: "camera.macro", withConfiguration: smallIconConfig), for: .normal)
            macroToggleButton.tintColor = .systemYellow
            macroToggleButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.15)
            macroToggleButton.layer.cornerRadius = 18
            macroToggleButton.layer.shadowColor = UIColor.systemYellow.cgColor
            macroToggleButton.layer.shadowOpacity = 0.5
            macroToggleButton.layer.shadowOffset = CGSize(width: 0, height: 1)
            macroToggleButton.layer.shadowRadius = 4
        }

        // 布局刷新
        previewContainer.layoutIfNeeded()
    }
}

// MARK: - CaptureSessionManagerDelegate

@available(iOS 15.0, *)
extension CameraViewController: CaptureSessionManagerDelegate {

    func captureSessionManager(_ manager: CaptureSessionManager, didOutputBackPixelBuffer pixelBuffer: CVPixelBuffer) {
        latestBackBuffer = pixelBuffer

        // 仅后置可用时（前置被占用），直接用后置帧处理
        if let frontBuffer = latestFrontBuffer {
            viewModel.processFrames(
                backPixelBuffer: pixelBuffer,
                frontPixelBuffer: frontBuffer,
                pipConfig: cachedPIPConfig
            )
        } else if !isSessionInterrupted {
            // 没有前置帧且未中断：降级为仅后置模式
            viewModel.processFrames(
                backPixelBuffer: pixelBuffer,
                frontPixelBuffer: pixelBuffer,
                pipConfig: cachedPIPConfig
            )
        }
    }

    func captureSessionManager(_ manager: CaptureSessionManager, didOutputFrontPixelBuffer pixelBuffer: CVPixelBuffer) {
        // 仅缓存前置帧，不触发渲染。统一由后置帧回调驱动渲染管线，避免前后双队列
        // 并发执行两次完整渲染管线（每帧各触发一次，实际渲染量翻倍）导致 GPU 过载掉帧。
        latestFrontBuffer = pixelBuffer
    }

    func captureSessionManager(_ manager: CaptureSessionManager, didDetermineBackOutputSize size: CGSize) {
        // 首帧到达后触发取景框布局（仅此作用，画布尺寸由 viewDidLayoutSubviews 以固定 3:4 计算）
        DispatchQueue.main.async { [weak self] in
            self?.view.setNeedsLayout()
        }
    }

    // MARK: - Session Interruption Handlers

    func captureSessionManager(_ manager: CaptureSessionManager, wasInterrupted reason: AVCaptureSession.InterruptionReason) {
        isSessionInterrupted = true
        print("📷 Camera session interrupted (reason: \(reason.rawValue))")
        showCameraUnavailableOverlay()
    }

    func captureSessionManagerInterruptionEnded(_ manager: CaptureSessionManager) {
        isSessionInterrupted = false
        print("📷 Camera session interruption ended")
        hideCameraUnavailableOverlay()
    }

    func captureSessionManager(_ manager: CaptureSessionManager, didReceiveRuntimeError error: Error) {
        print("📷 Camera runtime error: \(error.localizedDescription)")
        showCameraErrorAlert(message: error.localizedDescription)
    }

    // MARK: - UI: Camera Unavailable State

    private func showCameraUnavailableOverlay() {
        guard cameraUnavailableOverlay == nil else { return }
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = OWLocalized("camera.unavailable")
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)

        previewContainer.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -40),
        ])

        cameraUnavailableOverlay = overlay
        previewContainer.bringSubviewToFront(overlay)
    }

    private func hideCameraUnavailableOverlay() {
        cameraUnavailableOverlay?.removeFromSuperview()
        cameraUnavailableOverlay = nil
    }

    private func showCameraErrorAlert(message: String) {
        let alert = UIAlertController(
            title: OWLocalized("camera.error"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - PIP Config (主线程安全更新，后台线程读取缓存)

    /// 从 UI 状态更新缓存的 PIP 配置（仅主线程调用）
    /// UIView 坐标系 (y-down, 原点在左上) → CIImage 坐标系 (y-up, 原点在左下)
    private func updateCachedPIPConfig(containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }

        let pipFrame = pipOverlayView.frame
        guard pipFrame.width > 0, pipFrame.height > 0 else { return }

        let widthRatio = pipFrame.width / containerSize.width
        let heightRatio = pipFrame.height / containerSize.height

        // UIView 左上角归一化坐标 (y-down)
        let uiTop = pipFrame.minY / containerSize.height
        let uiLeft = pipFrame.minX / containerSize.width

        // CIImage 坐标系 (y-up, 原点在左下)
        // ciY = 1.0 - uiTop - heightRatio
        let ciY = 1.0 - uiTop - heightRatio

        cachedPIPConfig = Compositor.PIPConfig(
            position: CGPoint(x: uiLeft, y: ciY),
            size: CGSize(width: widthRatio, height: heightRatio)
        )
    }
}
