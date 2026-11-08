import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.clearBeforeQuit() }
}

@main
struct LocationSpooferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Location Spoofer", id: "main") {
            ContentView()
                .environment(model)
                .environment(\.locale, model.language.locale)
                .id(model.language.revision)          // 切換語言時重建畫面,所有文字立即更新
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    delegate.model = model
                    if let dir = ScreenshotRunner.directory { model.demo = true; model.start(); await ScreenshotRunner.run(model: model, dir: dir) }
                    else { model.start() }
                }
        }
        .commands {
            let _ = model.language.revision
            CommandGroup(replacing: .appInfo) {
                Button(L("關於 Location Spoofer")) { AboutPanel.show() }
            }
            CommandMenu(L("定位")) {
                Button(L("開始 / 暫停 / 繼續")) { model.toggleRun() }.keyboardShortcut(.return, modifiers: .command)
                Button(L("停止移動")) { model.controller.stop() }.keyboardShortcut(".", modifiers: .command)
                Button(L("還原真實定位")) { Task { await model.clear() } }.keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button(L("撤銷上一個路徑點")) { model.removeLastWaypoint() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(L("定位模擬"), systemImage: model.phase == .simulating ? "location.fill" : "location") {
            MenuBarContent()
                .environment(model)
                .environment(\.locale, model.language.locale)
                .id(model.language.revision)
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let c = model.controller
        if let cur = model.active {
            Text(String(format: "%.5f, %.5f", cur.latitude, cur.longitude))
            if c.isActive { Text(L("%.0f km/h · 已行進 %@", c.currentSpeedKmh, Format.distance(c.traveled))) }
        } else { Text("未在模擬") }
        let flights = model.scheduler.flights.filter(\.enabled)
        if !flights.isEmpty {
            Divider()
            ForEach(flights) { f in
                let st = model.scheduler.status(of: f)
                switch st.phase {
                case .airborne: Text(L("✈︎ %@ 飛行中", f.title))
                case .boarding: Text(L("%@ 登機中", f.title))
                case .waiting: Text(L("%@ 等待起飛", f.title))
                case .none: Text(L("%@ 無後續班次", f.title))
                }
            }
        }
        Divider()
        if c.state == .running { Button("暫停") { c.pause() } }
        else if c.state == .paused { Button("繼續") { model.startMovement() } }
        if c.isActive { Button("停止移動") { c.stop() } }
        Button("還原真實定位") { Task { await model.clear() } }
        Divider()
        Button(L("關於 Location Spoofer")) { AboutPanel.show() }
        Button("顯示主視窗") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("結束") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
