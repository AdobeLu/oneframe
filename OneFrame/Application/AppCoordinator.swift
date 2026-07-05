//
//  AppCoordinator.swift
//  OneFrame
//
//  App 主协调器 - 管理 TabBar 页面初始化
//

import UIKit

@available(iOS 15.0, *)
final class AppCoordinator {

    let tabBarController: UITabBarController
    let captureSessionManager: CaptureSessionManager

    private let cameraVC: CameraViewController
    private let galleryVC: UINavigationController
    private let settingsVC: UINavigationController

    init() {
        captureSessionManager = CaptureSessionManager()

        // 相机页
        cameraVC = CameraViewController(captureSessionManager: captureSessionManager)
        cameraVC.tabBarItem = UITabBarItem(
            title: OWLocalized("camera.photo"),
            image: UIImage(systemName: "camera.fill"),
            tag: 0
        )

        // 相册页
        let mediaVC = MediaPreviewViewController()
        galleryVC = UINavigationController(rootViewController: mediaVC)
        galleryVC.tabBarItem = UITabBarItem(
            title: OWLocalized("gallery.title"),
            image: UIImage(systemName: "photo.on.rectangle"),
            tag: 1
        )

        // 设置页
        let settingsRoot = SettingsViewController()
        settingsVC = UINavigationController(rootViewController: settingsRoot)
        settingsVC.tabBarItem = UITabBarItem(
            title: OWLocalized("setting.title"),
            image: UIImage(systemName: "gearshape.fill"),
            tag: 2
        )

        tabBarController = UITabBarController()

        // TabBar 外观：纯黑，与 camera 操作栏统一
        let appearance = UITabBarAppearance()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .black
        appearance.shadowColor = .clear
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
        tabBarController.tabBar.standardAppearance = appearance
        tabBarController.tabBar.scrollEdgeAppearance = appearance
        tabBarController.tabBar.clipsToBounds = true
        tabBarController.tabBar.tintColor = .white
        tabBarController.viewControllers = [cameraVC, galleryVC, settingsVC]
        tabBarController.selectedIndex = 0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshTabBarTitles),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func refreshTabBarTitles() {
        cameraVC.tabBarItem.title = OWLocalized("camera.photo")
        galleryVC.tabBarItem.title = OWLocalized("gallery.title")
        settingsVC.tabBarItem.title = OWLocalized("setting.title")
    }

    /// 进入后台/通知栏下拉时，如正在录像则自动停止
    func stopRecordingIfNeeded() {
        cameraVC.stopRecordingIfNeeded()
    }

    /// 场景恢复活跃时，清除中断遮罩
    func handleSceneDidBecomeActive() {
        cameraVC.handleSceneDidBecomeActive()
    }
}
