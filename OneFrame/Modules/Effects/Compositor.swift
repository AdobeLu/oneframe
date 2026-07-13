//
//  Compositor.swift
//  OneFrame
//
//  双画面合成器 - 支持多种布局模式（画中画 / 上下分屏 / 左右分屏）
//

import CoreImage
import UIKit

/// 双画面布局模式
enum LayoutMode: Int, CaseIterable {
    /// 仅显示后置画面（不显示前置）
    case off
    /// 画中画小窗（自由拖动/缩放）
    case pip
    /// 上下分屏（上：前置，下：后置）
    case splitVertical
    /// 左右分屏（左：后置，右：前置）
    case splitHorizontal

    /// 下一个布局模式（循环切换）
    var next: LayoutMode {
        let all = LayoutMode.allCases
        let idx = (all.firstIndex(of: self)! + 1) % all.count
        return all[idx]
    }

    /// 按钮图标 SF Symbol 名称
    var sfSymbolName: String {
        switch self {
        case .off:             return "rectangle.fill"
        case .pip:             return "pip.enter"
        case .splitVertical:   return "rectangle.split.2x1"
        case .splitHorizontal: return "rectangle.split.1x2"
        }
    }
}

final class Compositor {

    // MARK: - Properties

    /// 输出画布尺寸
    private(set) var canvasSize: CGSize

    /// PIP 配置（仅在 .pip 模式下生效）
    struct PIPConfig {
        var position: CGPoint = CGPoint(x: 0.69, y: 0.38)
        var size: CGSize = CGSize(width: 0.30, height: 0.40)
        var cornerRadius: CGFloat = 0.02
    }

    var pipConfig = PIPConfig(
        position: CGPoint(x: 0.69, y: 0.38),
        size: CGSize(width: 0.30, height: 0.40)
    )

    /// 分屏模式下的分割比例（前后画面各占比例，0.5 = 各半）
    private static let splitRatio: CGFloat = 0.5

    // MARK: - Reusable CIFilters

    private lazy var sourceOverFilter: CIFilter? = {
        CIFilter(name: "CISourceOverCompositing")
    }()

    private lazy var blendWithMaskFilter: CIFilter? = {
        CIFilter(name: "CIBlendWithAlphaMask")
    }()

    private lazy var roundedRectGenerator: CIFilter? = {
        CIFilter(name: "CIRoundedRectangleGenerator")
    }()

    private lazy var lanczosScaleFilter: CIFilter? = {
        CIFilter(name: "CILanczosScaleTransform")
    }()

    // MARK: - Init

    init(canvasSize: CGSize = CGSize(width: 1080, height: 1920)) {
        self.canvasSize = canvasSize
    }

    // MARK: - Public

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    /// 合成前后画面
    /// - Parameters:
    ///   - background: 后置摄像头画面
    ///   - foreground: 前置摄像头画面（nil 时仅显示背景）
    ///   - mode: 布局模式
    ///   - config: PIP 配置（仅 .pip 模式生效）
    func composite(
        background: CIImage,
        foreground: CIImage?,
        mode: LayoutMode = .off,
        config: PIPConfig? = nil
    ) -> CIImage {
        // 前景为空或模式为 off → 仅返回背景
        guard let foreground = foreground, mode != .off else {
            return background.scaledToFill(size: canvasSize, scaleFilter: lanczosScaleFilter)
        }

        switch mode {
        case .off:
            return background.scaledToFill(size: canvasSize, scaleFilter: lanczosScaleFilter)
        case .pip:
            return compositePIP(background: background, foreground: foreground, config: config ?? pipConfig)
        case .splitVertical:
            return compositeSplitVertical(background: background, foreground: foreground)
        case .splitHorizontal:
            return compositeSplitHorizontal(background: background, foreground: foreground)
        }
    }

    // MARK: - PIP 画中画

    private func compositePIP(
        background: CIImage,
        foreground: CIImage,
        config: PIPConfig
    ) -> CIImage {
        let cfg = config

        // 1. 背景 AspectFill 到画布
        let scaledBackground = background.scaledToFill(size: canvasSize, scaleFilter: lanczosScaleFilter)

        // 2. 计算 PIP 实际尺寸
        let pipWidth = canvasSize.width * cfg.size.width
        let pipHeight = canvasSize.height * cfg.size.height
        let pipSize = CGSize(width: pipWidth, height: pipHeight)

        // 3. 前景缩放
        let scaledForeground = foreground.scaledToFill(size: pipSize, scaleFilter: lanczosScaleFilter)

        // 4. PIP 位置
        let pipOriginX = canvasSize.width * cfg.position.x
        let pipOriginY = canvasSize.height * cfg.position.y
        let pipOriginX_clamped = max(0, min(canvasSize.width - pipWidth, pipOriginX))
        let pipOriginY_clamped = max(0, min(canvasSize.height - pipHeight, pipOriginY))

        // 5. 圆角裁剪
        let roundedForeground = applyCornerRadius(
            to: scaledForeground,
            radius: cfg.cornerRadius * canvasSize.width,
            size: pipSize
        )

        // 6. 移动到指定位置
        let movedForeground = roundedForeground.transformed(
            by: CGAffineTransform(translationX: pipOriginX_clamped, y: pipOriginY_clamped)
        )

        // 7. 合成
        guard let compositorFilter = sourceOverFilter else { return scaledBackground }
        compositorFilter.setValue(movedForeground, forKey: kCIInputImageKey)
        compositorFilter.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)

        return compositorFilter.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? scaledBackground
    }

    // MARK: - 上下分屏 (上: 前置, 下: 后置)

    private func compositeSplitVertical(
        background: CIImage,
        foreground: CIImage
    ) -> CIImage {
        let halfHeight = canvasSize.height * Self.splitRatio
        let topSize = CGSize(width: canvasSize.width, height: halfHeight)
        let bottomSize = CGSize(width: canvasSize.width, height: canvasSize.height - halfHeight)

        // 上：前置画面 AspectFill 到上半区域
        let topImage = foreground.scaledToFill(size: topSize, scaleFilter: lanczosScaleFilter)
            .transformed(by: CGAffineTransform(translationX: 0, y: canvasSize.height - halfHeight))

        // 下：后置画面 AspectFill 到下半区域
        let bottomImage = background.scaledToFill(size: bottomSize, scaleFilter: lanczosScaleFilter)

        // 先合成下半部分（背景）+ 上半部分（前景）
        guard let compositorFilter = sourceOverFilter else { return bottomImage }
        compositorFilter.setValue(topImage, forKey: kCIInputImageKey)
        compositorFilter.setValue(bottomImage, forKey: kCIInputBackgroundImageKey)

        return compositorFilter.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? bottomImage
    }

    // MARK: - 左右分屏 (左: 后置, 右: 前置)

    private func compositeSplitHorizontal(
        background: CIImage,
        foreground: CIImage
    ) -> CIImage {
        let halfWidth = canvasSize.width * Self.splitRatio
        let leftSize = CGSize(width: halfWidth, height: canvasSize.height)
        let rightSize = CGSize(width: canvasSize.width - halfWidth, height: canvasSize.height)

        // 左：后置画面 AspectFill
        let leftImage = background.scaledToFill(size: leftSize, scaleFilter: lanczosScaleFilter)

        // 右：前置画面 AspectFill + 平移到右侧
        let rightImage = foreground.scaledToFill(size: rightSize, scaleFilter: lanczosScaleFilter)
            .transformed(by: CGAffineTransform(translationX: halfWidth, y: 0))

        guard let compositorFilter = sourceOverFilter else { return leftImage }
        compositorFilter.setValue(rightImage, forKey: kCIInputImageKey)
        compositorFilter.setValue(leftImage, forKey: kCIInputBackgroundImageKey)

        return compositorFilter.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? leftImage
    }

    // MARK: - Private

    private func applyCornerRadius(to image: CIImage, radius: CGFloat, size: CGSize) -> CIImage {
        guard let maskGenerator = roundedRectGenerator,
              let blendFilter = blendWithMaskFilter else {
            return image
        }
        maskGenerator.setValue(CIVector(x: 0, y: 0, z: size.width, w: size.height), forKey: "inputExtent")
        maskGenerator.setValue(radius, forKey: "inputRadius")

        guard let maskImage = maskGenerator.outputImage else { return image }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }
}

// MARK: - CIImage Extension

private extension CIImage {
    /// 缩放并居中裁剪到目标尺寸 (AspectFill)
    func scaledToFill(size targetSize: CGSize, scaleFilter: CIFilter? = nil) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return self }
        let scale = max(targetSize.width / extent.width, targetSize.height / extent.height)

        let filter = scaleFilter ?? CIFilter(name: "CILanczosScaleTransform")!
        filter.setValue(self, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let scaled = filter.outputImage else { return self }

        let cropX = (scaled.extent.width - targetSize.width) / 2 + scaled.extent.origin.x
        let cropY = (scaled.extent.height - targetSize.height) / 2 + scaled.extent.origin.y
        let cropped = scaled.cropped(to: CGRect(x: cropX, y: cropY, width: targetSize.width, height: targetSize.height))

        return cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.origin.x, y: -cropped.extent.origin.y))
    }
}
