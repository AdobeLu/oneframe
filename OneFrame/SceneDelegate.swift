//
//  SceneDelegate.swift
//  OneFrame
//
//  Created by luligang on 2026/6/2.
//

import UIKit

@available(iOS 15.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let coordinator = AppCoordinator()
        self.appCoordinator = coordinator

        window = UIWindow(windowScene: windowScene)
        window?.overrideUserInterfaceStyle = .dark
        window?.rootViewController = coordinator.tabBarController
        window?.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 清除通知栏下拉导致的中断遮罩
        appCoordinator?.handleSceneDidBecomeActive()

        // 仅在用户已在相机页且 session 之前是正常运行时恢复
        // 如果是在中断期间（如微信视频占用摄像头），不要盲目重启
        let manager = appCoordinator?.captureSessionManager
        if appCoordinator?.tabBarController.selectedIndex == 0,
           manager?.isSessionRunning == false {
            manager?.startSession()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 通知栏下拉时，如果正在录像则自动停止保存
        appCoordinator?.stopRecordingIfNeeded()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 进入后台时，如果正在录像则自动停止保存
        appCoordinator?.stopRecordingIfNeeded()
        appCoordinator?.captureSessionManager.stopSession()
    }
}
