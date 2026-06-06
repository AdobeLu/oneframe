//
//  FrameEffect.swift
//  OneFrame
//
//  画框效果 - 叠加 PNG 装饰画框到合成画面
//

import CoreImage
import UIKit

enum FrameStyle: String, CaseIterable {
    case none = "无"
    case classic = "经典白"
    case vintage = "复古金"
    case modern = "现代极简"
    case polaroid = "拍立得"

    /// 画框图片名称（Resources/Frames/ 下的文件）
    var assetName: String? {
        switch self {
        case .none: return nil
        case .classic: return "frame_classic"
        case .vintage: return "frame_vintage"
        case .modern: return "frame_modern"
        case .polaroid: return "frame_polaroid"
        }
    }
}

final class FrameEffect {

    private(set) var currentFrame: FrameStyle = .none

    // 缓存的画框 CIImage
    private var cachedFrameImage: CIImage?
    private var cachedFrameName: String?

    func setFrame(_ frame: FrameStyle) {
        currentFrame = frame
        cachedFrameImage = nil
        cachedFrameName = nil
    }

    /// 将画框叠加到图像上
    func apply(to image: CIImage, canvasSize: CGSize) -> CIImage {
        guard currentFrame != .none else { return image }

        let frameImage = loadFrameImage(size: canvasSize)
        guard let frame = frameImage else { return image }

        // 将图像放置到画布上（居中）
        let imageScale = min(
            canvasSize.width / image.extent.width,
            canvasSize.height / image.extent.height
        ) * 0.85 // 85% 占比留出边框空间

        let scaledWidth = image.extent.width * imageScale
        let scaledHeight = image.extent.height * imageScale
        let imageX = (canvasSize.width - scaledWidth) / 2
        let imageY = (canvasSize.height - scaledHeight) / 2

        let transformedImage = image.transformed(by: CGAffineTransform(
            translationX: imageX - image.extent.origin.x,
            y: imageY - image.extent.origin.y
        ).scaledBy(x: imageScale, y: imageScale))

        // 合成: 画框在上，图像在下
        guard let compositor = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        compositor.setValue(transformedImage, forKey: kCIInputImageKey)
        compositor.setValue(frame, forKey: kCIInputBackgroundImageKey)

        return compositor.outputImage ?? image
    }

    // MARK: - Private

    private func loadFrameImage(size: CGSize) -> CIImage? {
        guard let assetName = currentFrame.assetName else { return nil }

        // 尝试从 Assets 加载
        if let uiImage = UIImage(named: assetName) {
            let frameCIImage: CIImage
            if let cgImage = uiImage.cgImage {
                frameCIImage = CIImage(cgImage: cgImage)
            } else {
                frameCIImage = CIImage(image: uiImage) ?? CIImage()
            }
            // 缩放到画布尺寸
            let scaleX = size.width / frameCIImage.extent.width
            let scaleY = size.height / frameCIImage.extent.height
            let scale = max(scaleX, scaleY)
            return frameCIImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // 如果没有图片资源，生成一个简单的纯色边框
        return generateDefaultFrame(size: size)
    }

    /// 默认画框（纯色边框）
    private func generateDefaultFrame(size: CGSize) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // canvasSize 已是像素级，不需要再乘屏幕 scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let uiImage = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            // 外部背景
            UIColor.white.setFill()
            ctx.fill(rect)

            // 内部透明区域（画框内沿）
            let margin: CGFloat = 20
            let innerRect = rect.insetBy(dx: margin, dy: margin)
            UIColor.black.setFill()
            ctx.fill(innerRect)

            // 金色边框描边
            let borderPath = UIBezierPath(rect: innerRect.insetBy(dx: -2, dy: -2))
            UIColor(red: 0.8, green: 0.7, blue: 0.4, alpha: 1.0).setStroke()
            borderPath.lineWidth = 4
            borderPath.stroke()
        }

        return CIImage(image: uiImage)
    }
}
