import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        let progress = LavaProgressViewController()
        progress.tabBarItem = UITabBarItem(title: "Progress Bars", image: UIImage(systemName: "line.horizontal.3.decrease.circle"), tag: 0)
        let lab = MetalLabViewController()
        lab.tabBarItem = UITabBarItem(title: "Metal Lab", image: UIImage(systemName: "cpu"), tag: 1)
        let emoji = EmojiParticlesViewController()
        emoji.tabBarItem = UITabBarItem(title: "Emoji", image: UIImage(systemName: "face.smiling"), tag: 2)
        let showcase = GPUShowcaseViewController()
        showcase.tabBarItem = UITabBarItem(title: "Showcase", image: UIImage(systemName: "cube.transparent"), tag: 3)
        let compute = ComputeBenchmarkViewController()
        compute.tabBarItem = UITabBarItem(title: "Compute", image: UIImage(systemName: "function"), tag: 4)
        viewControllers = [progress, lab, emoji, showcase, compute]
        tabBar.tintColor = UIColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        if ProcessInfo.processInfo.arguments.contains("--metal-lab") { selectedIndex = 1 }
        if ProcessInfo.processInfo.arguments.contains("--emoji-particles") { selectedIndex = 2 }
        if ProcessInfo.processInfo.arguments.contains("--gpu-showcase") { selectedIndex = 3 }
        if ProcessInfo.processInfo.arguments.contains("--compute-bench") { selectedIndex = 4 }
    }
}
