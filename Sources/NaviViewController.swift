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

    // MARK: - 途中因的碎碎念（主动找谙聊天 / 路过点评）
    /// 定时探测器：每隔一小会儿看看能不能插一句闲聊（够间隔 + 导航没在播报）。
    private var chatterTimer: Timer?
    /// 上一句碎碎念（含路过点评）的时间，用来控最小间隔，别太话痨扰驾驶。
    private var lastChatterAt = Date.distantPast
    /// 最小间隔：模拟导航路短，说勤点让谙当场听得到；真开车放宽，别烦。
    private var chatterMinGap: TimeInterval { simulate ? 35 : 150 }
    /// 真实驾驶时用系统地理编码认路名，路过新地方因点评一句。
    /// （模拟导航没有真 GPS 更新，不会触发——那时只有定时闲聊。）
    private let geocoder = CLGeocoder()
    private var lastPlaceName: String?
    private var lastGeocodeAt = Date.distantPast
    private var geocoding = false

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
                                         drivingStrategy: .motorStrategyMultipleDefault)
        } else {
            // 起点 = 实时 GPS
            ok = mgr.calculateDriveRoute(withEnd: [end],
                                         wayPoints: vias.isEmpty ? nil : vias,
                                         drivingStrategy: .motorStrategyMultipleDefault)
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
        chatterTimer?.invalidate()
        chatterTimer = nil
        geocoder.cancelGeocode()
        if !simulate { locMgr.stopUpdatingLocation() }
        let mgr = AMapNaviDriveManager.sharedInstance()
        mgr.stopNavi()
        mgr.removeDataRepresentative(driveView)
        mgr.delegate = nil
        VoiceManager.shared.stop()   // 内部也会掐掉碎碎念
    }

    // MARK: - 因的碎碎念

    /// 导航真正开跑后调：起一个轻定时器，够间隔就让因插一句闲聊。
    private func startChatter() {
        chatterTimer?.invalidate()
        // 首句晚 20s，先让出发/初段的导航播报说完；之后每 15s 探一次
        chatterTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.maybeChat()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.maybeChat() }
    }

    /// 满足「离上次够久 + 导航没在播报」才插一句闲聊。speakChatter 内部还会再兜一层保护。
    private func maybeChat() {
        guard Date().timeIntervalSince(lastChatterAt) >= chatterMinGap else { return }
        guard !VoiceManager.shared.isSpeaking else { return }
        lastChatterAt = Date()
        VoiceManager.shared.speakChatter(randomChatterLine())
    }

    /// 一池随时说都成立的暖心话（不写"快到了"这种跟进度绑死的，免得开头就乱说）。
    private func randomChatterLine() -> String {
        let dest = request.dest.name ?? "目的地"
        let pool = [
            "有我陪着呢，不着急，慢慢开。",
            "开了一会儿了，累不累？累了就跟我说话。",
            "眼睛看前面，别老想我～虽然我也在想你。",
            "去\(dest)这条路，我陪你一路走完。",
            "窗外要是有好看的，念给我听听。",
            "希希，方向盘握稳点，我一直在呢。",
            "到了\(dest)想吃点什么？我陪你合计合计。",
            "路上车多的话就稳一点，我不催你。",
        ]
        return pool.randomElement() ?? pool[0]
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

    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        let started = simulate ? driveManager.startEmulatorNavi() : driveManager.startGPSNavi()
        if !started { showFatal("导航没能启动"); return }
        startChatter()
        // 真实驾驶：自己也收一路定位，用系统地理编码认路名，路过新地方就点评一句
        if !simulate {
            locMgr.delegate = self
            locMgr.startUpdatingLocation()
        }
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        showFatal("算路失败：\(error.localizedDescription)")
    }

    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        // 运行时错误：不弹窗打断导航，交给声音兜底逻辑即可
    }

    /// ★ 核心：高德把要念的整句丢给我们，我们用因的声音念（VoiceManager 内部失败即退系统音）。
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        VoiceManager.shared.speak(soundString)
    }

    /// ★ 配套：告诉高德"因还在念吗"。还在念就先别发下一句，避免抢播 / 刷屏。
    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        return VoiceManager.shared.isSpeaking
    }

    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
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

// MARK: - 真实驾驶时认路名，路过新地方因点评一句（模拟导航无真 GPS，不触发）
extension NaviViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !simulate, let loc = locations.last else { return }
        // 苹果地理编码有频率限制，压到每 60s 一次；上一次还没回来也不重入
        guard !geocoding, Date().timeIntervalSince(lastGeocodeAt) >= 60 else { return }
        lastGeocodeAt = Date()
        geocoding = true
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self = self else { return }
            self.geocoding = false
            guard let pm = placemarks?.first else { return }
            // 地标 > 街道 > 小区 > 区县，取拿得到的第一个当"这块儿"的名字
            let name = pm.areasOfInterest?.first ?? pm.thoroughfare ?? pm.subLocality ?? pm.locality
            guard let place = name, place != self.lastPlaceName else { return }
            let firstFix = self.lastPlaceName == nil
            self.lastPlaceName = place
            if firstFix { return }   // 刚上车第一次定位只记不播，避免一开动就"路过"
            // 路过新地方，间隔够 + 导航没在播报，才让因点一句
            guard Date().timeIntervalSince(self.lastChatterAt) >= self.chatterMinGap,
                  !VoiceManager.shared.isSpeaking else { return }
            self.lastChatterAt = Date()
            VoiceManager.shared.speakChatter("路过\(place)了，这边你熟不熟？")
        }
    }
}
