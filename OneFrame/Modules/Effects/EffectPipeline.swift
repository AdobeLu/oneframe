//
//  EffectPipeline.swift
//  OneFrame
//
//  效果管线 - 协调滤镜/画框/水印/打码的顺序应用
//

import CoreImage

final class EffectPipeline {

    // MARK: - Components

    let filterEffect = FilterEffect()
    let watermarkEffect = WatermarkEffect()
    let mosaicEffect = MosaicEffect()
    let compositor = Compositor()

    // MARK: - Public

    /// 处理一帧: 背景(后摄) + 前景(前摄) → 滤镜 → 合成 → 水印 → 打码
    func processFrame(
        background: CIImage,
        foreground: CIImage?,
        mode: LayoutMode = .off,
        pipConfig: Compositor.PIPConfig? = nil
    ) -> CIImage {

        // 1. 对前后画面分别应用滤镜
        let filteredBack = filterEffect.apply(to: background)
        let filteredFront = foreground.map { filterEffect.apply(to: $0) }

        // 2. 按指定模式合成双画面
        let composited = compositor.composite(
            background: filteredBack,
            foreground: filteredFront,
            mode: mode,
            config: pipConfig
        )

        // 3. 叠加水印
        let watermarked = watermarkEffect.apply(to: composited, canvasSize: compositor.canvasSize)

        // 5. 应用打码
        let mosaiced = mosaicEffect.apply(to: watermarked, canvasSize: compositor.canvasSize)

        return mosaiced
    }

    /// 仅处理已有的合成画面（用于预览更新）
    func processImage(_ image: CIImage, canvasSize: CGSize) -> CIImage {
        let filtered = filterEffect.apply(to: image)
        let watermarked = watermarkEffect.apply(to: filtered, canvasSize: canvasSize)
        let mosaiced = mosaicEffect.apply(to: watermarked, canvasSize: canvasSize)
        return mosaiced
    }

    /// 高级会员：移除 "同框相机" App 名称水印
    func setPremium(_ premium: Bool) {
        watermarkEffect.setPremium(premium)
    }

    /// 用户手动开关品牌 Logo 水印（仅高级会员生效）
    func setBrandWatermarkHidden(_ hidden: Bool) {
        watermarkEffect.setBrandWatermarkHidden(hidden)
    }

    /// 用户手动开关时间/地点/设备信息水印
    func setInfoWatermarkHidden(_ hidden: Bool) {
        watermarkEffect.setInfoWatermarkHidden(hidden)
    }
}
