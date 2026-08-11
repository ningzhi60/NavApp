import Foundation

/// 一个导航点（GCJ-02，高德同坐标系）。bot 的 nav.py 与高德分享链接都用这个坐标系，拿来即用。
struct NavPoint {
    let lat: Double
    let lng: Double
    let name: String?
}

/// 一次导航请求：可选显式起点 + 目的地 + 途经点。没有起点时仍从手机当前位置出发。
/// 两条入口——① 因在 TG 发的 yinnav:// 直跳链接；② 谙从高德复制的链接——最后都归一成它。
struct RouteRequest {
    let start: NavPoint?
    let dest: NavPoint
    let waypoints: [NavPoint]
    var title: String { dest.name ?? "目的地" }
}

/// 把各种来源的链接/文本解析成 RouteRequest。
/// 能认：yinnav://（我们自己的）、amapuri:///iosamap:///androidamap://（高德 deeplink）、
///        http(s) 的 uri.amap.com（带 to=/position= 坐标的）、以及高德短链（先跟随跳转再扫坐标）。
enum RouteParser {

    // MARK: - 对外

    /// 同步解析：能直接从 URL 本身拿到坐标时用（yinnav、amap deeplink、带坐标的 uri.amap.com）。
    static func parse(_ url: URL) -> RouteRequest? {
        let scheme = (url.scheme ?? "").lowercased()
        switch scheme {
        case "yinnav":
            return parseYinnav(url)
        case "amapuri", "iosamap", "androidamap":
            return parseAmapDeeplink(url)
        case "http", "https":
            return parseAmapWeb(url)
        default:
            return nil
        }
    }

    /// 从一段分享文本里揪出第一个可用链接。
    static func firstURL(in text: String) -> URL? {
        let pattern = "(?:https?|yinnav|amapuri|iosamap|androidamap)://[^\\s\"'<>）)】]+"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: range),
              let r = Range(m.range, in: text) else { return nil }
        return URL(string: String(text[r]))
    }

    /// 异步解析剪贴板文本：先试同步；不行就当短链跟随跳转，再扫最终 URL + 页面正文里的坐标。
    /// 全程最多 ~8s；解析不出就回 nil（调用方负责给谙一句"没认出来"的提示）。
    static func resolve(fromClipboard text: String, completion: @escaping (RouteRequest?) -> Void) {
        guard let url = firstURL(in: text) else { completion(nil); return }
        if let r = parse(url) { completion(r); return }

        // 短链 / 不带坐标的高德网页：GET 跟随跳转，扫最终 URL 和正文
        guard (url.scheme == "http" || url.scheme == "https") else { completion(nil); return }
        var req = URLRequest(url: url, timeoutInterval: 8.0)
        req.setValue("Mozilla/5.0 (iPhone)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var result: RouteRequest?
            if let finalURL = resp?.url, let r = parse(finalURL) {
                result = r
            } else {
                var scan = resp?.url?.absoluteString ?? ""
                if let data = data, let body = String(data: data, encoding: .utf8) { scan += "\n" + body }
                result = scanCoordinates(in: scan)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // MARK: - 各来源解析

    private static func parseYinnav(_ url: URL) -> RouteRequest? {
        guard let q = queryItems(url) else { return nil }
        // 优先我们自己的字段；也兼容高德风格的 to=lng,lat,name
        var dest: NavPoint?
        if let dlatS = q["dlat"], let dlngS = q["dlng"] ?? q["dlon"],
           let dlat = Double(dlatS), let dlng = Double(dlngS) {
            dest = NavPoint(lat: dlat, lng: dlng, name: q["dname"]?.removingPercentEncoding)
        } else if let to = q["to"] {
            dest = pointFromCSV(to)
        }
        guard let d = dest else { return nil }

        var vias: [NavPoint] = []
        if let via = q["via"] {
            // 途经点用 | 或 ; 分隔，每段 lat,lng[,name] 或 lng,lat[,name]（顺序自动判别）
            for seg in via.components(separatedBy: CharacterSet(charactersIn: "|;")) {
                if let p = pointFromCSV(seg) { vias.append(p) }
            }
        }
        let start = explicitStart(from: q)
        return RouteRequest(start: start, dest: d, waypoints: vias)
    }

    private static func parseAmapDeeplink(_ url: URL) -> RouteRequest? {
        guard let q = queryItems(url) else { return nil }
        // 高德 route/plan：dlat/dlon/dname
        if let dlatS = q["dlat"], let dlonS = q["dlon"] ?? q["dlng"],
           let dlat = Double(dlatS), let dlon = Double(dlonS) {
            return RouteRequest(start: explicitStart(from: q),
                                dest: NavPoint(lat: dlat, lng: dlon, name: q["dname"]?.removingPercentEncoding),
                                waypoints: [])
        }
        return nil
    }

    private static func parseAmapWeb(_ url: URL) -> RouteRequest? {
        guard let host = url.host?.lowercased(), host.contains("amap.com"),
              let q = queryItems(url) else { return nil }
        // uri.amap.com/navigation?to=lng,lat,name
        if let to = q["to"], let d = pointFromCSV(to) {
            var vias: [NavPoint] = []
            if let via = q["via"] {
                for seg in via.components(separatedBy: CharacterSet(charactersIn: "|;")) {
                    if let p = pointFromCSV(seg) { vias.append(p) }
                }
            }
            return RouteRequest(start: q["from"].flatMap(pointFromCSV), dest: d, waypoints: vias)
        }
        // uri.amap.com/marker?position=lng,lat&name=xxx
        if let pos = q["position"], let d0 = pointFromCSV(pos) {
            let named = NavPoint(lat: d0.lat, lng: d0.lng, name: q["name"]?.removingPercentEncoding ?? d0.name)
            return RouteRequest(start: nil, dest: named, waypoints: [])
        }
        // 兜底：分离的 lat/lng 参数
        if let latS = q["lat"] ?? q["mlat"], let lngS = q["lng"] ?? q["lon"] ?? q["mlon"],
           let lat = Double(latS), let lng = Double(lngS), let d = point(lat, lng, name: q["name"]) {
            return RouteRequest(start: nil, dest: d, waypoints: [])
        }
        return nil
    }

    // MARK: - 正文扫坐标（短链兜底）

    private static func scanCoordinates(in s: String) -> RouteRequest? {
        let patterns = [
            "position=([\\d.]+),([\\d.]+)",
            "[?&]to=([\\d.]+),([\\d.]+)",
            "\"lng\"\\s*:\\s*([\\d.]+)\\s*,\\s*\"lat\"\\s*:\\s*([\\d.]+)",
            "\"lat\"\\s*:\\s*([\\d.]+)\\s*,\\s*\"lng\"\\s*:\\s*([\\d.]+)",
            "([1]\\d{2}\\.\\d{4,}),([1-5]?\\d\\.\\d{4,})",   // 116.397,39.909
            "([1-5]?\\d\\.\\d{4,}),([1]\\d{2}\\.\\d{4,})",   // 39.909,116.397
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            guard let m = re.firstMatch(in: s, options: [], range: range),
                  m.numberOfRanges >= 3,
                  let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s),
                  let a = Double(s[r1]), let b = Double(s[r2]),
                  let d = point(a, b, name: nil) else { continue }
            return RouteRequest(start: nil, dest: d, waypoints: [])
        }
        return nil
    }

    // MARK: - 小工具

    private static func queryItems(_ url: URL) -> [String: String]? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return nil }
        var dict: [String: String] = [:]
        for it in items where it.value != nil { dict[it.name.lowercased()] = it.value }
        return dict
    }

    private static func explicitStart(from q: [String: String]) -> NavPoint? {
        if let slatS = q["slat"], let slngS = q["slng"] ?? q["slon"],
           let slat = Double(slatS), let slng = Double(slngS) {
            return NavPoint(lat: slat, lng: slng, name: q["sname"]?.removingPercentEncoding)
        }
        return q["from"].flatMap(pointFromCSV)
    }

    /// "lng,lat,名字" 或 "lat,lng,名字" → NavPoint（经纬度顺序自动判别）。
    private static func pointFromCSV(_ csv: String) -> NavPoint? {
        let parts = csv.components(separatedBy: ",")
        guard parts.count >= 2, let a = Double(parts[0]), let b = Double(parts[1]) else { return nil }
        let name = parts.count >= 3 ? parts[2...].joined(separator: ",").removingPercentEncoding : nil
        return point(a, b, name: name)
    }

    /// 给两个数，靠中国经纬度范围判断谁是纬度谁是经度（lat 3~54，lng 73~136，两区间不重叠，判别唯一）。
    private static func point(_ a: Double, _ b: Double, name: String?) -> NavPoint? {
        func isLat(_ v: Double) -> Bool { v >= 3 && v <= 54 }
        func isLng(_ v: Double) -> Bool { v >= 73 && v <= 136 }
        if isLat(a) && isLng(b) { return NavPoint(lat: a, lng: b, name: name) }
        if isLng(a) && isLat(b) { return NavPoint(lat: b, lng: a, name: name) }
        return nil
    }
}
