//
//  DeviceInfoService.swift
//  OneFrame
//
//  获取设备信息用于水印显示
//

import UIKit

final class DeviceInfoService {

    static let shared = DeviceInfoService()

    /// 设备型号名称（如 iPhone 15 Pro）
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapToDeviceName(identifier: identifier)
    }

    /// 系统版本
    var systemVersion: String {
        UIDevice.current.systemVersion
    }

    /// 系统名称
    var systemName: String {
        UIDevice.current.systemName
    }

    /// 完整系统信息字符串
    var fullSystemInfo: String {
        "\(systemName) \(systemVersion)"
    }

    // MARK: - Private

    private func mapToDeviceName(identifier: String) -> String {
        let deviceMap: [String: String] = [
            // iPhone 15 series
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            // iPhone 14 series
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            // iPhone 13 series
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            // iPhone 12 series
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            // iPhone 11 series
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            // iPhone X series
            "iPhone10,3": "iPhone X",
            "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            // iPhone SE
            "iPhone12,8": "iPhone SE (2nd gen)",
            "iPhone14,6": "iPhone SE (3rd gen)",
            // Simulator
            "x86_64": "Simulator",
            "arm64": "Simulator"
        ]
        return deviceMap[identifier] ?? identifier
    }
}
