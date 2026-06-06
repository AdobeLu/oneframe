//
//  PIPOverlayView.swift
//  OneFrame
//
//  前置摄像头画中画小窗 - 支持拖动/缩放（仅作为定位指示器）
//

import UIKit

final class PIPOverlayView: UIView {

    // MARK: - Constants

    private static let defaultSizeRatio: CGFloat = 0.3      // 默认占屏幕宽度的 30%
    private static let minSizeRatio: CGFloat = 0.15          // 最小尺寸
    private static let maxSizeRatio: CGFloat = 0.45          // 最大尺寸
    private static let cornerRadius: CGFloat = 12
    private static let borderWidth: CGFloat = 3

    // MARK: - Properties

    /// 当前的缩放比例（相对屏幕宽度）
    private(set) var currentSizeRatio: CGFloat = defaultSizeRatio

    /// PIP 内部的实时预览图（由外部注入，已合成的画中画裁剪）
    private var previewImageView: UIImageView?

    /// 是否隐藏预览图（仅做拖拽指示器时设为 true，避免与合成画面中的 PIP 重复）
    var isPreviewHidden: Bool = false {
        didSet { previewImageView?.isHidden = isPreviewHidden }
    }

    /// 位置/尺寸变化时回调（用于同步合成管线配置）
    var onPositionChanged: (() -> Void)?

    // MARK: - Gesture recognizers

    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        layer.cornerRadius = Self.cornerRadius
        layer.masksToBounds = false
        layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        layer.borderWidth = Self.borderWidth

        // 预览图（由外部设置）- 需要裁剪圆角
        let iv = UIImageView(frame: bounds)
        iv.contentMode = .scaleAspectFill
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.clipsToBounds = true
        iv.layer.cornerRadius = Self.cornerRadius - Self.borderWidth
        addSubview(iv)
        previewImageView = iv

        // 阴影（masksToBounds = false 时生效）
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 12
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewImageView?.frame = bounds
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
    }

    // MARK: - Display

    /// 更新 PIP 窗内显示的预览图像
    func updatePreview(image: UIImage?) {
        previewImageView?.image = image
    }

    func resetPosition(to containerSize: CGSize) {
        let pipSize = Self.calculateSize(for: containerSize, ratio: currentSizeRatio)
        let margin: CGFloat = 16
        let originX = containerSize.width - pipSize.width - margin
        let originY = containerSize.height - pipSize.height - margin - 100
        frame = CGRect(origin: CGPoint(x: originX, y: originY), size: pipSize)
    }

    // MARK: - Gesture Handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }

        let translation = gesture.translation(in: superview)

        if gesture.state == .changed {
            var newCenter = CGPoint(
                x: center.x + translation.x,
                y: center.y + translation.y
            )

            let halfWidth = bounds.width / 2
            let halfHeight = bounds.height / 2
            let safeTop: CGFloat = superview.safeAreaInsets.top + 44
            let safeBottom: CGFloat = superview.safeAreaInsets.bottom + 80

            newCenter.x = max(halfWidth, min(superview.bounds.width - halfWidth, newCenter.x))
            newCenter.y = max(safeTop + halfHeight, min(superview.bounds.height - safeBottom - halfHeight, newCenter.y))

            center = newCenter
            gesture.setTranslation(.zero, in: superview)
        }

        if gesture.state == .ended {
            let velocity = gesture.velocity(in: superview)
            let targetCenter = snapTargetCenter(velocity: velocity, in: superview)
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.center = targetCenter
            }
            onPositionChanged?()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let superview = superview else { return }

        if gesture.state == .changed {
            let newRatio = currentSizeRatio * gesture.scale
            let clampedRatio = max(Self.minSizeRatio, min(Self.maxSizeRatio, newRatio))

            let oldSize = bounds.size
            let newSize = Self.calculateSize(for: superview.bounds.size, ratio: clampedRatio)

            let dx = (oldSize.width - newSize.width) / 2
            let dy = (oldSize.height - newSize.height) / 2
            frame = CGRect(
                x: frame.origin.x + dx,
                y: frame.origin.y + dy,
                width: newSize.width,
                height: newSize.height
            )

            gesture.scale = 1.0
        }

        if gesture.state == .ended {
            currentSizeRatio = bounds.width / superview.bounds.width
            onPositionChanged?()
        }
    }

    // MARK: - Private Helpers

    private static func calculateSize(for containerSize: CGSize, ratio: CGFloat) -> CGSize {
        let width = containerSize.width * ratio
        let height = width * (4.0 / 3.0)
        return CGSize(width: width, height: height)
    }

    private func snapTargetCenter(velocity: CGPoint, in superview: UIView) -> CGPoint {
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let safeTop: CGFloat = superview.safeAreaInsets.top + 44
        let safeBottom: CGFloat = superview.safeAreaInsets.bottom + 80

        let midX = superview.bounds.width / 2
        let targetX: CGFloat

        if abs(velocity.x) > 200 {
            targetX = velocity.x > 0
                ? superview.bounds.width - halfWidth - 16
                : halfWidth + 16
        } else {
            targetX = center.x < midX ? halfWidth + 16 : superview.bounds.width - halfWidth - 16
        }

        var targetY = center.y
        targetY = max(safeTop + halfHeight, min(superview.bounds.height - safeBottom - halfHeight, targetY))

        return CGPoint(x: targetX, y: targetY)
    }
}
