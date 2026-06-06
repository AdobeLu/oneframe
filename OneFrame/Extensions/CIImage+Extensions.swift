//
//  CIImage+Extensions.swift
//  OneFrame
//

import CoreImage
import UIKit

extension CIImage {

    /// 将 CIImage 渲染为 CGImage
    func renderedCGImage(scale: CGFloat = UIScreen.main.scale) -> CGImage? {
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        return context.createCGImage(self, from: extent)
    }

    /// 将 CIImage 渲染为 UIImage
    func renderedUIImage(scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        guard let cgImage = renderedCGImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// 缩放到指定尺寸
    func scaled(to size: CGSize) -> CIImage {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        let scale = min(scaleX, scaleY)
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// 居中裁剪
    func centeredCropped(to size: CGSize) -> CIImage {
        let originX = (extent.width - size.width) / 2
        let originY = (extent.height - size.height) / 2
        return cropped(to: CGRect(origin: CGPoint(x: originX, y: originY), size: size))
    }
}
