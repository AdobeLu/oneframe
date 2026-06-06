//
//  MosaicEffect.swift
//  OneFrame
//
//  打码效果 - 手动框选 + CIPixellate 马赛克
//

import CoreImage
import UIKit

struct MosaicRegion {
    let id: String
    /// 归一化坐标 (0~1)，基于合成帧尺寸
    let normalizedRect: CGRect
}

final class MosaicEffect {

    // 当前所有打码区域（归一化坐标）
    private var regions: [MosaicRegion] = []

    /// 马赛克像素大小
    var pixelScale: CGFloat = 12.0

    // MARK: - Public

    /// 添加一个打码区域
    func addRegion(normalizedRect: CGRect) -> MosaicRegion {
        let region = MosaicRegion(
            id: UUID().uuidString,
            normalizedRect: normalizedRect
        )
        regions.append(region)
        return region
    }

    /// 移除指定打码区域
    func removeRegion(id: String) {
        regions.removeAll { $0.id == id }
    }

    /// 移除所有打码区域
    func removeAllRegions() {
        regions.removeAll()
    }

    var hasRegions: Bool { !regions.isEmpty }

    var allRegions: [MosaicRegion] { regions }

    /// 应用打码效果到图像
    func apply(to image: CIImage, canvasSize: CGSize) -> CIImage {
        guard !regions.isEmpty else { return image }

        var result = image

        for region in regions {
            // 将归一化坐标转为实际像素坐标
            let rect = CGRect(
                x: region.normalizedRect.origin.x * canvasSize.width,
                y: region.normalizedRect.origin.y * canvasSize.height,
                width: region.normalizedRect.width * canvasSize.width,
                height: region.normalizedRect.height * canvasSize.height
            )

            result = applyMosaic(to: result, rect: rect)
        }

        return result
    }

    // MARK: - Private

    private func applyMosaic(to image: CIImage, rect: CGRect) -> CIImage {
        // 裁剪出打码区域
        let cropped = image.cropped(to: rect)

        // 缩小小图再放大实现马赛克效果（比 CIPixellate 更可控）
        let shrinkScale: CGFloat = 1.0 / pixelScale
        let shrinkTransform = CGAffineTransform(scaleX: shrinkScale, y: shrinkScale)
        let shrunk = cropped.transformed(by: shrinkTransform)

        // 放大回原始尺寸（用 nearest neighbor 采样）
        let enlargeTransform = CGAffineTransform(scaleX: pixelScale, y: pixelScale)
        let enlarged = shrunk.transformed(by: enlargeTransform)

        // 将马赛克部分合成回原图
        let composited = enlarged.composited(over: image)
            .cropped(to: image.extent)

        return composited
    }
}
