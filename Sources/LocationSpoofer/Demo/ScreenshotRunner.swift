import AppKit
import SwiftUI
import MapKit
import ScreenCaptureKit

/// Demo / screenshot mode: only enabled when the `LS_SCREENSHOT_DIR` environment variable is set.
/// Never touches a device or saved data; sets up a few screens and saves its own window as PNG for the docs.
///
///   LS_SCREENSHOT_DIR=out LS_LANG=en LocationSpoofer.app/Contents/MacOS/LocationSpoofer
@MainActor
enum ScreenshotRunner {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["LS_SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(model: AppModel, dir: URL) async {
        let lang = ProcessInfo.processInfo.environment["LS_LANG"] ?? "en"
        let only = ProcessInfo.processInfo.environment["LS_ONLY"]      // e.g. 4-about; when unset, capture everything
        func want(_ n: String) -> Bool { only == nil || only == n }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Demo state: never touch a real device or user data
        model.demo = true
        model.language.persistsChanges = false
        model.language.selection = AppLanguage(rawValue: lang) ?? .en
        model.devices = [Device(id: "DEMO", name: "iPhone", osVersion: "27.3", isWireless: true, isConnected: true)]
        model.selectedDeviceID = "DEMO"
        model.scheduler.flights = demoFlights(enabled: false)

        guard let window = await waitForWindow() else { print("找不到視窗"); NSApp.terminate(nil); return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(3))

        // 1. Teleport
        if want("1-teleport") {
        model.controller.mode = .teleport
        model.reveal(Coordinate(latitude: 25.033964, longitude: 121.564468), zoom: 1600)
        model.apply()
        await shoot(window, dir, lang, "1-teleport", wait: 6)
        }

        // 2. Route (along roads, running)
        if want("2-route") {
        model.controller.stop()
        model.controller.mode = .route
        model.controller.transport = .car
        model.controller.timeScale = 1
        model.controller.waypoints = [
            Coordinate(latitude: 25.0330, longitude: 121.5354), Coordinate(latitude: 25.0339, longitude: 121.5430),
            Coordinate(latitude: 25.0290, longitude: 121.5440), Coordinate(latitude: 25.0268, longitude: 121.5370),
        ]
        model.camera = .camera(MapCamera(centerCoordinate: .init(latitude: 25.0305, longitude: 121.5395), distance: 3200))
        model.startMovement()
        await shoot(window, dir, lang, "2-route", wait: 12)
        }

        // 3. Scheduled flights + flight (the first flight is already airborne)
        if want("3-flight") {
        model.controller.stop()
        model.controller.timeScale = 1
        model.scheduler.flights = demoFlights(enabled: true)
        try? await Task.sleep(for: .seconds(4))
        model.fitFlight()
        await shoot(window, dir, lang, "3-flight", wait: 8)
        }

        // 4. About window
        AboutPanel.show()
        try? await Task.sleep(for: .seconds(2))
        if let about = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) && $0.frame.width < 700 }) {
            await shoot(about, dir, lang, "4-about", wait: 1, resize: false)
        }

        print("截圖完成:\(dir.path)")
        NSApp.terminate(nil)
    }

    /// Flight 1 "departed 40 min ago" (airborne), flight 2 departs in 2 h with a 20 min delay, flight 3 is disabled.
    static func demoFlights(enabled: Bool) -> [ScheduledFlight] {
        let cal = Calendar.current
        let now = Date()
        func make(_ no: String, _ o: String, _ d: String, offsetMin: Int, dur: Int, delay: Int, on: Bool) -> ScheduledFlight {
            let t = now.addingTimeInterval(Double(offsetMin) * 60)
            var f = ScheduledFlight(flightNumber: no, origin: o, destination: d)
            f.hour = cal.component(.hour, from: t); f.minute = cal.component(.minute, from: t)
            f.weekdays = Set(1...7); f.durationMinutes = dur; f.delayMinutes = delay; f.enabled = on
            return f
        }
        return [
            make("LS 101", "TPE", "NRT", offsetMin: -40, dur: 190, delay: 0, on: enabled),
            make("LS 202", "TPE", "LAX", offsetMin: 120, dur: 700, delay: 20, on: enabled),
            make("LS 303", "TPE", "SIN", offsetMin: 600, dur: 270, delay: 0, on: false),
        ]
    }

    private static func waitForWindow() async -> NSWindow? {
        for _ in 0..<50 {
            if let w = NSApp.windows.first(where: { $0.title == "Location Spoofer" && $0.isVisible }) { return w }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    private static func shoot(_ window: NSWindow, _ dir: URL, _ lang: String, _ name: String, wait: Double, resize: Bool = true) async {
        try? await Task.sleep(for: .seconds(wait))
        // Fix the window size so every screenshot has the same dimensions
        if resize {
            window.setContentSize(NSSize(width: 1440, height: 900))
            try? await Task.sleep(for: .seconds(1))
        }

        // Capture the composited window (glass material and map included), own window only. Retry because the first run may need permission.
        for attempt in 1...4 {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                    print("找不到可擷取的視窗:\(name)"); return
                }
                let cfg = SCStreamConfiguration()
                cfg.width = Int(target.frame.width * 2)
                cfg.height = Int(target.frame.height * 2)
                cfg.showsCursor = false
                let cg = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: cfg)
                if let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(lang)-\(name).png"))
                    print("已存:\(lang)-\(name).png \(cg.width)x\(cg.height)")
                }
                return
            } catch {
                print("擷取失敗 \(name)(第 \(attempt) 次):\(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
