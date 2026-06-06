//
//  Compositor.swift
//  OneFrame
//
//  双画面合成器 - 将前后摄像头画面合成为一帧
//

import CoreImage
import UIKit

final class Compositor {

    // MARK: - Properties

    /// 输出画布尺寸
    private(set) var canvasSize: CGSize

    /// PIP 配置
    /// position 使用左上角锚点，归一化到 [0,1] 范围，基于 CIImage 坐标系 (y-up, 原点在左下)
    struct PIPConfig {
        var position: CGPoint = CGPoint(x: 0.69, y: 0.38)
        var size: CGSize = CGSize(width: 0.30, height: 0.40)
        var cornerRadius: CGFloat = 0.02
    }

    var pipConfig = PIPConfig(
        position: CGPoint(x: 0.69, y: 0.38),
        size: CGSize(width: 0.30, height: 0.40)
    )

    // MARK: - Init

    init(canvasSize: CGSize = CGSize(width: 1080, height: 1920)) {
        self.canvasSize = canvasSize
    }

    // MARK: - Public

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    /// 合成前后画面
    /// foreground 为 nil 时仅返回缩放后的背景（PIP 关闭）
    func composite(
        background: CIImage,    // 后置摄像头画面
        foreground: CIImage?,   // 前置摄像头画面(PIP)，nil 表示关闭 PIP
        config: PIPConfig? = nil
    ) -> CIImage {
        let cfg = config ?? pipConfig

        // 1. 背景 AspectFill 到画布，居中裁剪
        let scaledBackground = background.scaledToFill(size: canvasSize)

        // 前景为空时直接返回背景（PIP 关闭）
        guard let foreground = foreground else {
            return scaledBackground
        }

        // 2. 计算 PIP 实际尺寸
        let pipWidth = canvasSize.width * cfg.size.width
        let pipHeight = canvasSize.height * cfg.size.height
        let pipSize = CGSize(width: pipWidth, height: pipHeight)

        // 3. 前景缩放到 PIP 尺寸（AspectFill 居中裁剪）
        let scaledForeground = foreground.scaledToFill(size: pipSize)

        // 4. PIP 位置（从归一化转实际像素）
        //    position 表示 CIImage 坐标系中的左上角 (y-up, 原点左下)
        let pipOriginX = canvasSize.width * cfg.position.x
        let pipOriginY = canvasSize.height * cfg.position.y

        var pipOrigin = CGPoint(x: pipOriginX, y: pipOriginY)

        // 边界保护
        pipOrigin.x = max(0, min(canvasSize.width - pipWidth, pipOrigin.x))
        pipOrigin.y = max(0, min(canvasSize.height - pipHeight, pipOrigin.y))

        // 5. 圆角裁剪 PIP
        let roundedForeground = applyCornerRadius(
            to: scaledForeground,
            radius: cfg.cornerRadius * canvasSize.width,
            size: pipSize
        )

        // 6. 将 PIP 移动到指定位置
        let movedForeground = roundedForeground.transformed(
            by: CGAffineTransform(translationX: pipOrigin.x, y: pipOrigin.y)
        )

        // 7. 合成
        guard let compositor = CIFilter(name: "CISourceOverCompositing") else {
            return scaledBackground
        }

        compositor.setValue(movedForeground, forKey: kCIInputImageKey)
        compositor.setValue(scaledBackground, forKey: kCIInputBackgroundImageKey)

        return compositor.outputImage?.cropped(to: CGRect(origin: .zero, size: canvasSize)) ?? scaledBackground
    }

    // MARK: - Private

    private func applyCornerRadius(to image: CIImage, radius: CGFloat, size: CGSize) -> CIImage {
        // 使用圆形遮罩实现圆角
        let maskGenerator = CIFilter(name: "CIRoundedRectangleGenerator")!
        maskGenerator.setValue(CIVector(x: 0, y: 0, z: size.width, w: size.height), forKey: "inputExtent")
        maskGenerator.setValue(radius, forKey: "inputRadius")

        guard let maskImage = maskGenerator.outputImage else { return image }

        let blendFilter = CIFilter(name: "CIBlendWithAlphaMask")!
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? image
    }
}

// MARK: - CIImage Extension (扩展方法)

private extension CIImage {
    /// 缩放并居中裁剪到目标尺寸 (AspectFill)
    /// 使用 CILanczosScaleTransform 进行高质量缩放，直接裁剪中心区域
    func scaledToFill(size targetSize: CGSize) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return self }
        let scale = max(targetSize.width / extent.width, targetSize.height / extent.height)

        // 使用 CILanczosScaleTransform 可靠缩放，避免手动仿射变换坐标系陷阱
        let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
        scaleFilter.setValue(self, forKey: kCIInputImageKey)
        scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
        scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let scaled = scaleFilter.outputImage else { return self }

        // 从缩放后图像的正中心裁剪出目标尺寸
        let cropX = (scaled.extent.width - targetSize.width) / 2 + scaled.extent.origin.x
        let cropY = (scaled.extent.height - targetSize.height) / 2 + scaled.extent.origin.y
        let cropped = scaled.cropped(to: CGRect(x: cropX, y: cropY, width: targetSize.width, height: targetSize.height))

        // 将裁剪后的图像原点平移到 (0,0)，否则非零 origin 在合成时会产生黑边
        return cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.origin.x, y: -cropped.extent.origin.y))
    }
}
