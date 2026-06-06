//
//  WatermarkEffect.swift
//  OneFrame
//
//  水印效果 - 叠加位置/天气/设备信息/App名称
//

import CoreImage
import UIKit

final class WatermarkEffect {

    // MARK: - Properties

    /// App 名称水印: 中文环境下显示"同框相机"，其他语言显示"OneFrame"
    private var appName: String {
        LanguageManager.shared.currentLanguage == .chinese ? "同框相机" : "OneFrame"
    }
    private var isWatermarkRemoved: Bool = false // 内购后变 true

    /// 水印文字颜色
    private let textColor = UIColor.white.withAlphaComponent(0.85)
    private let shadowColor = UIColor.black.withAlphaComponent(0.5)

    // MARK: - Public

    func setWatermarkRemoved(_ removed: Bool) {
        isWatermarkRemoved = removed
    }

    /// 生成水印 CIImage 叠加到画面上
    func apply(to image: CIImage, canvasSize: CGSize) -> CIImage {
        let watermarkImage = renderWatermark(canvasSize: canvasSize)
        guard let overlay = watermarkImage else { return image }

        guard let compositor = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        compositor.setValue(overlay, forKey: kCIInputImageKey)
        compositor.setValue(image, forKey: kCIInputBackgroundImageKey)

        return compositor.outputImage ?? image
    }

    // MARK: - Private

    private func renderWatermark(canvasSize: CGSize) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // canvasSize 已是像素级，不需要再乘屏幕 scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let uiImage = renderer.image { ctx in
            let context = ctx.cgContext

            // 获取水印信息
            let dateStr = formatDate()
            let locationStr = LocationService.shared.locationInfoString
            let deviceStr = "\(DeviceInfoService.shared.modelName) | \(DeviceInfoService.shared.fullSystemInfo)"
            let weatherStr = WeatherService.shared.currentWeather ?? ""

            var lines: [String] = [dateStr]

            if !locationStr.isEmpty && locationStr != OWLocalized("watermark.location_unknown") {
                lines.append(locationStr)
            }
            if !weatherStr.isEmpty {
                lines.append(weatherStr)
            }
            lines.append(deviceStr)

            // App 名称水印（右下角半透明）
            if !isWatermarkRemoved {
                renderAppNameWatermark(context: context, canvasSize: canvasSize)
            }

            // 信息文字 (左下角)
            renderInfoLines(lines, context: context, canvasSize: canvasSize)
        }

        return CIImage(image: uiImage)
    }

    private func renderAppNameWatermark(context: CGContext, canvasSize: CGSize) {
        let fontSize: CGFloat = min(canvasSize.width * 0.1, 45)
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            .shadow: shadow,
        ]

        let textSize = appName.size(withAttributes: attributes)
        let margin: CGFloat = 24
        // UIKit 坐标系原点在左上角，y 向下
        let x = canvasSize.width - textSize.width - margin
        let y = canvasSize.height - textSize.height - margin

        appName.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func renderInfoLines(_ lines: [String], context: CGContext, canvasSize: CGSize) {
        let fontSize: CGFloat = min(canvasSize.width * 0.04, 30)
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)

        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .shadow: shadow
        ]

        let margin: CGFloat = 16
        let lineHeight = fontSize * 1.5
        let totalHeight = lineHeight * CGFloat(lines.count)
        let startY = canvasSize.height - totalHeight - margin

        for (index, line) in lines.enumerated() {
            let y = startY + lineHeight * CGFloat(index)
            line.draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: attributes
            )
        }
    }

    private func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
