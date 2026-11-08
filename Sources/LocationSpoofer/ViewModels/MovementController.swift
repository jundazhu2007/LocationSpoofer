import SwiftUI

/// 移動引擎:依「真實經過時間 × 速度」計算位置,不受 devicectl 延遲影響。
@MainActor @Observable
final class MovementController {
    enum State: Equatable { case idle, preparing, running, paused }

    // MARK: 設定
    var mode: MovementMode = .teleport
    var transport: Transport = .walk {
        didSet { if transport != .custom { speedKmh = transport.defaultKmh }; invalidateTrack() }
    }
    var speedKmh: Double = 5
    var speedJitterPct: Double = 0
    var gpsJitterMeters: Double = 0
    var smoothMotion = true          // 平滑起步 / 煞車
    var dwellSeconds: Double = 0     // 每個路徑點停留秒數(0 = 不停)
    var repeatCount = 0              // 循環 / 往返圈數(0 = 無限)
    var loop: LoopMode = .once { didSet { invalidateTrack() } }
    var followRoads = true { didSet { invalidateTrack() } }
    var startFromCurrent = true { didSet { invalidateTrack() } }
    var waypoints: [Coordinate] = [] { didSet { invalidateTrack() } }
    var anchor: Coordinate?          // 環繞 / 漫遊的中心
    var radius: Double = 200         // 公尺
    var clockwise = true
    var joystick: CGVector = .zero   // dx 向東、dy 向北,-1...1
    var flightOrigin: Airport?
    var flightDest: Airport?
    var cruiseKmh: Double = 850
    var timeScale: Double = 1        // 時間加速倍率
    /// 設定後,飛行會自動調整巡航速度,使飛機在此時刻落地(固定航班用,可隨時更新以套用誤點)。
    var flightDeadline: Date?
    var now: @MainActor () -> Date = { Date() }

    // MARK: 狀態
    private(set) var state: State = .idle
    private(set) var track: PathTrack?
    private(set) var current: Coordinate?
    private(set) var heading: Double = 0
    private(set) var traveled: Double = 0
    private(set) var laps = 0
    private(set) var progress: Double = 0
    private(set) var message = ""
    /// 最近一次飛行 / 路線是否正常抵達終點(排程器據此判斷落地,不依賴文字)。
    private(set) var arrived = false
    private(set) var currentSpeedKmh: Double = 0
    private(set) var dwellRemaining: Double = 0
    private(set) var cruiseInUse: Double = 850
    private(set) var deadlineFeasible = true

    var onPosition: ((Coordinate) -> Void)?

    private var task: Task<Void, Never>?
    private var speedNoise = 0.0
    private var actualSpeed = 0.0
    private var orbitAngle = 0.0
    private var wanderHeading = 0.0
    private var stops: [Double] = []
    private var lastD = 0.0
    private var lastTick = Date()

    // MARK: 衍生資訊
    var isActive: Bool { state == .running || state == .paused || state == .preparing }
    var displayPath: [Coordinate] {
        if mode == .flight {
            if isActive, let t = track { return t.points }
            if let o = flightOrigin, let d = flightDest { return [o.coordinate, d.coordinate] }
            return []
        }
        return track?.points ?? waypoints
    }
    var flightDistance: Double? {
        guard let o = flightOrigin, let d = flightDest else { return nil }
        return o.coordinate.distance(to: d.coordinate)
    }
    var routeDistance: Double {
        if let t = track { return t.total }
        var pts = waypoints
        if startFromCurrent, let c = current, !pts.isEmpty { pts.insert(c, at: 0) }
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
    var remaining: Double? {
        guard mode == .route || mode == .flight, loop == .once, let t = track else { return nil }
        return max(0, t.total - traveled)
    }
    var etaSeconds: Double? {
        if mode == .flight {
            if let dl = flightDeadline, isActive { return max(0, dl.timeIntervalSince(now())) }
            if let t = track, isActive { return FlightProfile.duration(total: t.total, cruise: cruiseKmh, from: traveled) / max(1, timeScale) }
            guard let d = flightDistance else { return nil }
            return FlightProfile.duration(total: d, cruise: cruiseKmh) / max(1, timeScale)
        }
        let v = speedKmh / 3.6
        guard v > 0 else { return nil }
        if let r = remaining { return r / v + dwellTotalLeft }
        return mode == .route && state == .idle ? routeDistance / v + Double(max(0, waypoints.count - 2)) * dwellSeconds : nil
    }
    private var dwellTotalLeft: Double {
        dwellRemaining + Double(stops.filter { $0 > lastD }.count) * dwellSeconds
    }

    // MARK: 路徑點編輯
    var smartInsert = false          // 點地圖時插入最近的線段,而不是加在最後

    func addWaypoint(_ c: Coordinate) {
        guard smartInsert, waypoints.count >= 2 else { waypoints.append(c); return }
        // 比較:加在最前 / 最後 / 插入各線段 的額外距離
        var best = (cost: c.distance(to: waypoints[0]), index: 0)                      // 加在最前
        let tail = waypoints[waypoints.count - 1].distance(to: c)
        if tail < best.cost { best = (tail, waypoints.count) }
        for i in 0..<(waypoints.count - 1) {
            let a = waypoints[i], b = waypoints[i + 1]
            let extra = a.distance(to: c) + c.distance(to: b) - a.distance(to: b)
            if extra < best.cost { best = (extra, i + 1) }
        }
        waypoints.insert(c, at: best.index)
    }

    func moveWaypoint(_ i: Int, to c: Coordinate) { if waypoints.indices.contains(i) { waypoints[i] = c } }
    func removeWaypoint(_ i: Int) { if waypoints.indices.contains(i) { waypoints.remove(at: i) } }

    // MARK: 控制
    func teleport(to c: Coordinate) {
        stop()
        current = c
        onPosition?(c)
    }

    func start(fallbackOrigin: Coordinate?, flightElapsed: Double = 0) async {
        if state == .paused { resume(); return }
        guard state == .idle else { return }
        message = ""; arrived = false; traveled = 0; laps = 0; progress = 0; speedNoise = 0
        dwellRemaining = 0; lastD = 0
        actualSpeed = smoothMotion ? 0 : speedKmh / 3.6

        switch mode {
        case .teleport:
            return
        case .route:
            var pts = waypoints
            if startFromCurrent, let c = current, let first = pts.first, c.distance(to: first) > 5 { pts.insert(c, at: 0) }
            guard pts.count >= 2 else { message = L("至少需要 2 個點(或先定位後再加 1 個目標點)"); return }
            state = .preparing
            let built = await RoutingService.buildTrack(waypoints: pts, transport: transport, followRoads: followRoads, closed: loop == .loop)
            guard state == .preparing else { return }
            track = built.track; stops = built.stops
            if built.roadLegs + built.fallbackLegs > 0 {
                message = L("沿道路 %lld 段", built.roadLegs) + (built.fallbackLegs > 0 ? L(",%lld 段無路徑改走直線", built.fallbackLegs) : "")
            }
            guard built.track.total > 0 else { state = .idle; message = L("路線長度為 0"); return }
            publish(built.track.points[0], heading: 0)
        case .flight:
            guard let o = flightOrigin, let d = flightDest, o.iata != d.iata else { message = L("請選擇出發與抵達機場"); return }
            loop = .once
            let t = PathTrack(points: [o.coordinate, d.coordinate])
            track = t; stops = []
            cruiseInUse = cruiseKmh
            if let dl = flightDeadline {
                let fullSeconds = dl.timeIntervalSince(now()) + flightElapsed
                cruiseInUse = FlightProfile.solveCruise(total: t.total, seconds: max(60, fullSeconds)).cruise
            }
            if flightElapsed > 0 { traveled = FlightProfile.distance(afterElapsed: flightElapsed, total: t.total, cruise: cruiseInUse) }
            lastD = traveled
            let startPos = t.sample(at: traveled)
            publish(startPos?.coordinate ?? o.coordinate, heading: startPos?.heading ?? o.coordinate.bearing(to: d.coordinate))
        case .joystick:
            guard let origin = current ?? fallbackOrigin else { message = L("請先在地圖點選起點"); return }
            publish(origin, heading: heading)
        case .orbit:
            guard let c = anchor ?? fallbackOrigin else { message = L("請先在地圖點選圓心"); return }
            anchor = c; orbitAngle = 0
            publish(c.moved(distance: radius, bearing: 0), heading: clockwise ? .pi / 2 : -.pi / 2)
        case .wander:
            guard let c = anchor ?? fallbackOrigin else { message = L("請先在地圖點選中心"); return }
            anchor = c; wanderHeading = Double.random(in: 0..<(2 * .pi))
            if current == nil || current!.distance(to: c) > radius { publish(c, heading: wanderHeading) }
        }
        begin()
    }

    func pause() { guard state == .running else { return }; task?.cancel(); state = .paused }
    func resume() { guard state == .paused else { return }; begin() }

    func stop() {
        task?.cancel(); task = nil
        state = .idle; currentSpeedKmh = 0; dwellRemaining = 0
    }

    private func invalidateTrack() { if state == .idle { track = nil; stops = [] } }

    // MARK: 迴圈
    private func begin() {
        state = .running
        task?.cancel()
        lastTick = now()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { break }
                guard let self else { return }
                let t = self.now()
                let dt = min(max(t.timeIntervalSince(self.lastTick), 0), 6 * 3600)
                self.lastTick = t
                self.tick(dt: dt)
            }
        }
    }

    private func tick(dt: Double) {
        guard state == .running else { return }
        speedNoise += (Double.random(in: -1...1) * speedJitterPct / 100 - speedNoise) * 0.3
        let scale = max(1, timeScale)
        let target = max(0.05, speedKmh / 3.6 * (1 + speedNoise)) * scale

        if dwellRemaining > 0 {
            dwellRemaining -= dt; currentSpeedKmh = 0; actualSpeed = 0
            if gpsJitterMeters > 0, let c = current { publish(c, heading: heading) }
            if dwellRemaining <= 0 { dwellRemaining = 0 }
            return
        }

        var goal = target
        if mode == .flight, let t = track {
            if let dl = flightDeadline {
                let left = dl.timeIntervalSince(now())
                if left <= 0 { traveled = t.total; deadlineFeasible = true }
                else {
                    let r = FlightProfile.solveCruise(total: t.total, seconds: left, from: traveled)
                    cruiseInUse = r.cruise; deadlineFeasible = r.feasible
                }
            } else { cruiseInUse = cruiseKmh }
            goal = FlightProfile.speedKmh(at: traveled, total: t.total, cruise: cruiseInUse) / 3.6 * (1 + speedNoise) * scale
            actualSpeed = goal
        } else if smoothMotion {
            let accel = min(max(target / 10, 0.5), 8)            // 約 10 秒加速到目標速度
            if mode == .route, loop == .once, let r = remaining { goal = min(target, max(0.5, sqrt(2 * accel * r))) }
            actualSpeed = goal > actualSpeed ? min(goal, max(actualSpeed, 0.3) + accel * dt) : goal
        } else { actualSpeed = goal }
        let v = actualSpeed
        currentSpeedKmh = v * 3.6

        switch mode {
        case .route, .flight: tickRoute(step: v * dt)
        case .joystick: tickJoystick(v: v, dt: dt)
        case .orbit: tickOrbit(v: v, dt: dt)
        case .wander: tickWander(v: v, dt: dt)
        case .teleport: break
        }
    }

    private func fold(_ t: Double, total: Double) -> (d: Double, reversed: Bool) {
        switch loop {
        case .once: return (min(t, total), false)
        case .loop: return (t.truncatingRemainder(dividingBy: total), false)
        case .pingPong:
            let m = t.truncatingRemainder(dividingBy: 2 * total)
            return m > total ? (2 * total - m, true) : (m, false)
        }
    }

    private func tickRoute(step: Double) {
        guard let track, track.total > 0 else { return }
        let total = track.total
        let period = loop == .pingPong ? 2 * total : total
        let limit: Double? = loop == .once ? total : (repeatCount > 0 ? period * Double(repeatCount) : nil)

        traveled += step
        var finished = false
        if let limit, traveled >= limit { traveled = limit; finished = true }
        var (d, reversed) = fold(traveled, total: total)
        laps = Int(traveled / period)

        // 途中停留:若這一步跨過某個路徑點,就停在該點
        if !finished, dwellSeconds > 0, abs(d - lastD) < total / 2 {
            let forward = d >= lastD
            let hit = stops.filter { forward ? ($0 > lastD && $0 <= d) : ($0 < lastD && $0 >= d) }
                .min { abs($0 - lastD) < abs($1 - lastD) }
            if let s = hit {
                d = s
                let base = (traveled / period).rounded(.down) * period
                traveled = base + (reversed ? 2 * total - s : s)
                dwellRemaining = dwellSeconds * Double.random(in: 0.7...1.3)
            }
        }
        lastD = d
        progress = d / total
        if let s = track.sample(at: d) { publish(s.coordinate, heading: reversed ? s.heading + .pi : s.heading) }
        if finished { stop(); arrived = true; message = L("已抵達終點") }
    }

    private func tickJoystick(v: Double, dt: Double) {
        let mag = min(1, hypot(joystick.dx, joystick.dy))
        guard mag > 0.05, let cur = current else { currentSpeedKmh = 0; return }
        let b = atan2(joystick.dx, joystick.dy)
        let dist = v * mag * dt
        traveled += dist
        currentSpeedKmh = v * mag * 3.6
        publish(cur.moved(distance: dist, bearing: b), heading: b)
    }

    private func tickOrbit(v: Double, dt: Double) {
        guard let c = anchor else { return }
        let r = max(1, radius)
        orbitAngle += (v / r) * dt * (clockwise ? 1 : -1)
        traveled += v * dt
        laps = Int(abs(orbitAngle) / (2 * .pi))
        publish(c.moved(distance: r, bearing: orbitAngle), heading: orbitAngle + (clockwise ? .pi / 2 : -.pi / 2))
        if repeatCount > 0, laps >= repeatCount { stop(); message = L("已繞完 %lld 圈", repeatCount) }
    }

    private func tickWander(v: Double, dt: Double) {
        guard let cur = current, let c = anchor else { return }
        wanderHeading += Double.random(in: -1...1) * 1.2 * dt
        if cur.distance(to: c) > radius { wanderHeading = cur.bearing(to: c) + Double.random(in: -0.5...0.5) }
        let dist = v * dt
        traveled += dist
        publish(cur.moved(distance: dist, bearing: wanderHeading), heading: wanderHeading)
    }

    private func publish(_ base: Coordinate, heading h: Double) {
        current = base; heading = h
        onPosition?(base.jittered(meters: gpsJitterMeters))
    }
}
