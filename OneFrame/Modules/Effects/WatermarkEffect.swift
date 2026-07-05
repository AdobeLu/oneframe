//
//  WatermarkEffect.swift
//  OneFrame
//
//  水印效果 - 左下角信息水印 + 右下角品牌名
//  布局: 日期时间 | 经纬度(N/E) | 城市 · 天气 · 设备
//
//  性能优化: 水印文字每秒变化一次，内容不变时复用缓存位图，避免每帧重绘
//

import CoreImage
import UIKit

final class WatermarkEffect {

    // MARK: - Properties

    /// App 名称水印: 中文环境下显示"同框相机"，其他语言显示"OneFrame"
    private var appName: String {
        LanguageManager.shared.currentLanguage == .chinese ? "同框相机" : "OneFrame"
    }
    /// 高级会员后移除 "同框相机" App 名称水印
    private var isPremium: Bool = false
    /// 用户手动开关品牌 Logo 水印（仅高级会员生效）
    private var isBrandWatermarkHidden: Bool = false
    /// 用户手动开关时间/地点/设备信息水印（免费开关）
    private var isInfoWatermarkHidden: Bool = false

    /// 文字颜色
    private let textColor = UIColor.white
    private let dimTextColor = UIColor.white.withAlphaComponent(0.82)

    // MARK: - Cache

    private var cachedWatermarkImage: CIImage?
    private var cachedCanvasSize: CGSize = .zero
    private var cachedDateStr: String = ""
    private var cachedTimeStr: String = ""
    private var cachedCoordinateStr: String = ""
    private var cachedCityName: String = ""
    private var cachedWeatherStr: String = ""
    private var cachedDeviceInfo: String = ""
    private var cachedAppName: String = ""
    private var cachedPremiumStatus: Bool = false
    private var cachedBrandHidden: Bool = false
    private var cachedInfoHidden: Bool = false

    /// 上次格式化时间的整数秒，用于避免每帧调用 DateFormatter
    /// DateFormatter 开销虽不大，但 30fps × 2 次/帧 = 每秒 60 次纯属浪费
    private var cachedSecond: Int = -1

    private lazy var sourceOverFilter: CIFilter? = {
        CIFilter(name: "CISourceOverCompositing")
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月dd日"
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Public

    func setPremium(_ premium: Bool) {
        isPremium = premium
        cachedWatermarkImage = nil
    }

    func setBrandWatermarkHidden(_ hidden: Bool) {
        isBrandWatermarkHidden = hidden
        cachedWatermarkImage = nil
    }

    func setInfoWatermarkHidden(_ hidden: Bool) {
        isInfoWatermarkHidden = hidden
        cachedWatermarkImage = nil
    }

    func apply(to image: CIImage, canvasSize: CGSize) -> CIImage {
        // 高级会员关闭了品牌水印 且 信息水印也关闭 → 不渲染任何水印
        if isInfoWatermarkHidden && (isPremium && isBrandWatermarkHidden) {
            return image
        }

        let watermarkImage = getCachedWatermark(canvasSize: canvasSize)
        guard let overlay = watermarkImage else { return image }

        guard let compositor = sourceOverFilter else { return image }
        compositor.setValue(overlay, forKey: kCIInputImageKey)
        compositor.setValue(image, forKey: kCIInputBackgroundImageKey)

        return compositor.outputImage ?? image
    }

    // MARK: - Caching Logic

    private func getCachedWatermark(canvasSize: CGSize) -> CIImage? {
        let sizeChanged = canvasSize != cachedCanvasSize

        // 秒级时间戳快速路径：时间每秒才变一次，避免每帧 2 次 DateFormatter
        // 直接用 Calendar 取秒分量，比 DateFormatter 开销低一个数量级
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let currentSecond = components.second ?? 0

        // 每秒只执行一次 DateFormatter
        let dateStr: String
        let timeStr: String
        if currentSecond != cachedSecond || sizeChanged {
            dateStr = dateFormatter.string(from: now)
            timeStr = timeFormatter.string(from: now)
        } else {
            dateStr = cachedDateStr
            timeStr = cachedTimeStr
        }

        let coordinateStr = LocationService.shared.coordinateString
        let cityName = LocationService.shared.cityName
        let weatherStr = WeatherService.shared.currentWeather ?? ""
        let deviceStr = "\(DeviceInfoService.shared.modelName) | \(DeviceInfoService.shared.fullSystemInfo)"
        let currentAppName = appName

        let contentChanged = sizeChanged
            || dateStr != cachedDateStr
            || timeStr != cachedTimeStr
            || coordinateStr != cachedCoordinateStr
            || cityName != cachedCityName
            || weatherStr != cachedWeatherStr
            || deviceStr != cachedDeviceInfo
            || currentAppName != cachedAppName
            || isPremium != cachedPremiumStatus
            || isBrandWatermarkHidden != cachedBrandHidden
            || isInfoWatermarkHidden != cachedInfoHidden

        if !contentChanged, let cached = cachedWatermarkImage {
            return cached
        }

        let newWatermark = renderWatermark(
            canvasSize: canvasSize,
            dateStr: dateStr,
            timeStr: timeStr,
            coordinateStr: coordinateStr,
            cityName: cityName,
            weatherStr: weatherStr,
            deviceStr: deviceStr
        )
        cachedWatermarkImage = newWatermark
        cachedCanvasSize = canvasSize
        cachedDateStr = dateStr
        cachedTimeStr = timeStr
        cachedSecond = currentSecond
        cachedCoordinateStr = coordinateStr
        cachedCityName = cityName
        cachedWeatherStr = weatherStr
        cachedDeviceInfo = deviceStr
        cachedAppName = currentAppName
        cachedPremiumStatus = isPremium
        cachedBrandHidden = isBrandWatermarkHidden
        cachedInfoHidden = isInfoWatermarkHidden
        return newWatermark
    }

    // MARK: - Rendering

    private func renderWatermark(
        canvasSize: CGSize,
        dateStr: String,
        timeStr: String,
        coordinateStr: String,
        cityName: String,
        weatherStr: String,
        deviceStr: String
    ) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let uiImage = renderer.image { rc in
            let ctx = rc.cgContext

            if !isInfoWatermarkHidden {
                renderInfoBlock(
                    context: ctx,
                    canvasSize: canvasSize,
                    dateStr: dateStr,
                    timeStr: timeStr,
                    coordinateStr: coordinateStr,
                    cityName: cityName,
                    weatherStr: weatherStr,
                    deviceStr: deviceStr
                )
            }

            if !(isPremium && isBrandWatermarkHidden) {
                renderAppNameWatermark(context: ctx, canvasSize: canvasSize)
            }
        }
        return CIImage(image: uiImage)
    }

    // MARK: - 左下角信息块

    private func renderInfoBlock(
        context: CGContext,
        canvasSize: CGSize,
        dateStr: String,
        timeStr: String,
        coordinateStr: String,
        cityName: String,
        weatherStr: String,
        deviceStr: String
    ) {
        let margin: CGFloat = max(canvasSize.width * 0.045, 20)
        let bottomMargin: CGFloat = max(canvasSize.height * 0.08, 50)

        // 字体大小 (相对画布宽度自适应)
        let dateFontSize: CGFloat = max(canvasSize.width * 0.055, 28)
        let timeFontSize: CGFloat = max(canvasSize.width * 0.036, 18)
        let coordFontSize: CGFloat = max(canvasSize.width * 0.030, 15)
        let detailFontSize: CGFloat = max(canvasSize.width * 0.026, 13)

        // 阴影
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowOffset = CGSize(width: 0.5, height: 0.5)
        shadow.shadowBlurRadius = 3

        // --- 第1行: 日期 (粗体) + 时间 (等宽) ---
        let dateFont = UIFont.boldSystemFont(ofSize: dateFontSize)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: textColor,
            .shadow: shadow
        ]
        let dateStr_size = dateStr.size(withAttributes: dateAttrs)

        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: timeFontSize, weight: .medium)
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: timeFont,
            .foregroundColor: dimTextColor,
            .shadow: shadow
        ]
        let timeStr_size = timeStr.size(withAttributes: timeAttrs)

        let line1Height = max(dateStr_size.height, timeStr_size.height)
        let spacing: CGFloat = margin * 0.2
        let dateX = margin
        let dateY_base = canvasSize.height - bottomMargin - line1Height - spacing * 2

        dateStr.draw(at: CGPoint(x: dateX, y: dateY_base), withAttributes: dateAttrs)

        let timeX = dateX + dateStr_size.width + margin * 0.3
        let timeY = dateY_base + dateStr_size.height - timeStr_size.height
        timeStr.draw(at: CGPoint(x: timeX, y: timeY), withAttributes: timeAttrs)

        // --- 第2行: 经纬度 (N/E 格式) ---
        var line2Y = dateY_base + line1Height + spacing

        if !coordinateStr.isEmpty {
            let coordFont = UIFont.monospacedDigitSystemFont(ofSize: coordFontSize, weight: .regular)
            let coordAttrs: [NSAttributedString.Key: Any] = [
                .font: coordFont,
                .foregroundColor: dimTextColor,
                .shadow: shadow
            ]
            coordinateStr.draw(at: CGPoint(x: dateX, y: line2Y), withAttributes: coordAttrs)
            let coordHeight = coordinateStr.size(withAttributes: coordAttrs).height
            line2Y += coordHeight + spacing * 0.5
        }

        // --- 第3行: 城市 · 天气 · 设备 ---
        var detailParts: [String] = []
        if !cityName.isEmpty {
            detailParts.append(cityName)
        }
        if !weatherStr.isEmpty {
            detailParts.append(weatherStr)
        }
        detailParts.append(deviceStr)
        let detailText = detailParts.joined(separator: "  ·  ")

        let detailFont = UIFont.systemFont(ofSize: detailFontSize, weight: .regular)
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: detailFont,
            .foregroundColor: dimTextColor.withAlphaComponent(0.75),
            .shadow: shadow
        ]
        detailText.draw(at: CGPoint(x: dateX, y: line2Y), withAttributes: detailAttrs)
    }

    // MARK: - 品牌水印（右下角）

    private func renderAppNameWatermark(context: CGContext, canvasSize: CGSize) {
        let fontSize: CGFloat = min(canvasSize.width * 0.12, 56)
        let font = UIFont.boldSystemFont(ofSize: fontSize)

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.4)
        shadow.shadowOffset = CGSize(width: 0.5, height: 0.5)
        shadow.shadowBlurRadius = 3

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            .shadow: shadow
        ]

        let textSize = appName.size(withAttributes: attributes)
        let margin: CGFloat = 22
        let x = canvasSize.width - textSize.width - margin
        let y = canvasSize.height - textSize.height - margin * 1.8

        appName.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
}
