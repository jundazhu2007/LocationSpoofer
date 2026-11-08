import SwiftUI

private enum TimeFmt {
    private static var locale: Locale { Locale(identifier: Localizer.shared.code) }
    static var hm: DateFormatter { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }
    static var date: DateFormatter { let f = DateFormatter(); f.locale = locale; f.dateFormat = "M/d (E)"; return f }
    /// 星期名稱(Calendar weekday 1 = 週日)。中文 / 日文用單字,英文用縮寫。
    static func weekdayName(_ weekday: Int) -> String {
        let f = DateFormatter(); f.locale = locale
        let symbols = Localizer.shared.code == "en" ? f.shortWeekdaySymbols : f.veryShortWeekdaySymbols
        return symbols?[weekday - 1] ?? "\(weekday)"
    }
}

struct ScheduleView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ScheduledFlight?

    var body: some View {
        @Bindable var sch = model.scheduler
        @Bindable var power = model.power
        List {
            Section("固定航班") {
                if sch.flights.isEmpty {
                    Text("尚無航班。新增後,到點會自動登機、起飛;誤點可隨時修改並立即套用。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach($sch.flights) { $f in
                    FlightRow(flight: $f, onEdit: { editing = f }, onDelete: { sch.flights.removeAll { $0.id == f.id } })
                }
                Button("新增航班", systemImage: "plus.circle") {
                    var f = ScheduledFlight(); f.oneOffDate = .now
                    editing = f
                }
            }

            Section("無人看守運作") {
                Toggle("防止閒置睡眠", isOn: $power.preventSleep)
                Toggle("開機自動啟動", isOn: Binding(get: { power.launchAtLogin }, set: { power.setLaunchAtLogin($0) }))
                Toggle("闔上螢幕也不睡眠", isOn: Binding(get: { power.sleepDisabled }, set: { v in Task { await power.setSleepDisabled(v) } }))
                Button("為下一班預約喚醒 Mac", systemImage: "alarm") {
                    if let d = sch.nextWakeDate() { power.scheduleWake(at: d) }
                }.disabled(sch.nextWakeDate() == nil)
                if !power.message.isEmpty { Text(power.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("位置是由 Mac 一路送給 iPhone,所以 Mac 必須:開機、不睡眠、與 iPhone 在同一個網路。")
                    Text("「闔上螢幕也不睡眠」「預約喚醒」會修改系統電源設定,需要管理員密碼;不再使用時請關閉。")
                    Text("時間皆為 Mac 的本地時區。")
                }
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editing) { f in FlightEditor(draft: f).environment(model) }
        .task { await model.power.refreshSleepDisabled() }
    }
}

struct FlightRow: View {
    @Environment(AppModel.self) private var model
    @Binding var flight: ScheduledFlight
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let st = model.scheduler.status(of: flight)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(flight.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                    Toggle("啟用", isOn: $flight.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Text(scheduleText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Group {
                    if flight.enabled { statusLine(st, now: ctx.date) }
                    else { Label("已停用", systemImage: "pause.circle").foregroundStyle(.secondary) }
                }
                .font(.callout).fixedSize(horizontal: false, vertical: true)
                Stepper(flight.delayMinutes == 0 ? L("準點") : L("誤點 %lld 分(即時套用)", flight.delayMinutes),
                        value: $flight.delayMinutes, in: 0...1440, step: 5).font(.callout)
                HStack {
                    Button("編輯", systemImage: "pencil", action: onEdit)
                    Button("刪除", systemImage: "trash", role: .destructive, action: onDelete)
                }.controlSize(.small)
            }
            .padding(.vertical, 4)
            .opacity(flight.enabled ? 1 : 0.5)
        }
    }

    private var scheduleText: String {
        let days: String
        if flight.weekdays.isEmpty { days = flight.oneOffDate.map { TimeFmt.date.string(from: $0) } ?? L("單次") }
        else {
            let sep = Localizer.shared.code == "en" ? ", " : ""
            days = L("每週 %@", [2, 3, 4, 5, 6, 7, 1].filter(flight.weekdays.contains).map { TimeFmt.weekdayName($0) }.joined(separator: sep))
        }
        return L("%@ %02lld:%02lld 起飛 · 表定 %@", days, flight.hour, flight.minute, Format.duration(Double(flight.durationMinutes) * 60))
    }

    @ViewBuilder private func statusLine(_ st: FlightScheduler.Status, now: Date) -> some View {
        switch st.phase {
        case .none: Label("無後續班次", systemImage: "moon.zzz").foregroundStyle(.secondary)
        case .waiting:
            if let dep = st.departure, let sch = st.scheduled {
                let delayed = flight.delayMinutes != 0
                Label(L("等待起飛 · 倒數 %@", Format.duration(dep.timeIntervalSince(now))) +
                      (delayed ? L("(表定 %@ → 實際 %@)", TimeFmt.hm.string(from: sch), TimeFmt.hm.string(from: dep)) : ""), systemImage: "clock")
            }
        case .boarding:
            if let dep = st.departure { Label(L("登機中 · %@ 後起飛", Format.duration(dep.timeIntervalSince(now))), systemImage: "figure.walk.arrival").foregroundStyle(.orange) }
        case .airborne:
            if let arr = st.arrival {
                Label(L("飛行中 · 剩 %@ · 預計 %@ 落地", Format.duration(arr.timeIntervalSince(now)), TimeFmt.hm.string(from: arr)), systemImage: "airplane").foregroundStyle(.green)
            }
        }
    }
}

struct FlightEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: ScheduledFlight
    @State private var origin: Airport?
    @State private var dest: Airport?
    @State private var loaded = false

    private let weekdayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let exists = model.scheduler.flights.contains { $0.id == draft.id }
        VStack(spacing: 0) {
            Text(exists ? L("編輯航班") : L("新增航班")).font(.title3.bold()).padding()
            Form {
                TextField("航班號(選填)", text: $draft.flightNumber)
                AirportPicker(title: L("出發機場"), selection: $origin, origin: nil, directOnly: false)
                AirportPicker(title: L("抵達機場"), selection: $dest, origin: origin, directOnly: false)

                Section("起飛時間") {
                    DatePicker("時間", selection: timeBinding, displayedComponents: .hourAndMinute)
                    HStack(spacing: 4) {
                        ForEach(weekdayOrder, id: \.self) { wd in
                            Toggle(TimeFmt.weekdayName(wd), isOn: Binding(get: { draft.weekdays.contains(wd) },
                                                       set: { if $0 { draft.weekdays.insert(wd) } else { draft.weekdays.remove(wd) } }))
                                .toggleStyle(.button)
                        }
                    }
                    if draft.weekdays.isEmpty {
                        DatePicker("日期(單次)", selection: Binding(get: { draft.oneOffDate ?? .now }, set: { draft.oneOffDate = $0 }), displayedComponents: .date)
                    } else { Text("每週重複;全部取消則為單次航班").font(.caption).foregroundStyle(.secondary) }
                }

                Section("飛行時間") {
                    Stepper(L("表定 %@", Format.duration(Double(draft.durationMinutes) * 60)), value: $draft.durationMinutes, in: 10...1500, step: 5)
                    if let o = origin, let d = dest {
                        let dist = o.coordinate.distance(to: d.coordinate)
                        let r = FlightProfile.solveCruise(total: dist, seconds: Double(draft.durationMinutes) * 60)
                        Button("依距離估算(巡航 850 km/h)") {
                            draft.durationMinutes = max(10, Int((FlightProfile.duration(total: dist, cruise: 850) / 60 / 5).rounded()) * 5)
                        }.controlSize(.small)
                        if r.feasible { Text(L("航程 %@,需平均巡航約 %lld km/h", Format.distance(dist), Int(r.cruise))).font(.caption).foregroundStyle(.secondary) }
                        else { Text(L("航程 %@:時間太短,飛不到", Format.distance(dist))).font(.caption).foregroundStyle(.red) }
                    }
                }

                Section("其他") {
                    Stepper(L("誤點 %lld 分", draft.delayMinutes), value: $draft.delayMinutes, in: 0...1440, step: 5)
                    Stepper(L("起飛前 %lld 分先傳送到出發機場", draft.boardingLeadMinutes), value: $draft.boardingLeadMinutes, in: 0...180, step: 5)
                    Stepper(draft.restoreAfterLandingMinutes == 0 ? L("落地後保留在目的地") : L("落地後 %lld 分還原定位", draft.restoreAfterLandingMinutes),
                            value: $draft.restoreAfterLandingMinutes, in: 0...720, step: 5)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("儲存") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(origin == nil || dest == nil || origin?.iata == dest?.iata)
            }.padding()
        }
        .frame(width: 440, height: 640)
        .onAppear {
            guard !loaded else { return }; loaded = true
            origin = model.airports.airport(draft.origin); dest = model.airports.airport(draft.destination)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: .now) ?? .now },
                set: { draft.hour = Calendar.current.component(.hour, from: $0); draft.minute = Calendar.current.component(.minute, from: $0) })
    }

    private func save() {
        guard let o = origin, let d = dest else { return }
        draft.origin = o.iata; draft.destination = d.iata
        if draft.weekdays.isEmpty && draft.oneOffDate == nil { draft.oneOffDate = .now }
        if let i = model.scheduler.flights.firstIndex(where: { $0.id == draft.id }) { model.scheduler.flights[i] = draft }
        else { model.scheduler.flights.append(draft) }
        dismiss()
    }
}
