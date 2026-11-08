import SwiftUI

struct ControlPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var c = model.controller
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DeviceSection()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(MovementMode.allCases) { m in
                        Button { if m != c.mode { c.stop(); c.mode = m } } label: {
                            VStack(spacing: 3) {
                                Image(systemName: m.symbol).font(.title3)
                                Text(m.title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered).tint(c.mode == m ? .accentColor : .secondary)
                    }
                }

                LocationSection()

                switch c.mode {
                case .teleport: TeleportSection()
                case .route: RouteSection()
                case .flight: FlightSection()
                case .joystick: JoystickSection()
                case .orbit: AreaSection(title: "環繞", hint: "點地圖設定圓心,以半徑繞圈", showsDirection: true)
                case .wander: AreaSection(title: "隨機漫遊", hint: "點地圖設定中心,在半徑內隨機走動", showsDirection: false)
                }

                if c.mode != .teleport && c.mode != .flight { SpeedSection() }
                ActionSection()
                AdvancedSection()

                Divider()
                Button { AboutPanel.show() } label: {
                    Label("關於 Location Spoofer", systemImage: "info.circle")
                    Text("· \(AppInfo.author)").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless).font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sections

struct DeviceSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        HStack {
            Picker("裝置", selection: $model.selectedDeviceID) {
                if model.devices.isEmpty { Text("未偵測到 iPhone").tag(Device.ID?.none) }
                ForEach(model.devices) {
                    Label("\($0.name) · iOS \($0.osVersion)", systemImage: $0.isWireless ? "wifi" : "cable.connector")
                        .tag(Device.ID?.some($0.id))
                }
            }.labelsHidden()
            Circle().fill(model.selectedDevice?.isConnected == true ? .green : .orange).frame(width: 10, height: 10)
                .help(model.selectedDevice?.isConnected == true ? L("已連線") : L("尚未連線(解鎖 iPhone 後會自動連線)"))
            Button("重新整理", systemImage: "arrow.clockwise") { Task { await model.refreshDevices() } }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }
    }
}

struct LocationSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜尋地點,按 Enter", text: $model.searchText)
                .onSubmit { Task { await model.search() } }
            if model.searchResults.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.searchResults) { r in
                        Button { model.reveal(r.coordinate) } label: {
                            VStack(alignment: .leading) {
                                Text(r.name).font(.callout)
                                if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption2).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField("貼上座標,例如 25.033, 121.564", text: $model.coordinateText)
                    .onSubmit { model.goToCoordinateText() }
                Button("前往") { model.goToCoordinateText() }
            }
            Menu("熱門地點", systemImage: "globe.asia.australia") {
                ForEach(AppModel.hotPlaces) { p in Button(L(p.name)) { model.reveal(p.coordinate, zoom: 4000) } }
            }.menuStyle(.button).controlSize(.small)
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct TeleportSection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var randomRadius = 500.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = model.picked {
                Text(L("已選 %.6f, %.6f", p.latitude, p.longitude)).font(.callout.monospacedDigit()).textSelection(.enabled)
                if !model.pickedAddress.isEmpty { Text(model.pickedAddress).font(.caption).foregroundStyle(.secondary) }
                if let cur = model.active, cur.distance(to: p) >= 10 {
                    let d = cur.distance(to: p)
                    let kmh = model.controller.speedKmh
                    Label(L("距目前位置 %@", Format.distance(d)) + (kmh > 0 ? L(",以 %lld km/h 約 %@", Int(kmh), Format.duration(d / (kmh / 3.6))) : ""),
                          systemImage: "ruler").font(.caption)
                }
                HStack {
                    TextField("收藏名稱", text: $name).textFieldStyle(.roundedBorder)
                    Button("收藏", systemImage: "star") { model.savePlace(name: name); name = "" }
                }
                Button("走過去(以下方交通方式從目前位置前往)", systemImage: "figure.walk.motion") { model.travelToPicked() }
                    .controlSize(.small).disabled(model.active == nil)
            } else { Text("點地圖或搜尋以選擇位置").font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button("隨機附近", systemImage: "dice") { model.teleportRandom(radius: randomRadius) }
                    .controlSize(.small).disabled(model.picked == nil && model.active == nil)
                Slider(value: Binding(get: { log(randomRadius / 50) / log(1000) }, set: { randomRadius = (50 * pow(1000, $0)).rounded() }))
                Text(Format.distance(randomRadius)).font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
            }
        }
    }
}

struct RouteSection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    var body: some View {
        @Bindable var c = model.controller
        VStack(alignment: .leading, spacing: 8) {
            Text(L("點地圖加入路徑點(%lld 個);拖曳編號圓點可移動,右鍵可刪除", c.waypoints.count)).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("智慧插入:點線段旁邊,插入最近的一段", isOn: $c.smartInsert).font(.caption)
            HStack {
                Button("撤銷", systemImage: "arrow.uturn.backward") { model.removeLastWaypoint() }
                Button("清除", systemImage: "trash") { model.clearWaypoints() }
                Button("反轉", systemImage: "arrow.left.arrow.right") { model.reverseWaypoints() }
            }.controlSize(.small).disabled(c.waypoints.isEmpty)
            HStack {
                Button("匯入 GPX", systemImage: "square.and.arrow.down") { model.importGPX() }
                Button("匯出 GPX", systemImage: "square.and.arrow.up") { model.exportGPX() }.disabled(c.waypoints.isEmpty)
            }.controlSize(.small)
            HStack {
                TextField("路線名稱", text: $name).textFieldStyle(.roundedBorder)
                Button("儲存", systemImage: "star") { model.saveRoute(name: name); name = "" }.disabled(c.waypoints.count < 2)
            }
            Picker("方式", selection: $c.loop) { ForEach(LoopMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if c.loop != .once {
                Stepper(c.repeatCount == 0 ? L("重複:無限") : L("重複 %lld 圈", c.repeatCount), value: $c.repeatCount, in: 0...99)
            }
            HStack {
                Text("途中停留").font(.caption)
                Slider(value: $c.dwellSeconds, in: 0...300, step: 5)
                Text(c.dwellSeconds == 0 ? L("不停") : L("%lld 秒", Int(c.dwellSeconds))).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
            }
            if c.transport.routing != .straight {
                Toggle("沿道路行走(MapKit 導航路線)", isOn: $c.followRoads)
            }
            Toggle("從目前位置出發", isOn: $c.startFromCurrent)
            if !c.waypoints.isEmpty {
                let d = c.routeDistance
                Label(L("總距離 %@", Format.distance(d)), systemImage: "ruler")
                    .font(.callout)
                if let e = c.etaSeconds { Label(L("以 %lld km/h 約 %@", Int(c.speedKmh), Format.duration(e)), systemImage: "clock").font(.callout) }
            }
        }
    }
}

struct JoystickSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var c = model.controller
        VStack(spacing: 8) {
            JoystickView(vector: $c.joystick)
            Text("拖曳搖桿,或用方向鍵 / WASD(北在上)").font(.caption).foregroundStyle(.secondary)
            Text("先點地圖選起點並按「傳送」,再啟用搖桿").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct AreaSection: View {
    @Environment(AppModel.self) private var model
    let title: String; let hint: String; let showsDirection: Bool
    var body: some View {
        @Bindable var c = model.controller
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(.callout)
            HStack {
                Text("半徑").frame(width: 36, alignment: .leading)
                Slider(value: Binding(get: { log(c.radius / 10) / log(5000) },
                                      set: { c.radius = (10 * pow(5000, $0)).rounded() }))
                Text(Format.distance(c.radius)).font(.callout.monospacedDigit()).frame(width: 64, alignment: .trailing)
            }
            if showsDirection { Stepper(c.repeatCount == 0 ? L("圈數:無限") : L("繞 %lld 圈", c.repeatCount), value: $c.repeatCount, in: 0...99) }
            if showsDirection { Picker("方向", selection: $c.clockwise) { Text("順時針").tag(true); Text("逆時針").tag(false) }.pickerStyle(.segmented) }
        }
    }
}

struct SpeedSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var c = model.controller
        let speed = Binding<Double>(get: { c.speedKmh }, set: { c.speedKmh = max(1, $0); if c.transport != .custom { c.transport = .custom } })
        VStack(alignment: .leading, spacing: 8) {
            Text("交通方式與速度").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Transport.allCases) { t in
                    Button { c.transport = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.title3)
                            Text(t.title).font(.caption2)
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(c.transport == t ? .accentColor : .secondary)
                    .help("\(t.title) \(Int(t.defaultKmh)) km/h")
                }
            }
            HStack {
                Slider(value: Binding(get: { log(max(c.speedKmh, 1)) / log(3000) },
                                      set: { speed.wrappedValue = pow(3000, $0).rounded() }))
                TextField("", value: speed, format: .number.precision(.fractionLength(0)))
                    .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                Text("km/h").font(.caption)
            }
            Text(String(format: "= %.1f m/s · %.1f mph", c.speedKmh / 3.6, c.speedKmh / 1.609344))
                .font(.caption).foregroundStyle(.secondary)
            Toggle("平滑起步與煞車(客機會先加速)", isOn: $c.smoothMotion).font(.caption)
            HStack {
                Text("速度起伏").font(.caption).frame(width: 60, alignment: .leading)
                Slider(value: $c.speedJitterPct, in: 0...40)
                Text("±\(Int(c.speedJitterPct))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
        }
    }
}

struct ActionSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let c = model.controller
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if c.mode == .teleport {
                    Button("套用到 iPhone", systemImage: "location.fill") { model.apply() }
                        .buttonStyle(.borderedProminent).disabled(model.picked == nil || model.selectedDevice == nil)
                } else {
                    Button(startTitle(c), systemImage: "play.fill") { model.startMovement() }
                        .buttonStyle(.borderedProminent)
                        .disabled(c.isActive && c.state != .paused || model.selectedDevice == nil)
                }
                Button("還原", systemImage: "arrow.uturn.backward") { Task { await model.clear() } }
                Menu("Apple 情境", systemImage: "sparkles") {
                    ForEach(model.scenarios, id: \.self) { s in Button(s) { Task { await model.runScenario(s) } } }
                }.menuStyle(.button)
            }
            PhaseLabel(phase: model.phase)
        }
    }
    private func startTitle(_ c: MovementController) -> String {
        if c.state == .paused { return L("繼續") }
        return switch c.mode { case .route: L("開始移動"); case .flight: L("起飛"); case .joystick: L("啟用搖桿"); case .orbit: L("開始環繞"); default: L("開始漫遊") }
    }
}

struct AdvancedSection: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        @Bindable var c = model.controller
        DisclosureGroup("進階") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GPS 抖動").font(.caption).frame(width: 60, alignment: .leading)
                    Slider(value: $c.gpsJitterMeters, in: 0...30)
                    Text("\(Int(c.gpsJitterMeters)) m").font(.caption.monospacedDigit()).frame(width: 40)
                }
                HStack {
                    Text("時間加速").font(.caption)
                    Picker("", selection: $c.timeScale) {
                        ForEach([1.0, 2, 5, 10, 30, 60, 120, 300], id: \.self) { Text("×\(Int($0))").tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Text("(路線與飛行)").font(.caption2).foregroundStyle(.secondary)
                }
                Toggle("同步到所有已連線裝置(iPhone + iPad)", isOn: $model.syncAll)
                HStack {
                    Text(L("軌跡 %lld 點", model.trail.count)).font(.caption)
                    Button("匯出 GPX", systemImage: "square.and.arrow.up") { model.exportTrail() }.controlSize(.small).disabled(model.trail.count < 2)
                    Button("清除", systemImage: "trash") { model.trail.removeAll() }.controlSize(.small).disabled(model.trail.isEmpty)
                }
                Toggle("結束 app 時自動還原真實定位", isOn: $model.autoClearOnQuit)
                Text("提示:devicectl 只能設定經緯度,無法指定海拔與速度欄位。").font(.caption2).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
    }
}

struct PhaseLabel: View {
    let phase: AppModel.Phase
    var body: some View {
        switch phase {
        case .idle: EmptyView()
        case .working: Label("處理中…", systemImage: "hourglass").font(.caption)
        case .simulating: Label("模擬定位中", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let m): Label(m, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
        }
    }
}

// MARK: - Joystick

struct JoystickView: View {
    @Binding var vector: CGVector
    private let size: CGFloat = 130
    var body: some View {
        let r = size / 2
        ZStack {
            Circle().fill(.quaternary)
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 1)
            Image(systemName: "arrow.up").font(.caption).foregroundStyle(.secondary).offset(y: -r + 12)
            Circle().fill(.tint).frame(width: 44, height: 44)
                .offset(x: vector.dx * (r - 22), y: -vector.dy * (r - 22))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                var dx = (v.location.x - r) / (r - 22), dy = -(v.location.y - r) / (r - 22)
                let m = hypot(dx, dy); if m > 1 { dx /= m; dy /= m }
                vector = CGVector(dx: dx, dy: dy)
            }
            .onEnded { _ in vector = .zero })
    }
}

// MARK: - Flight

struct FlightSection: View {
    @Environment(AppModel.self) private var model
    @State private var directOnly = true
    private let scales: [Double] = [1, 2, 5, 10, 30, 60, 120, 300]

    var body: some View {
        @Bindable var c = model.controller
        VStack(alignment: .leading, spacing: 10) {
            Label("機場到機場", systemImage: "airplane").font(.headline)

            AirportPicker(title: L("出發"), selection: $c.flightOrigin, origin: nil, directOnly: false)
            HStack {
                Button("對調", systemImage: "arrow.up.arrow.down") { model.swapAirports() }
                    .controlSize(.small).disabled(c.flightOrigin == nil && c.flightDest == nil)
                Spacer(minLength: 0)
                Toggle("只列直飛", isOn: $directOnly).font(.caption).controlSize(.small).disabled(c.flightOrigin == nil)
            }
            AirportPicker(title: L("抵達"), selection: $c.flightDest, origin: c.flightOrigin, directOnly: directOnly)

            if let o = c.flightOrigin, let d = c.flightDest {
                if !model.airports.hasDirect(o.iata, d.iata) {
                    Label("這兩地沒有定期直飛航班", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let dist = c.flightDistance {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(L("航程 %@", Format.distance(dist)), systemImage: "ruler")
                        if let e = c.etaSeconds {
                            Label(L("飛行約 %@", Format.duration(e)) + (c.timeScale > 1 ? "(×\(Int(c.timeScale)))" : ""), systemImage: "clock")
                        }
                    }.font(.callout)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("巡航").font(.caption)
                    Slider(value: $c.cruiseKmh, in: 500...1000, step: 10)
                    Text("\(Int(c.cruiseKmh))").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                }
                GridRow {
                    Text("加速").font(.caption)
                    Picker("", selection: $c.timeScale) { ForEach(scales, id: \.self) { Text("×\(Int($0))").tag($0) } }
                        .labelsHidden().pickerStyle(.menu).gridCellColumns(2)
                }
            }

            Text("速度曲線:起飛 → 爬升 → 巡航 → 下降 → 降落。路徑為大圓航線,真實航班會因風與空域略有繞行。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: c.flightOrigin) { model.fitFlight() }
        .onChange(of: c.flightDest) { model.fitFlight() }
    }
}

struct AirportPicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var selection: Airport?
    let origin: Airport?
    let directOnly: Bool
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let a = selection {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(a.iata) · \(a.city)").font(.body.bold()).lineLimit(1)
                        Text("\(a.name),\(a.country)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("清除", systemImage: "xmark.circle.fill") { selection = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                .padding(8).background(.quaternary, in: .rect(cornerRadius: 8))
            } else {
                TextField(L("%@:TPE、桃園…", title), text: $query).textFieldStyle(.roundedBorder)
                let results = model.airports.search(query, from: origin, directOnly: directOnly)
                ForEach(results) { a in
                    Button { selection = a; query = "" } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(a.iata) · \(a.city)(\(a.country))").font(.callout).lineLimit(1)
                            Text(a.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
                if !query.isEmpty && results.isEmpty { Text("找不到符合的機場").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
