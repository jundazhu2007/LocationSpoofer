import Foundation

struct CommandResult: Sendable { let status: Int32; let output: String }

/// 執行 `xcrun devicectl ...`(Xcode 內建,走 CoreDevice,支援 USB 與無線)。
enum DeviceCtl {
    static func run(_ args: [String], timeout: Duration = .seconds(30)) async -> CommandResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["devicectl"] + args
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: .init(status: proc.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
            do { try p.run() } catch { cont.resume(returning: .init(status: -1, output: error.localizedDescription)); return }
            let box = Box(p)
            Task { try? await Task.sleep(for: timeout); if box.p.isRunning { box.p.terminate() } }
        }
    }
    private final class Box: @unchecked Sendable { let p: Process; init(_ p: Process) { self.p = p } }

    /// 同步版本,僅供結束 app 時還原定位使用。
    static func runSync(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["devicectl"] + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
