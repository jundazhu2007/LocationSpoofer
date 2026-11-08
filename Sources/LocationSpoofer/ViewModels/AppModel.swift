import SwiftUI
import MapKit

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, imagery, hybrid
    var id: String { rawValue }
    var title: String { switch self { case .standard: L("標準"); case .imagery: L("衛星"); case .hybrid: L("混合") } }
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: Coordinate
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case idle, working, simulating, failed(String) }

    // Devices
    var devices: [Device] = []
    var selectedDeviceID: Device.ID?
    var phase: Phase = .idle

    // Map
    var picked: Coordinate? { didSet { if picked != oldValue { lookupAddress() } } }
    var pickedAddress = ""
    var syncAll = false
    var trail: [Coordinate] = []
    var camera: MapCameraPosition = .automatic
    var mapStyle: MapStyleChoice = .standard
    var followCamera = false
    var mapDistance: Double = 2000

    // Search
    var searchText = ""
    var searchResults: [SearchResult] = []
    var coordinateText = ""

    // Data
    var library = LibraryData()
    var logText = ""
    var autoClearOnQuit: Bool = UserDefaults.standard.object(forKey: "autoClearOnQuit") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoClearOnQuit, forKey: "autoClearOnQuit") }
    }
    static let hotPlaces: [SavedPlace] = [
        .init(name: "台北 101", coordinate: .init(latitude: 25.033964, longitude: 121.564468)),
        .init(name: "桃園國際機場", coordinate: .init(latitude: 25.0777, longitude: 121.2328)),
        .init(name: "東京鐵塔", coordinate: .init(latitude: 35.658581, longitude: 139.745433)),
        .init(name: "成田機場", coordinate: .init(latitude: 35.7720, longitude: 140.3929)),
        .init(name: "首爾塔", coordinate: .init(latitude: 37.551169, longitude: 126.988227)),
        .init(name: "香港中環", coordinate: .init(latitude: 22.2819, longitude: 114.1583)),
        .init(name: "新加坡魚尾獅", coordinate: .init(latitude: 1.286785, longitude: 103.854503)),
        .init(name: "杜拜哈里發塔", coordinate: .init(latitude: 25.197197, longitude: 55.274376)),
        .init(name: "巴黎鐵塔", coordinate: .init(latitude: 48.858370, longitude: 2.294481)),
        .init(name: "倫敦大笨鐘", coordinate: .init(latitude: 51.500729, longitude: -0.124625)),
        .init(name: "紐約時代廣場", coordinate: .init(latitude: 40.758000, longitude: -73.985500)),
        .init(name: "舊金山金門大橋", coordinate: .init(latitude: 37.819929, longitude: -122.478255)),
        .init(name: "洛杉磯機場 LAX", coordinate: .init(latitude: 33.9416, longitude: -118.4085)),
        .init(name: "雪梨歌劇院", coordinate: .init(latitude: -33.856784, longitude: 151.215297)),
    ]
    let scenarios = ["City Run", "City Bicycle Ride", "Apple", "Freeway Drive"]

    let language = LanguageSettings()
    let controller = MovementController()
    let airports = AirportDB.load()
    let scheduler: FlightScheduler
    let power = PowerService()
    var active: Coordinate? { controller.current }

    private let service = DeviceService()
    private let sender = LocationSender()
    private let store = LibraryStore()
    /// Screenshot / demo mode: connects to no device and never writes the library file.
    var demo = false
    private var pollTask: Task<Void, Never>?
    private var addrTask: Task<Void, Never>?
    private var failures = 0
    private var sentOnce = false

    var selectedDevice: Device? { devices.first { $0.id == selectedDeviceID } }
    /// Devices to send the location to (sync mode = every connected device).
    var targets: [String] {
        if syncAll { let ids = devices.filter(\.isConnected).map(\.id); if !ids.isEmpty { return ids } }
        return selectedDeviceID.map { [$0] } ?? []
    }

    init() {
        let db = airports
        scheduler = FlightScheduler(controller: controller, airports: db)
        library = store.load()
        scheduler.flights = library.flights
        power.wantsActive = scheduler.flights.contains(where: \.enabled)
        scheduler.onChange = { [weak self] in
            guard let self else { return }
            self.library.flights = self.scheduler.flights
            self.persist()
            self.power.wantsActive = self.scheduler.flights.contains(where: \.enabled)
        }
        scheduler.onLog = { [weak self] in self?.log($0) }
        scheduler.onClear = { [weak self] in Task { await self?.clear() } }
        controller.onPosition = { [weak self] c in self?.push(c) }
        Task { [weak self] in
            await self?.sender.setHandler { ok, out in
                Task { @MainActor in self?.handleSend(ok: ok, output: out) }
            }
        }
    }

    func start() {
        guard pollTask == nil else { return }
        scheduler.start()
        if demo { return }
        Task { await power.refreshSleepDisabled() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDevices()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refreshDevices() async {
        devices = await service.list()
        if selectedDeviceID == nil || !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = devices.first(where: \.isConnected)?.id ?? devices.first?.id
        }
    }

    // MARK: Sending locations
    private func push(_ c: Coordinate) {
        if demo { phase = .simulating; return }     // Demo mode: no device connection
        let udids = targets
        guard !udids.isEmpty else { log(L("沒有選擇裝置")); controller.stop(); return }
        if phase != .simulating { phase = .simulating }
        if followCamera { camera = .camera(MapCamera(centerCoordinate: c.clCoordinate, distance: mapDistance)) }
        if trail.last.map({ $0.distance(to: c) > 3 }) ?? true {
            trail.append(c); if trail.count > 4000 { trail.removeFirst(500) }
        }
        Task { await sender.submit(c, udids: udids) }
    }

    private func handleSend(ok: Bool, output: String) {
        if ok { failures = 0; if case .failed = phase, controller.isActive { phase = .simulating }; if !sentOnce { sentOnce = true; log(L("已送出第一筆位置")) }; return }
        failures += 1
        log(output)
        if scheduler.running != nil {     // Scheduled flights never give up: the position is computed from time and catches up once the connection returns
            phase = .failed(L("裝置暫時離線,恢復連線後會自動追上目前位置"))
            return
        }
        if failures >= 3 {
            controller.stop()
            phase = .failed(L("連續 %lld 次送出失敗,已停止。請確認 iPhone 已解鎖且在同一網路", failures))
        }
    }

    // MARK: Actions
    func apply() {
        guard let c = picked else { return }
        controller.teleport(to: c)
        remember(c, name: String(format: "%.5f, %.5f", c.latitude, c.longitude))
        log(L("→ 傳送到 %@", String(format: "%.6f, %.6f", c.latitude, c.longitude)))
    }

    func startMovement() {
        Task {
            failures = 0
            if !controller.isActive { trail.removeAll() }
            await controller.start(fallbackOrigin: picked)
            if controller.state == .idle, !controller.message.isEmpty { log(controller.message) }
        }
    }

    func clear() async {
        let udids = targets
        guard !udids.isEmpty else { return }
        controller.stop()
        phase = .working
        await sender.cancelPending()
        await sender.waitIdle()
        var ok = true
        for u in udids {
            let r = await service.clearLocation(udid: u)
            if r.status != 0 { ok = false; log(r.output) }
        }
        if ok { phase = .idle; sentOnce = false; log(L("→ 已還原真實定位(%lld 台)", udids.count)) }
        else { phase = .failed(L("還原失敗,請看紀錄")) }
    }

    func runScenario(_ name: String) async {
        let udids = targets
        guard !udids.isEmpty else { return }
        controller.stop(); phase = .working
        await sender.cancelPending(); await sender.waitIdle()
        var ok = true
        for u in udids {
            let r = await service.runScenario(name, udid: u)
            if r.status != 0 { ok = false; log(r.output) }
        }
        if ok { phase = .simulating; log(L("→ 情境:%@", name)) } else { phase = .failed(L("情境失敗")) }
    }

    // MARK: Quick locations
    func teleportRandom(radius: Double) {
        guard let base = picked ?? active else { log(L("請先選一個中心點")); return }
        let c = base.moved(distance: radius * Double.random(in: 0...1).squareRoot(), bearing: Double.random(in: 0..<(2 * .pi)))
        picked = c
        camera = .camera(MapCamera(centerCoordinate: c.clCoordinate, distance: max(800, radius * 4)))
        apply()
    }

    /// Travels from the current position to the picked target using the selected transport.
    func travelToPicked() {
        guard let p = picked else { return }
        guard controller.current != nil else { log(L("尚未有目前位置,請先「套用到 iPhone」")); return }
        controller.stop()
        controller.mode = .route
        controller.waypoints = [p]
        controller.startFromCurrent = true
        controller.loop = .once
        startMovement()
    }

    /// Menu bar / shortcut: start, pause, resume.
    func toggleRun() {
        switch controller.state {
        case .running: controller.pause()
        case .paused: startMovement()
        case .idle: controller.mode == .teleport ? apply() : startMovement()
        case .preparing: break
        }
    }

    // MARK: Address
    private func lookupAddress() {
        addrTask?.cancel()
        guard let p = picked else { pickedAddress = ""; return }
        addrTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let req = MKReverseGeocodingRequest(location: CLLocation(latitude: p.latitude, longitude: p.longitude))
            let item = try? await req?.mapItems.first
            guard !Task.isCancelled else { return }
            pickedAddress = item?.address?.fullAddress ?? item?.name ?? ""
        }
    }

    func mapTapped(_ c: Coordinate) {
        switch controller.mode {
        case .route: controller.addWaypoint(c)
        case .orbit, .wander: controller.anchor = c; picked = c
        case .flight: break
        case .teleport, .joystick: picked = c
        }
    }

    func swapAirports() { swap(&controller.flightOrigin, &controller.flightDest); fitFlight() }

    func fitFlight() {
        guard let o = controller.flightOrigin?.coordinate, let d = controller.flightDest?.coordinate else {
            if let a = controller.flightOrigin ?? controller.flightDest { camera = .camera(MapCamera(centerCoordinate: a.coordinate.clCoordinate, distance: 400_000)) }
            return
        }
        let p1 = MKMapPoint(o.clCoordinate), p2 = MKMapPoint(d.clCoordinate)
        let r = MKMapRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
        camera = .rect(r.insetBy(dx: -r.width * 0.3 - 20_000, dy: -r.height * 0.3 - 20_000))
    }

    func reveal(_ c: Coordinate, zoom: Double = 2000) {
        picked = c
        camera = .camera(MapCamera(centerCoordinate: c.clCoordinate, distance: zoom))
    }

    // MARK: Search
    func search() async {
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = searchText
        guard let items = try? await MKLocalSearch(request: req).start().mapItems, !items.isEmpty else {
            searchResults = []; log(L("找不到「%@」", searchText)); return
        }
        searchResults = items.prefix(6).map {
            SearchResult(name: $0.name ?? L("未命名"), subtitle: $0.address?.shortAddress ?? "", coordinate: Coordinate($0.location.coordinate))
        }
        if let first = searchResults.first { reveal(first.coordinate) }
    }

    func goToCoordinateText() {
        guard let c = Coordinate.parse(coordinateText) else { log(L("無法解析座標:%@", coordinateText)); return }
        reveal(c)
    }

    // MARK: Route tools
    func removeLastWaypoint() { if !controller.waypoints.isEmpty { controller.waypoints.removeLast() } }
    func clearWaypoints() { controller.waypoints.removeAll() }
    func reverseWaypoints() { controller.waypoints.reverse() }

    func importGPX() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gpx") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let pts = GPXService.parse(data)
        guard !pts.isEmpty else { log(L("GPX 裡沒有座標點")); return }
        controller.waypoints = pts
        if let f = pts.first { reveal(f, zoom: 5000) }
        log(L("已匯入 %lld 個點:%@", pts.count, url.lastPathComponent))
    }

    func exportGPX() {
        guard !controller.waypoints.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = "route.gpx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let xml = GPXService.export(name: url.deletingPathExtension().lastPathComponent, points: controller.waypoints)
        try? xml.write(to: url, atomically: true, encoding: .utf8)
        log(L("已匯出 %@", url.lastPathComponent))
    }

    func exportTrail() {
        guard trail.count > 1 else { log(L("尚無軌跡")); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "gpx") ?? .xml]
        panel.nameFieldStringValue = "trail.gpx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? GPXService.export(name: "trail", points: trail).write(to: url, atomically: true, encoding: .utf8)
        log(L("已匯出軌跡 %lld 點", trail.count))
    }

    // MARK: Favorites / history
    func savePlace(name: String) {
        guard let c = picked else { return }
        library.places.insert(SavedPlace(name: name.isEmpty ? String(format: "%.4f, %.4f", c.latitude, c.longitude) : name, coordinate: c), at: 0)
        persist()
    }
    func saveRoute(name: String) {
        guard controller.waypoints.count >= 2 else { return }
        library.routes.insert(SavedRoute(name: name.isEmpty ? L("路線 %lld", library.routes.count + 1) : name, waypoints: controller.waypoints), at: 0)
        persist()
    }
    func loadRoute(_ r: SavedRoute) { controller.mode = .route; controller.waypoints = r.waypoints; if let f = r.waypoints.first { reveal(f, zoom: 5000) } }
    func deletePlace(_ p: SavedPlace) { library.places.removeAll { $0.id == p.id }; persist() }
    func deleteRoute(_ r: SavedRoute) { library.routes.removeAll { $0.id == r.id }; persist() }
    func clearHistory() { library.history.removeAll(); persist() }

    private func remember(_ c: Coordinate, name: String) {
        library.history.removeAll { $0.coordinate == c }
        library.history.insert(SavedPlace(name: name, coordinate: c), at: 0)
        if library.history.count > 30 { library.history.removeLast() }
        persist()
    }
    private func persist() { if !demo { store.save(library) } }

    // MARK: Quitting
    func clearBeforeQuit() {
        controller.stop()
        guard !demo, autoClearOnQuit, phase == .simulating else { return }
        for u in targets { DeviceCtl.runSync(["device", "simulate", "location", "clear", "--device", u]) }
    }

    func log(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        logText += t + "\n"
        if logText.count > 10_000 { logText = String(logText.suffix(8_000)) }
    }
}
