import UIKit
import CoreLocation

/// 真·驾车导航页。高德 SDK 负责算路 + 界面 + 转向判断；
/// 但每一句播报都交给因的声音（playNaviSoundString 回调 → VoiceManager），合成失败自动退系统音。
/// 两条入口（bot 直跳 / 高德剪贴板）都进这一个页面。
final class NaviViewController: UIViewController {

    private let request: RouteRequest
    /// true = 室内模拟导航（固定起点，用 startEmulatorNavi，不用真 GPS，方便没车/没信号时测因的声音）。
    private let simulate: Bool

    private var driveView: AMapNaviDriveView!
    private let locMgr = CLLocationManager()
    /// 高频短语——导航前预合成进缓存，第一句就秒开、不卡网络空档。
    private let warmupPhrases = [
        "前方路口请左转", "前方路口请右转", "请直行", "请掉头",
        "前方进入主路", "前方驶出主路", "请靠左行驶", "请靠右行驶",
        "前方有测速摄像头", "已到达目的地附近，导航结束",
    ]

    init(request: RouteRequest, simulate: Bool) {
        self.request = request
        self.simulate = simulate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 导航 UI
        driveView = AMapNaviDriveView(frame: view.bounds, viewConfig: nil)
        driveView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        driveView.delegate = self
        view.addSubview(driveView)
        addExitButton()

        // 真 GPS 导航需要定位权限；模拟导航不需要
        if !simulate {
            locMgr.requestWhenInUseAuthorization()
        }

        // 先把高频播报灌进缓存，再算路
        VoiceManager.shared.prewarm(warmupPhrases)

        let mgr = AMapNaviDriveManager.sharedInstance()
        mgr.delegate = self
        mgr.addDataRepresentative(driveView)
        calculateRoute(mgr)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        teardown()
    }

    // MARK: - 算路

    private func calculateRoute(_ mgr: AMapNaviDriveManager) {
        let end = AMapNaviPoint.location(withLatitude: CGFloat(request.dest.lat),
                                         longitude: CGFloat(request.dest.lng))!
        let vias: [AMapNaviPoint] = request.waypoints.compactMap {
            AMapNaviPoint.location(withLatitude: CGFloat($0.lat), longitude: CGFloat($0.lng))
        }
        let ok: Bool
        if simulate {
            // 固定起点（北京中关村附近），室内也能算出一条路来试因的声音
            let start = AMapNaviPoint.location(withLatitude: 39.9890, longitude: 116.3130)!
            ok = mgr.calculateDriveRoute(withStart: [start], end: [end],
                                         wayPoints: vias.isEmpty ? nil : vias,
                                         drivingStrategy: .MotorStrategyMultipleDefault)
        } else {
            // 起点 = 实时 GPS
            ok = mgr.calculateDriveRoute(withEnd: [end],
                                         wayPoints: vias.isEmpty ? nil : vias,
                                         drivingStrategy: .MotorStrategyMultipleDefault)
        }
        if !ok { showFatal("路线没能开始规划") }
    }

    // MARK: - 退出

    private func addExitButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("✕ 退出", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        btn.layer.cornerRadius = 16
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            btn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
        ])
    }

    @objc private func exitTapped() {
        dismiss(animated: true)
    }

    private func teardown() {
        let mgr = AMapNaviDriveManager.sharedInstance()
        mgr.stopNavi()
        mgr.removeDataRepresentative(driveView)
        mgr.delegate = nil
        VoiceManager.shared.stop()
    }

    private func showFatal(_ msg: String) {
        // 导航是保命功能：算路失败也别让谙卡在黑屏——出声提示 + 给退回官方高德的出口
        VoiceManager.shared.speak("路线没算出来，你用手机自带地图吧")
        let a = UIAlertController(title: "没能开始导航", message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "用官方高德打开", style: .default) { [weak self] _ in
            self?.openInAmap(); self?.dismiss(animated: true)
        })
        a.addAction(UIAlertAction(title: "关闭", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(a, animated: true)
    }

    /// 兜底：拉起官方高德 App 导到同一目的地（我们这条路走不了时的保命出口）。
    private func openInAmap() {
        let name = (request.dest.name ?? "目的地").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "目的地"
        let s = "iosamap://path?sourceApplication=yinnav&dlat=\(request.dest.lat)&dlon=\(request.dest.lng)&dname=\(name)&t=0"
        if let u = URL(string: s), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
        } else {
            let web = "https://uri.amap.com/navigation?to=\(request.dest.lng),\(request.dest.lat),\(name)&mode=car&coordinate=gaode&callnative=1"
            if let u = URL(string: web) { UIApplication.shared.open(u) }
        }
    }
}

// MARK: - 导航事件：把每一句播报接管给因的声音
extension NaviViewController: AMapNaviDriveManagerDelegate {

    func driveManagerOnCalculateRouteSuccess(_ driveManager: AMapNaviDriveManager) {
        let started = simulate ? driveManager.startEmulatorNavi() : driveManager.startGPSNavi()
        if !started { showFatal("导航没能启动") }
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        showFatal("算路失败：\(error.localizedDescription)")
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        // 运行时错误：不弹窗打断导航，交给声音兜底逻辑即可
    }

    /// ★ 核心：高德把要念的整句丢给我们，我们用因的声音念（VoiceManager 内部失败即退系统音）。
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSoundString soundString: String, soundStringType: AMapNaviSoundType) {
        VoiceManager.shared.speak(soundString)
    }

    /// ★ 配套：告诉高德"因还在念吗"。还在念就先别发下一句，避免抢播 / 刷屏。
    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        return VoiceManager.shared.isSpeaking
    }

    func driveManagerOnArrivedDestination(_ driveManager: AMapNaviDriveManager) {
        VoiceManager.shared.speak("到啦，我们到目的地了")
    }

    func driveManagerDidEndEmulatorNavi(_ driveManager: AMapNaviDriveManager) {
        // 模拟导航跑完，自动收尾
        dismiss(animated: true)
    }
}

// MARK: - 导航界面上的按钮（关闭等）
extension NaviViewController: AMapNaviDriveViewDelegate {
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        dismiss(animated: true)
    }
}
