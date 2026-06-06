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
        // 仅在用户已在相机页时恢复 session，避免与 CameraViewController.viewDidAppear 重复启动
        if appCoordinator?.tabBarController.selectedIndex == 0 {
            appCoordinator?.captureSessionManager.startSession()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {
        appCoordinator?.captureSessionManager.stopSession()
    }
}
