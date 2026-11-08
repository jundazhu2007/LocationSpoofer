import Foundation

struct Airport: Identifiable, Hashable, Sendable {
    let iata: String
    let name: String
    let city: String
    let country: String
    let coordinate: Coordinate
    var id: String { iata }
    var title: String { "\(iata) · \(city)" }
}

/// 機場與直飛航線資料庫(資料來源:OpenFlights,ODbL)。
struct AirportDB: Sendable {
    let airports: [Airport]
    private let byIATA: [String: Airport]
    private let routes: [String: Set<String>]

    init(airportsTSV: String, routesTXT: String) {
        var list: [Airport] = []
        for line in airportsTSV.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, let la = Double(f[4]), let lo = Double(f[5]) else { continue }
            list.append(Airport(iata: f[0], name: f[1], city: f[2], country: f[3], coordinate: .init(latitude: la, longitude: lo)))
        }
        var r: [String: Set<String>] = [:]
        for line in routesTXT.split(separator: "\n") {
            let p = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard p.count == 2 else { continue }
            r[p[0], default: []].formUnion(p[1].split(separator: ",").map(String.init))
        }
        airports = list
        byIATA = Dictionary(uniqueKeysWithValues: list.map { ($0.iata, $0) })
        routes = r
    }

    static func load() -> AirportDB {
        func read(_ name: String, _ ext: String) -> String {
            Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
        return AirportDB(airportsTSV: read("airports", "tsv"), routesTXT: read("routes", "txt"))
    }

    func airport(_ iata: String) -> Airport? { byIATA[iata] }
    func hasDirect(_ a: String, _ b: String) -> Bool { routes[a]?.contains(b) == true || routes[b]?.contains(a) == true }
    func destinations(from a: String) -> Set<String> {
        var s = routes[a] ?? []
        for (k, v) in routes where v.contains(a) { s.insert(k) }
        return s
    }

    // l10n:ignore-begin  (中文搜尋別名,不是介面文字)
    private static let aliases: [String: [String]] = [
        "台北": ["TPE", "TSA"], "桃園": ["TPE"], "松山": ["TSA"], "高雄": ["KHH"], "台中": ["RMQ"], "台南": ["TNN"], "花蓮": ["HUN"],
        "金門": ["KNH"], "澎湖": ["MZG"], "馬祖": ["MFK"], "台東": ["TTT"],
        "東京": ["NRT", "HND"], "羽田": ["HND"], "成田": ["NRT"], "大阪": ["KIX", "ITM"], "關西": ["KIX"], "名古屋": ["NGO"],
        "福岡": ["FUK"], "札幌": ["CTS"], "沖繩": ["OKA"], "那霸": ["OKA"], "廣島": ["HIJ"], "仙台": ["SDJ"],
        "首爾": ["ICN", "GMP"], "仁川": ["ICN"], "釜山": ["PUS"], "濟州": ["CJU"],
        "香港": ["HKG"], "澳門": ["MFM"], "上海": ["PVG", "SHA"], "北京": ["PEK", "PKX"], "廣州": ["CAN"], "深圳": ["SZX"],
        "成都": ["TFU", "CTU"], "重慶": ["CKG"], "杭州": ["HGH"], "廈門": ["XMN"], "西安": ["XIY"],
        "新加坡": ["SIN"], "曼谷": ["BKK", "DMK"], "吉隆坡": ["KUL"], "雅加達": ["CGK"], "峇里島": ["DPS"], "馬尼拉": ["MNL"],
        "胡志明": ["SGN"], "河內": ["HAN"], "金邊": ["PNH"], "清邁": ["CNX"], "普吉": ["HKT"], "宿霧": ["CEB"],
        "德里": ["DEL"], "孟買": ["BOM"], "杜拜": ["DXB"], "杜哈": ["DOH"], "伊斯坦堡": ["IST"],
        "洛杉磯": ["LAX"], "舊金山": ["SFO"], "紐約": ["JFK", "EWR", "LGA"], "西雅圖": ["SEA"], "芝加哥": ["ORD"], "達拉斯": ["DFW"],
        "溫哥華": ["YVR"], "多倫多": ["YYZ"], "夏威夷": ["HNL"], "檀香山": ["HNL"], "關島": ["GUM"], "波士頓": ["BOS"], "華盛頓": ["IAD"],
        "倫敦": ["LHR", "LGW"], "巴黎": ["CDG"], "法蘭克福": ["FRA"], "阿姆斯特丹": ["AMS"], "羅馬": ["FCO"], "馬德里": ["MAD"],
        "維也納": ["VIE"], "蘇黎世": ["ZRH"], "慕尼黑": ["MUC"], "布拉格": ["PRG"], "米蘭": ["MXP"], "巴塞隆納": ["BCN"],
        "雪梨": ["SYD"], "墨爾本": ["MEL"], "布里斯本": ["BNE"], "奧克蘭": ["AKL"],
    ]

    // l10n:ignore-end

    /// 以 IATA、城市、機場名稱或中文城市名搜尋。
    func search(_ query: String, from origin: Airport? = nil, directOnly: Bool = false, limit: Int = 8) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let up = q.uppercased(), low = q.lowercased()
        let aliasHits = Set(Self.aliases.filter { $0.key.contains(q) || q.contains($0.key) }.flatMap(\.value))
        let allowed = (directOnly && origin != nil) ? destinations(from: origin!.iata) : nil

        var scored: [(Int, Int, Airport)] = []
        for a in airports {
            if let allowed, !allowed.contains(a.iata) { continue }
            if a.iata == origin?.iata { continue }
            let city = a.city.lowercased(), name = a.name.lowercased()
            var score: Int?
            if a.iata == up { score = 0 }
            else if aliasHits.contains(a.iata) { score = 1 }
            else if a.iata.hasPrefix(up) && up.count >= 2 { score = 2 }
            else if city.hasPrefix(low) { score = 3 }
            else if city.contains(low) || name.contains(low) || a.country.lowercased() == low { score = 4 }
            if let score { scored.append((score, -(routes[a.iata]?.count ?? 0), a)) }
        }
        scored.sort { ($0.0, $0.1) < ($1.0, $1.1) }
        return scored.prefix(limit).map(\.2)
    }
}

/// 客機的速度曲線:起飛滑行 → 爬升 → 巡航 → 下降 → 降落。
enum FlightProfile {
    static func speedKmh(at d: Double, total: Double, cruise: Double) -> Double {
        let roll = min(3_000, total * 0.02)
        let climb = min(110_000, total * 0.25)
        let desc = min(120_000, total * 0.25)
        let cruise = max(cruise, 400)
        if d > total - roll { return 30 + (280 - 30) * max(0, (total - d) / roll) }
        if d > total - desc { return 280 + (cruise - 280) * min(1, max(0, (total - roll - d) / (desc - roll))) }
        if d < roll { return 30 + (260 - 30) * (d / roll) }
        if d < climb { return 260 + (cruise - 260) * ((d - roll) / (climb - roll)) }
        return cruise
    }

    /// 從 start 公尺處飛到終點所需秒數(數值積分)。
    static func duration(total: Double, cruise: Double, from start: Double = 0) -> Double {
        guard total > start else { return 0 }
        var d = start, t = 0.0
        let step = max(200, total / 2000)
        while d < total {
            let s = min(step, total - d)
            t += s / max(speedKmh(at: d + s / 2, total: total, cruise: cruise) / 3.6, 5)
            d += s
        }
        return t
    }

    /// 起飛後經過 elapsed 秒時,已飛行的距離(公尺)。
    static func distance(afterElapsed elapsed: Double, total: Double, cruise: Double) -> Double {
        var d = 0.0, t = 0.0
        let dt = 1.0
        while t < elapsed, d < total {
            d += max(speedKmh(at: d, total: total, cruise: cruise) / 3.6, 2) * dt
            t += dt
        }
        return min(d, total)
    }

    /// 反解巡航速度,使「從 start 飛到終點」恰好花 seconds 秒。結果限制在 400...1500 km/h。
    static func solveCruise(total: Double, seconds: Double, from start: Double = 0) -> (cruise: Double, feasible: Bool) {
        var lo = 400.0, hi = 1500.0
        if duration(total: total, cruise: hi, from: start) > seconds { return (hi, false) }
        if duration(total: total, cruise: lo, from: start) < seconds { return (lo, true) }
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            if duration(total: total, cruise: mid, from: start) > seconds { lo = mid } else { hi = mid }
        }
        return ((lo + hi) / 2, true)
    }
}
