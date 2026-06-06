//
//  AlbumExporter.swift
//  OneFrame
//
//  相册导出与系统分享
//

import UIKit
import Photos

final class AlbumExporter {

    /// 保存图片到系统相册
    static func savePhotoToAlbum(image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized, .notDetermined:
                break
            default:
                DispatchQueue.main.async { completion(false, nil) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }

    /// 保存视频到系统相册
    static func saveVideoToAlbum(url: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized, .notDetermined:
                break
            default:
                DispatchQueue.main.async { completion(false, nil) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }

    /// 系统分享面板
    static func share(mediaURL: URL, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [mediaURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = viewController.view
        viewController.present(activityVC, animated: true)
    }

    /// 分享图片
    static func share(image: UIImage, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = viewController.view
        viewController.present(activityVC, animated: true)
    }
}
