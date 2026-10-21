//
//  SceneDelegate.swift
//  demo
//
//  Created by resoul on 21.10.2026.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let progressBars = LavaProgressViewController()
        progressBars.tabBarItem = UITabBarItem(
            title: "Progress Bars",
            image: UIImage(systemName: "line.horizontal.3.decrease.circle"),
            tag: 0
        )
        let metalLab = MetalLabViewController()
        metalLab.tabBarItem = UITabBarItem(title: "Metal Lab", image: UIImage(systemName: "cpu"), tag: 1)

        let emojiParticles = EmojiParticlesViewController()
        emojiParticles.tabBarItem = UITabBarItem(title: "Emoji", image: UIImage(systemName: "face.smiling"), tag: 2)

        let gpuCompute = GPUComputeViewController()
        gpuCompute.tabBarItem = UITabBarItem(title: "GPU Compute", image: UIImage(systemName: "function"), tag: 3)

        let gpuWorlds = GPUWorldsViewController()
        gpuWorlds.tabBarItem = UITabBarItem(title: "GPU Worlds", image: UIImage(systemName: "globe"), tag: 4)

        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [progressBars, metalLab, emojiParticles, gpuCompute, gpuWorlds]
        // Launch argument `-tab N` opens that tab directly.
        tabBarController.selectedIndex = min(UserDefaults.standard.integer(forKey: "tab"), tabBarController.viewControllers!.count - 1)
        tabBarController.overrideUserInterfaceStyle = .dark

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

