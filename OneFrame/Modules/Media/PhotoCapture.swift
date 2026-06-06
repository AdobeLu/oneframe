//
//  PhotoCapture.swift
//  OneFrame
//
//  拍照功能 - 渲染合成帧并保存为 JPEG
//

import UIKit

final class PhotoCapture {

    /// 保存照片到沙盒
    static func saveToSandbox(image: UIImage) -> URL? {
        let storage = MediaStorageManager.shared
        let fileName = generateFileName(ext: "jpg")
        let fileURL = storage.photosDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.92) else {
            return nil
        }

        do {
            try data.write(to: fileURL)
            // 同时生成缩略图
            let thumbURL = generateThumbnail(for: fileURL, image: image)
            // 记录元数据
            storage.addMediaEntry(
                type: .photo,
                originalURL: fileURL,
                thumbnailURL: thumbURL
            )
            return fileURL
        } catch {
            print("Failed to save photo: \(error)")
            return nil
        }
    }

    /// 生成缩略图
    static func generateThumbnail(for originalURL: URL, image: UIImage) -> URL {
        let thumbSize = CGSize(width: 360, height: 360)
        let thumbImage = image.thumbnail(size: thumbSize) ?? image
        let thumbData = thumbImage.jpegData(compressionQuality: 0.7)

        let thumbURL = originalURL
            .deletingPathExtension()
            .appendingPathExtension("thumb.jpg")

        try? thumbData?.write(to: thumbURL)
        return thumbURL
    }

    /// 生成文件名
    private static func generateFileName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: Date())).\(ext)"
    }
}
