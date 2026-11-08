import Foundation

struct DeviceService: Sendable {
    func list() async -> [Device] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ls-dev-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let r = await DeviceCtl.run(["list", "devices", "--json-output", file.path], timeout: .seconds(15))
        guard r.status == 0, let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        return devices.compactMap { d in
            guard let hw = d["hardwareProperties"] as? [String: Any],
                  let dp = d["deviceProperties"] as? [String: Any],
                  let cp = d["connectionProperties"] as? [String: Any],
                  hw["reality"] as? String == "physical", hw["platform"] as? String == "iOS",
                  let state = cp["tunnelState"] as? String, state != "unavailable",
                  let udid = hw["udid"] as? String else { return nil }
            return Device(id: udid, name: dp["name"] as? String ?? "iPhone",
                          osVersion: dp["osVersionNumber"] as? String ?? "?",
                          isWireless: cp["transportType"] as? String == "localNetwork",
                          isConnected: state == "connected")
        }
    }

    func setLocation(_ c: Coordinate, udid: String) async -> CommandResult {
        await DeviceCtl.run(["device", "simulate", "location", "coordinate", "--device", udid,
                             "--latitude", String(c.latitude), "--longitude", String(c.longitude)])
    }

    func clearLocation(udid: String) async -> CommandResult {
        await DeviceCtl.run(["device", "simulate", "location", "clear", "--device", udid])
    }

    func runScenario(_ name: String, udid: String) async -> CommandResult {
        await DeviceCtl.run(["device", "simulate", "location", "scenario", "--device", udid, name], timeout: .seconds(60))
    }
}

/// 序列化送出座標:慢的指令不會堆積,每台裝置永遠只送「最新」那一個;多台裝置並行。
actor LocationSender {
    private var pending: [String: Coordinate] = [:]
    private var draining = false
    private let service = DeviceService()
    private var onResult: (@Sendable (Bool, String) -> Void)?

    func setHandler(_ h: @escaping @Sendable (Bool, String) -> Void) { onResult = h }

    func submit(_ c: Coordinate, udids: [String]) {
        for u in udids { pending[u] = c }
        guard !draining else { return }
        draining = true
        Task { await drain() }
    }

    func cancelPending() { pending.removeAll() }

    func waitIdle() async { while draining { try? await Task.sleep(for: .milliseconds(100)) } }

    private func drain() async {
        while !pending.isEmpty {
            let batch = pending
            pending.removeAll()
            let service = self.service
            let results = await withTaskGroup(of: CommandResult.self) { group in
                for (udid, c) in batch { group.addTask { await service.setLocation(c, udid: udid) } }
                var out: [CommandResult] = []
                for await r in group { out.append(r) }
                return out
            }
            var failed = false
            for r in results { onResult?(r.status == 0, r.output); if r.status != 0 { failed = true } }
            if failed { try? await Task.sleep(for: .seconds(1)) }
        }
        draining = false
    }
}
