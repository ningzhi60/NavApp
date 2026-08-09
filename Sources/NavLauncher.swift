import UIKit

/// 统一的"开始导航"入口。bot 直跳链接、剪贴板高德链接、页面上的按钮，都走这里。
enum NavLauncher {

    /// 当前最顶层的 VC（可能已经弹了别的页）。
    static func topViewController() -> UIViewController? {
        guard let root = (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// 直接用一个已解析好的 RouteRequest 开导。若当前已在导航页，先关掉再开新的。
    static func start(_ request: RouteRequest, simulate: Bool = false) {
        guard let top = topViewController() else { return }
        let present = {
            guard let host = topViewController() else { return }
            host.present(NaviViewController(request: request, simulate: simulate), animated: true)
        }
        if let nav = top as? NaviViewController {
            nav.dismiss(animated: false) { present() }
        } else {
            present()
        }
    }

    /// 处理外部 URL（yinnav:// 直跳）。解析不出就提示一下。
    @discardableResult
    static func handle(url: URL) -> Bool {
        guard let req = RouteParser.parse(url) else {
            toast("这条链接我没认出目的地~")
            return false
        }
        start(req)
        return true
    }

    /// 简易提示（无导航目的地时用）。
    static func toast(_ msg: String) {
        guard let top = topViewController() else { return }
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        top.present(a, animated: true)
    }
}
