//
//  WatermarkEffect.swift
//  OneFrame
//
//  水印效果 - 叠加位置/天气/设备信息/App名称
//
//  性能优化: 水印文字在分钟级别才变化，避免每帧(~30fps)重新渲染 CPU 位图
//  只在水印内容实际变化时才重新渲染，大幅降低 CPU 占用和发热
//

import CoreImage
import UIKit

final class WatermarkEffect {

    // MARK: - Properties

    /// App 名称水印: 中文环境下显示"同框相机"，其他语言显示"OneFrame"
    private var appName: String {
        LanguageManager.shared.currentLanguage == .chinese ? "同框相机" : "OneFrame"
    }
    /// 内购后移除 "同框相机" App 名称水印（付费功能）
    private var isAppNameWatermarkRemoved: Bool = false
    /// 用户手动开关时间/地点/设备信息水印（免费开关）
    private var isInfoWatermarkHidden: Bool = false

    /// 水印文字颜色
    private let textColor = UIColor.white.withAlphaComponent(0.85)
    private let shadowColor = UIColor.black.withAlphaComponent(0.5)

    // MARK: - Cache (避免每帧重新渲染位图，这是相机发烫的主要原因)

    private var cachedWatermarkImage: CIImage?
    private var cachedCanvasSize: CGSize = .zero
    private var cachedDateMinute: String = ""
    private var cachedLocationString: String = ""
    private var cachedWeatherString: String = ""
    private var cachedDeviceInfo: String = ""
    private var cachedAppName: String = ""
    private var cachedAppNameRemoved: Bool = false
    private var cachedInfoHidden: Bool = false

    /// 复用 CIFilter 实例，避免每帧通过字符串查找重建
    private lazy var sourceOverFilter: CIFilter? = {
        CIFilter(name: "CISourceOverCompositing")
    }()

    /// 复用 DateFormatter，避免每帧新建
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"  // 秒级精度，每秒刷新一次水印时间
        return f
    }()

    // MARK: - Public

    /// 内购移除 App 名称水印（"同框相机"）- 付费功能
    func setAppNameWatermarkRemoved(_ removed: Bool) {
        isAppNameWatermarkRemoved = removed
        cachedWatermarkImage = nil
    }

    /// 用户手动开关时间/地点/设备信息水印 - 免费开关
    func setInfoWatermarkHidden(_ hidden: Bool) {
        isInfoWatermarkHidden = hidden
        cachedWatermarkImage = nil
    }

    /// 生成水印 CIImage 叠加到画面上
    func apply(to image: CIImage, canvasSize: CGSize) -> CIImage {
        // 两个水印都关闭时跳过渲染
        if isAppNameWatermarkRemoved && isInfoWatermarkHidden {
            return image
        }

        let watermarkImage = getCachedWatermark(canvasSize: canvasSize)
        guard let overlay = watermarkImage else { return image }

        guard let compositor = sourceOverFilter else {
            return image
        }
        compositor.setValue(overlay, forKey: kCIInputImageKey)
        compositor.setValue(image, forKey: kCIInputBackgroundImageKey)

        return compositor.outputImage ?? image
    }

    // MARK: - Caching Logic

    /// 获取缓存的水印图像，仅在内容变化时重新渲染
    private func getCachedWatermark(canvasSize: CGSize) -> CIImage? {
        // canvasSize 变化时强制重新渲染
        let sizeChanged = canvasSize != cachedCanvasSize

        // 收集当前水印信息
        let dateStr = dateFormatter.string(from: Date())
        let locationStr = LocationService.shared.locationInfoString
        let weatherStr = WeatherService.shared.currentWeather ?? ""
        let deviceStr = "\(DeviceInfoService.shared.modelName) | \(DeviceInfoService.shared.fullSystemInfo)"
        let currentAppName = appName

        // 检查是否需要重新渲染
        let contentChanged = sizeChanged
            || dateStr != cachedDateMinute
            || locationStr != cachedLocationString
            || weatherStr != cachedWeatherString
            || deviceStr != cachedDeviceInfo
            || currentAppName != cachedAppName
            || isAppNameWatermarkRemoved != cachedAppNameRemoved
            || isInfoWatermarkHidden != cachedInfoHidden

        // 内容没变化且有缓存 → 直接返回缓存（避免每帧重绘，大幅降低 CPU/发热）
        if !contentChanged, let cached = cachedWatermarkImage {
            return cached
        }

        // 内容变化了（或首次调用），重新渲染
        let newWatermark = renderWatermark(
            canvasSize: canvasSize,
            dateStr: dateStr,
            locationStr: locationStr,
            weatherStr: weatherStr,
            deviceStr: deviceStr
        )
        cachedWatermarkImage = newWatermark
        cachedCanvasSize = canvasSize
        cachedDateMinute = dateStr
        cachedLocationString = locationStr
        cachedWeatherString = weatherStr
        cachedDeviceInfo = deviceStr
        cachedAppName = currentAppName
        cachedAppNameRemoved = isAppNameWatermarkRemoved
        cachedInfoHidden = isInfoWatermarkHidden
        return newWatermark
    }

    // MARK: - Private Rendering

    private func renderWatermark(canvasSize: CGSize, dateStr: String, locationStr: String, weatherStr: String, deviceStr: String) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // canvasSize 已是像素级，不需要再乘屏幕 scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let uiImage = renderer.image { ctx in
            let context = ctx.cgContext

            // 信息文字 (左下角) - 用户手动开关控制（免费功能）
            if !isInfoWatermarkHidden {
                var lines: [String] = [dateStr]

                if !locationStr.isEmpty && locationStr != OWLocalized("watermark.location_unknown") {
                    lines.append(locationStr)
                }
                if !weatherStr.isEmpty {
                    lines.append(weatherStr)
                }
                lines.append(deviceStr)

                renderInfoLines(lines, context: context, canvasSize: canvasSize)
            }

            // App 名称水印（右下角半透明）- 内购付费移除
            if !isAppNameWatermarkRemoved {
                renderAppNameWatermark(context: context, canvasSize: canvasSize)
            }
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
}
