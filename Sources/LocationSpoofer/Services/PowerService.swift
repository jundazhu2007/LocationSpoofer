import Foundation
import ServiceManagement

/// 讓排程在無人看守時也能運作:防睡眠、開機自動啟動、預約喚醒。
@MainActor @Observable
final class PowerService {
    var preventSleep: Bool = UserDefaults.standard.object(forKey: "preventSleep") as? Bool ?? true {
        didSet { UserDefaults.standard.set(preventSleep, forKey: "preventSleep"); update() }
    }
    var wantsActive = false { didSet { update() } }
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var sleepDisabled = false
    var message = ""

    private var activity: NSObjectProtocol?

    /// 有啟用的航班時,保持 app 活躍(避免 App Nap 讓計時器變慢),並依設定阻止閒置睡眠。
    func update() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        guard wantsActive else { return }
        let opts: ProcessInfo.ActivityOptions = preventSleep ? .userInitiated : .userInitiatedAllowingIdleSystemSleep
        activity = ProcessInfo.processInfo.beginActivity(options: opts, reason: L("預約飛行排程"))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; message = "" }
        catch { message = L("開機啟動設定失敗:%@", error.localizedDescription) }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on && SMAppService.mainApp.status == .requiresApproval { message = L("請到「系統設定 → 一般 → 登入項目」允許 LocationSpoofer") }
    }

    func refreshSleepDisabled() async {
        let r = await Self.shell("/usr/bin/pmset -g")
        sleepDisabled = r.contains(/SleepDisabled\s+1/)
    }

    /// 需要管理員密碼。合上螢幕(闔蓋)也不睡眠。
    func setSleepDisabled(_ on: Bool) async {
        do { try Self.admin("/usr/bin/pmset -a disablesleep \(on ? 1 : 0)"); message = "" }
        catch { message = L("設定失敗:%@", error.localizedDescription) }
        await refreshSleepDisabled()
    }

    func scheduleWake(at date: Date) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MM/dd/yyyy HH:mm:ss"
        do { try Self.admin("/usr/bin/pmset schedule wake \"\(f.string(from: date))\""); message = L("已預約喚醒:%@", f.string(from: date)) }
        catch { message = L("預約喚醒失敗:%@", error.localizedDescription) }
    }

    private static func admin(_ cmd: String) throws {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(esc)\" with administrator privileges")?.executeAndReturnError(&err)
        if let err { throw NSError(domain: "Power", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(err[NSAppleScript.errorMessage] ?? err)"]) }
    }

    private static func shell(_ cmd: String) async -> String {
        await withCheckedContinuation { cont in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-c", cmd]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            p.terminationHandler = { _ in cont.resume(returning: String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
            do { try p.run() } catch { cont.resume(returning: "") }
        }
    }
}
