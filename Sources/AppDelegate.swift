import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // ① 高德隐私合规：8.1.0 起，任何 SDK 接口调用前必须先声明，否则 SDK 静默罢工。
        //    这版 SDK 的隐私开关是 MAMapView 的类方法（设的是全局标志，导航同样生效）。
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)

        // ② 设置高德 Key（CI 编译时由 GitHub Secrets 注入到 Secrets.swift）
        AMapServices.shared().enableHTTPS = true
        AMapServices.shared().apiKey = Secrets.amapKey

        // ③ 程序化根视图（不用 storyboard / scene，减少出错面）
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = ViewController()
        w.makeKeyAndVisible()
        window = w

        // ④ 冷启动就带着 yinnav:// 链接进来（因在 TG 里点的直跳）——等首页就绪后开导
        if let url = launchOptions?[.url] as? URL {
            DispatchQueue.main.async { NavLauncher.handle(url: url) }
        }
        return true
    }

    // 运行中被 yinnav:// 链接唤起（App 已在后台）
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return NavLauncher.handle(url: url)
    }
}
