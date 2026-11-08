import SwiftUI
import MapKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSidebar = true
    @State private var keys: Set<String> = []

    var body: some View {
        @Bindable var model = model
        @Bindable var lang = model.language
        NavigationSplitView {
            ControlPanel()
                .navigationSplitViewColumnWidth(min: 340, ideal: 370, max: 440)
        } detail: {
            MapArea()
                .inspector(isPresented: $showSidebar) {
                    LibrarySidebar().inspectorColumnWidth(min: 300, ideal: 360, max: 460)
                }
        }
        .toolbar {
            ToolbarItem {
                Picker("地圖", selection: $model.mapStyle) {
                    ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            ToolbarItem {
                Toggle("跟隨", systemImage: "scope", isOn: $model.followCamera).toggleStyle(.button)
            }
            ToolbarItem {
                Menu {
                    Picker("語言", selection: $lang.selection) {
                        ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }.pickerStyle(.inline)
                } label: { Label("語言", systemImage: "globe") }
            }
            ToolbarItem { Button("關於 Location Spoofer", systemImage: "info.circle") { AboutPanel.show() }.help("關於 Location Spoofer") }
            ToolbarItem { Button("收藏與紀錄", systemImage: "sidebar.trailing") { showSidebar.toggle() } }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat, .up]) { press in handleKey(press) }
        .task { model.start() }
    }

    /// 方向鍵 / WASD → 搖桿
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard model.controller.mode == .joystick else { return .ignored }
        let ch = press.characters.lowercased()
        let dir: String? = switch press.key {
        case .upArrow: "n"
        case .downArrow: "s"
        case .leftArrow: "w"
        case .rightArrow: "e"
        default: ["w": "n", "s": "s", "a": "w", "d": "e"][ch]
        }
        guard let dir else { return .ignored }
        if press.phase == .up { keys.remove(dir) } else { keys.insert(dir) }
        var dx = (keys.contains("e") ? 1.0 : 0) - (keys.contains("w") ? 1.0 : 0)
        var dy = (keys.contains("n") ? 1.0 : 0) - (keys.contains("s") ? 1.0 : 0)
        let m = hypot(dx, dy); if m > 1 { dx /= m; dy /= m }
        model.controller.joystick = CGVector(dx: dx, dy: dy)
        return .handled
    }
}

// MARK: - 地圖

struct MapArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let c = model.controller
        MapReader { proxy in
            Map(position: $model.camera) {
                if c.displayPath.count >= 2 {
                    MapPolyline(coordinates: c.displayPath.map(\.clCoordinate), contourStyle: .geodesic)
                        .stroke(.blue.opacity(0.85), lineWidth: 4)
                }
                if model.trail.count >= 2 {
                    MapPolyline(coordinates: model.trail.map(\.clCoordinate)).stroke(.green, lineWidth: 3)
                }
                ForEach(Array(c.waypoints.enumerated()), id: \.offset) { i, w in
                    Annotation("", coordinate: w.clCoordinate) {
                        Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(.blue, in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 2)
                            .contentShape(Circle())
                            .onTapGesture { }     // 避免點到圓點時又新增路徑點
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { v in
                                    if let coord = proxy.convert(v.location, from: .global) { c.moveWaypoint(i, to: Coordinate(coord)) }
                                })
                            .contextMenu { Button("刪除此點", systemImage: "trash", role: .destructive) { c.removeWaypoint(i) } }
                            .help("拖曳移動,右鍵刪除")
                    }
                }
                if (c.mode == .orbit || c.mode == .wander), let a = c.anchor {
                    MapCircle(center: a.clCoordinate, radius: c.radius)
                        .foregroundStyle(.blue.opacity(0.12)).stroke(.blue, lineWidth: 2)
                    Marker("中心", systemImage: "scope", coordinate: a.clCoordinate).tint(.blue)
                }
                if let p = model.picked, c.mode == .teleport || c.mode == .joystick {
                    Marker("選取", coordinate: p.clCoordinate).tint(.red)
                }
                if c.mode == .flight {
                    ForEach([c.flightOrigin, c.flightDest].compactMap { $0 }) { a in
                        Annotation(a.iata, coordinate: a.coordinate.clCoordinate) {
                            Image(systemName: "airplane.circle.fill").font(.title).foregroundStyle(.white, .blue).shadow(radius: 2)
                        }
                    }
                }
                if let cur = c.current {
                    Annotation("", coordinate: cur.clCoordinate) {
                        if c.mode == .flight {
                            Image(systemName: "airplane").font(.system(size: 30)).foregroundStyle(.orange)
                                .rotationEffect(.radians(c.heading - .pi / 2)).shadow(radius: 3)
                        } else {
                            Image(systemName: "location.north.circle.fill")
                                .font(.system(size: 30)).foregroundStyle(.white, .green)
                                .rotationEffect(.radians(c.heading)).shadow(radius: 3)
                        }
                    }
                }
            }
            .mapStyle(model.mapStyle.style)
            .mapControls { MapCompass(); MapScaleView(); MapZoomStepper() }
            .onMapCameraChange { ctx in model.mapDistance = ctx.camera.distance }
            .onTapGesture { pt in
                if let coord = proxy.convert(pt, from: .local) { model.mapTapped(Coordinate(coord)) }
            }
        }
        .overlay(alignment: .bottom) { HUD().padding(.bottom, 24) }
    }
}

// MARK: - 資訊列

struct HUD: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = model.controller
        if c.isActive || !c.message.isEmpty {
            VStack(spacing: 10) {
                if c.isActive {
                    HStack(spacing: 20) {
                        Stat(title: "速度", value: String(format: "%.0f km/h", c.currentSpeedKmh))
                        Stat(title: "已行進", value: Format.distance(c.traveled))
                        if let r = c.remaining { Stat(title: "剩餘", value: Format.distance(r)) }
                        if let e = c.etaSeconds, c.remaining != nil { Stat(title: "預計", value: Format.duration(e)) }
                        if c.dwellRemaining > 0 { Stat(title: "停留", value: L("%lld 秒", Int(c.dwellRemaining.rounded(.up)))) }
                        if c.timeScale > 1, c.mode == .route || c.mode == .flight { Stat(title: "時間加速", value: "×\(Int(c.timeScale))") }
                        if c.laps > 0 { Stat(title: "圈數", value: "\(c.laps)") }
                        Stat(title: "方位", value: String(format: "%.0f°", (c.heading * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)))
                    }
                    if c.mode == .flight || (c.mode == .route && c.loop == .once) { ProgressView(value: c.progress).frame(width: 360) }
                    HStack {
                        if c.state == .paused {
                            Button("繼續", systemImage: "play.fill") { model.startMovement() }
                        } else if c.state == .running {
                            Button("暫停", systemImage: "pause.fill") { c.pause() }
                        } else { ProgressView().controlSize(.small); Text("規劃路線中…") }
                        Button("停止", systemImage: "stop.fill") { c.stop() }
                    }.buttonStyle(.bordered)
                }
                if !c.message.isEmpty { Text(c.message).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}

struct Stat: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).monospacedDigit().bold())
            Text(L(title)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
