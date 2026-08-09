import UIKit
import CoreLocation
import CryptoKit

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

    // MARK: - 途中因的碎碎念（实时·因自己现写的话）
    // 思路：不预存台词。到点了就把「此刻情况」（在哪儿、开了多久、去哪）发给 bot，
    // 让因用自己的脑子现写一句发回来——只有真要说那一下才调一次，花费很小。
    // 什么时候说：泊松过程（间隔服从指数分布），平均 ~半小时一句，时早时晚不机械。

    /// 下一次开口的计划任务（可取消/重排）。
    private var sayWork: DispatchWorkItem?
    /// 导航开跑时刻，用来算「已经开了多久」。
    private var navStartAt = Date()
    /// 说话间隔的平均值（秒）：真开车约半小时；模拟导航路短，压到 ~45s 好当场听到。
    private var sayMeanGap: TimeInterval { simulate ? 45 : 1600 }
    private var sayFloorGap: TimeInterval { simulate ? 20 : 180 }   // 至少隔这么久，别话痨
    private var sayCapGap: TimeInterval { simulate ? 90 : 3000 }    // 最多憋这么久，别冷场
    /// 一次说话在跑（取话+播），避免重入。
    private var saying = false
    /// 真实驾驶时的最近定位，用来反查「现在路过哪儿」。模拟导航没有真 GPS，这里一直是 nil。
    private var lastLocation: CLLocation?
    private let geocoder = CLGeocoder()

    /// bot 的实时取话接口（走 calendar 无鉴权 vhost 专用路由，HMAC 自护）。
    private let sayEndpoint = "https://calendar.45.32.43.224.sslip.io/nav/api/say"

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
        sayWork?.cancel()
        sayWork = nil
        geocoder.cancelGeocode()
        if !simulate { locMgr.stopUpdatingLocation() }
        let mgr = AMapNaviDriveManager.sharedInstance()
        mgr.stopNavi()
        mgr.removeDataRepresentative(driveView)
        mgr.delegate = nil
        VoiceManager.shared.stop()   // 内部也会掐掉碎碎念
    }

    // MARK: - 因的实时碎碎念（泊松调度 + 到点现取一句）

    /// 导航开跑后调：记下起点时刻，排下一次开口。
    private func startYinSay() {
        navStartAt = Date()
        scheduleNextSay(first: true)
    }

    /// 抽一个指数分布间隔，排下一次「因开口」。first=true 时头一句来得早点（暖场 + 好验证）。
    private func scheduleNextSay(first: Bool) {
        sayWork?.cancel()
        let gap: TimeInterval
        if first {
            // 首句用更短的均值，让因早点吭一声；仍是随机
            gap = drawGap(mean: simulate ? 25 : 200, floor: simulate ? 15 : 90, cap: simulate ? 60 : 480)
        } else {
            gap = drawGap(mean: sayMeanGap, floor: sayFloorGap, cap: sayCapGap)
        }
        let w = DispatchWorkItem { [weak self] in self?.fireSay() }
        sayWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: w)
    }

    /// 指数分布（泊松过程的到达间隔）：-mean·ln(U)，再夹进 [floor, cap]。
    private func drawGap(mean: TimeInterval, floor: TimeInterval, cap: TimeInterval) -> TimeInterval {
        let u = max(Double.random(in: 0...1), 1e-9)
        let g = -mean * log(u)
        return min(max(g, floor), cap)
    }

    /// 到点了：导航没在播报就现取一句因的话来说；不管成不成，都排下一次。
    private func fireSay() {
        defer { scheduleNextSay(first: false) }
        guard !saying, !VoiceManager.shared.isSpeaking else { return }  // 让路给转向播报
        saying = true
        let dest = request.dest.name ?? "目的地"
        let elapsedMin = max(1, Int(Date().timeIntervalSince(navStartAt) / 60))
        // 真实驾驶：先反查此刻在哪儿，再连名字一起问因；模拟导航没真 GPS，place 留空
        resolvePlace { [weak self] place in
            guard let self = self else { return }
            self.fetchYinLine(place: place, elapsedMin: elapsedMin, dest: dest) { line in
                DispatchQueue.main.async {
                    self.saying = false
                    guard let line = line, !line.isEmpty else { return }   // 取不到就静默，不硬编
                    VoiceManager.shared.speakChatter(line)                 // 仍让路给保命播报、失败静默
                }
            }
        }
    }

    /// 反查「现在路过哪儿」。真实驾驶用最近定位做反向地理编码；模拟或失败 → nil。
    private func resolvePlace(_ done: @escaping (String?) -> Void) {
        guard !simulate, let loc = lastLocation else { done(nil); return }
        geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
            let pm = placemarks?.first
            let name = pm?.areasOfInterest?.first ?? pm?.thoroughfare ?? pm?.subLocality ?? pm?.locality
            done(name)
        }
    }

    /// 把此刻情况发给 bot，让因现写一句话。HMAC(用 MiniMax key) + 时间戳自护，服务端限流。
    private func fetchYinLine(place: String?, elapsedMin: Int, dest: String,
                              completion: @escaping (String?) -> Void) {
        let ts = String(Int(Date().timeIntervalSince1970))
        let key = SymmetricKey(data: Data(Secrets.minimaxApiKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ts.utf8), using: key)
        let sig = mac.map { String(format: "%02x", $0) }.joined()

        var cs = URLComponents(string: sayEndpoint)!
        var items = [URLQueryItem(name: "ts", value: ts),
                     URLQueryItem(name: "sig", value: sig),
                     URLQueryItem(name: "dest", value: dest),
                     URLQueryItem(name: "elapsed", value: String(elapsedMin))]
        if let p = place, !p.isEmpty { items.append(URLQueryItem(name: "place", value: p)) }
        cs.queryItems = items
        guard let url = cs.url else { completion(nil); return }

        var req = URLRequest(url: url, timeoutInterval: 8)
        URLSession.shared.dataTask(with: req) { data, _, err in
            guard err == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let line = json["line"] as? String else { completion(nil); return }
            completion(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
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
        startYinSay()
        // 真实驾驶：自己也收一路定位，留最近一个点，供开口时反查「现在路过哪儿」
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

// MARK: - 真实驾驶时留最近定位（供因开口时反查「现在路过哪儿」；模拟导航无真 GPS，不触发）
extension NaviViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !simulate, let loc = locations.last else { return }
        lastLocation = loc   // 不在这反查地名——地理编码挪到真要说那一下再做，省频率也更实时
    }
}
