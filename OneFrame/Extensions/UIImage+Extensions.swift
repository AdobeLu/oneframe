//
//  UIImage+Extensions.swift
//  OneFrame
//

import UIKit

extension UIImage {

    /// 缩放图片到指定尺寸
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// 生成指定尺寸的缩略图
    func thumbnail(size: CGSize) -> UIImage? {
        let aspectRatio = self.size.width / self.size.height
        var targetSize = size
        if aspectRatio > 1 {
            targetSize = CGSize(width: size.width, height: size.width / aspectRatio)
        } else {
            targetSize = CGSize(width: size.height * aspectRatio, height: size.height)
        }
        return resized(to: targetSize)
    }
}
