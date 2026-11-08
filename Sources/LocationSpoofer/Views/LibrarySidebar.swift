import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 3

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("航班").tag(3); Text("收藏").tag(0); Text("歷史").tag(1); Text("紀錄").tag(2)
            }.pickerStyle(.segmented).labelsHidden().padding()
            switch tab {
            case 0: favorites
            case 1: history
            case 3: ScheduleView()
            default: logView
            }
        }
    }

    private var favorites: some View {
        List {
            Section("地點") {
                if model.library.places.isEmpty { Text("尚無收藏").foregroundStyle(.secondary) }
                ForEach(model.library.places) { p in
                    Button { model.controller.mode = .teleport; model.reveal(p.coordinate) } label: { PlaceRow(name: p.name, c: p.coordinate) }
                        .buttonStyle(.plain)
                        .contextMenu { Button("刪除", role: .destructive) { model.deletePlace(p) } }
                }
            }
            Section("路線") {
                if model.library.routes.isEmpty { Text("尚無儲存的路線").foregroundStyle(.secondary) }
                ForEach(model.library.routes) { r in
                    Button { model.loadRoute(r) } label: {
                        Label(L("%@(%lld 點)", r.name, r.waypoints.count), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("刪除", role: .destructive) { model.deleteRoute(r) } }
                }
            }
        }
    }

    private var history: some View {
        List {
            if model.library.history.isEmpty { Text("尚無歷史").foregroundStyle(.secondary) }
            ForEach(model.library.history) { p in
                Button { model.reveal(p.coordinate) } label: { PlaceRow(name: p.name, c: p.coordinate) }.buttonStyle(.plain)
            }
            if !model.library.history.isEmpty { Button("清除歷史", role: .destructive) { model.clearHistory() } }
        }
    }

    private var logView: some View {
        ScrollView {
            Text(model.logText.isEmpty ? L("尚無紀錄") : model.logText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding()
        }
    }
}

struct PlaceRow: View {
    let name: String; let c: Coordinate
    var body: some View {
        VStack(alignment: .leading) {
            Text(name).lineLimit(1)
            Text(String(format: "%.5f, %.5f", c.latitude, c.longitude)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
