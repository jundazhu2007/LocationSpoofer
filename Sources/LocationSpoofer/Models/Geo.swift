import CoreLocation

private extension Double {
    var rad: Double { self * .pi / 180 }
    var deg: Double { self * 180 / .pi }
}

struct Coordinate: Equatable, Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double

    static let earthRadius = 6_371_008.8

    init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    init(_ c: CLLocationCoordinate2D) { self.init(latitude: c.latitude, longitude: c.longitude) }
    var clCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }

    /// 兩點大圓距離(公尺)。
    func distance(to o: Coordinate) -> Double {
        let p1 = latitude.rad, p2 = o.latitude.rad
        let dp = p2 - p1, dl = (o.longitude - longitude).rad
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * Self.earthRadius * asin(min(1, sqrt(a)))
    }

    /// 初始方位角(弧度,北 = 0,順時針)。
    func bearing(to o: Coordinate) -> Double {
        let p1 = latitude.rad, p2 = o.latitude.rad, dl = (o.longitude - longitude).rad
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return atan2(y, x)
    }

    /// 朝某方位角(弧度)移動 distance 公尺後的座標。
    func moved(distance d: Double, bearing b: Double) -> Coordinate {
        let ang = d / Self.earthRadius
        let p1 = latitude.rad, l1 = longitude.rad
        let p2 = asin(sin(p1) * cos(ang) + cos(p1) * sin(ang) * cos(b))
        let l2 = l1 + atan2(sin(b) * sin(ang) * cos(p1), cos(ang) - sin(p1) * sin(p2))
        var lon = l2.deg
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return Coordinate(latitude: p2.deg, longitude: lon)
    }

    /// 大圓上的內插(0...1)。
    func interpolated(to o: Coordinate, fraction f: Double) -> Coordinate {
        let d = distance(to: o) / Self.earthRadius
        guard d > 1e-9, d < .pi - 1e-9 else {
            return Coordinate(latitude: latitude + (o.latitude - latitude) * f, longitude: longitude + (o.longitude - longitude) * f)
        }
        let a = sin((1 - f) * d) / sin(d), b = sin(f * d) / sin(d)
        let p1 = latitude.rad, l1 = longitude.rad, p2 = o.latitude.rad, l2 = o.longitude.rad
        let x = a * cos(p1) * cos(l1) + b * cos(p2) * cos(l2)
        let y = a * cos(p1) * sin(l1) + b * cos(p2) * sin(l2)
        let z = a * sin(p1) + b * sin(p2)
        return Coordinate(latitude: atan2(z, sqrt(x * x + y * y)).deg, longitude: atan2(y, x).deg)
    }

    /// 在半徑內隨機偏移(模擬 GPS 抖動)。
    func jittered(meters: Double) -> Coordinate {
        guard meters > 0 else { return self }
        return moved(distance: Double.random(in: 0...meters), bearing: Double.random(in: 0..<(2 * .pi)))
    }

    /// 解析「25.03, 121.56」之類的貼上文字。
    static func parse(_ text: String) -> Coordinate? {
        // Google Maps 分享連結: ...!3d25.03!4d121.56
        if let m = text.firstMatch(of: /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/),
           let la = Double(m.1), let lo = Double(m.2) {
            let c = Coordinate(latitude: la, longitude: lo)
            if c.isValid { return c }
        }
        let nums = text.matches(of: /-?\d+(?:\.\d+)?/).compactMap { Double($0.output) }
        guard nums.count >= 2 else { return nil }
        let c = Coordinate(latitude: nums[0], longitude: nums[1])
        return c.isValid ? c : nil
    }
}

/// 折線路徑,可依「已行進距離」取樣位置與方向。每段以大圓內插。
struct PathTrack: Sendable {
    let points: [Coordinate]
    private let cumulative: [Double]
    var total: Double { cumulative.last ?? 0 }

    init(points raw: [Coordinate]) {
        var pts: [Coordinate] = []
        for p in raw where pts.last != p { pts.append(p) }
        points = pts
        var c: [Double] = [0]
        for i in 1..<max(pts.count, 1) { c.append(c[i - 1] + pts[i - 1].distance(to: pts[i])) }
        cumulative = pts.isEmpty ? [] : c
    }

    func sample(at distance: Double) -> (coordinate: Coordinate, heading: Double)? {
        guard let first = points.first else { return nil }
        guard points.count > 1, total > 0 else { return (first, 0) }
        let d = min(max(distance, 0), total)
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if cumulative[mid] <= d { lo = mid } else { hi = mid } }
        let seg = cumulative[hi] - cumulative[lo]
        let f = seg > 0 ? (d - cumulative[lo]) / seg : 0
        return (points[lo].interpolated(to: points[hi], fraction: f), points[lo].bearing(to: points[hi]))
    }
}
