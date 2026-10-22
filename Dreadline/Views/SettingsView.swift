import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft = Preferences()
    @State private var previewed = false
    @State private var resetPrompt = false
    @State private var pauseDate = Date().addingTimeInterval(3600)
    @State private var tab = "Behavior"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.largeTitle)
            Picker("Section", selection: $tab) { ForEach(["Behavior", "Sources", "Privacy & system", "Diagnostics"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            if model.demoActive { HStack { Text("Sandbox preview running — no source writes"); Spacer(); Button("End preview") { model.endDemo() } } }
            if tab == "Sources" { SourceSettings(model: model) }
            else if tab == "Diagnostics" { DiagnosticsView(model: model) }
            else {
                Form {
                    if tab == "Behavior" {
                        Section("Preview before enabling real delivery") {
                            HStack { ForEach(Intensity.allCases, id: \.self) { stage in Button("Preview \(stage.title)") { previewed = true; model.startDemo(stage) } } }
                            Toggle("Enable real alerts from selected sources and local reminders", isOn: $draft.alertsEnabled).disabled(!previewed && !model.preferences.alertsEnabled)
                            Picker("Intensity ceiling", selection: $draft.ceiling) { ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) } }
                            Toggle("Allow fullscreen stage", isOn: $draft.fullscreenEnabled).disabled(!previewed && !model.preferences.fullscreenEnabled)
                            Text("Overlays always allow Stop, Snooze, Skip, and Pause. Real overlays are nonactivating and redacted; full details stay in the main window.").font(.caption)
                        }
                        Section("Ordered lead times") { TimingControls(timing: $draft.timing) }
                        Section("Snooze and expiry") {
                            Stepper("Default snooze: \(draft.snoozeMinutes) min", value: $draft.snoozeMinutes, in: 1...120)
                            TextField("Event grace (seconds)", value: $draft.grace, format: .number)
                            TextField("Task escalation window (seconds)", value: $draft.taskWindow, format: .number)
                            Text("Events expire at the earlier of end or grace. Tasks remain pending after escalation stops.").font(.caption)
                        }
                        Section("Quiet hours — current local time zone") {
                            Toggle("Enable quiet hours", isOn: $draft.quiet.enabled)
                            MinuteControl(title: "Start", minute: $draft.quiet.startMinute)
                            MinuteControl(title: "End", minute: $draft.quiet.endMinute)
                            Text("Overnight ranges are supported. Equal start/end suppresses delivery all day. Quiet hours also suppress scheduled fallback alerts.").font(.caption)
                        }
                        Section("Presentation mode / pause") {
                            DatePicker("Pause until", selection: $pauseDate)
                            Button("Pause until chosen time") { model.pause(until: pauseDate) }.disabled(pauseDate <= Date())
                            HStack { Button("Pause indefinitely") { model.pause(until: nil) }; Button("Resume") { model.resume() } }
                        }
                    } else {
                        Section("Privacy and accessibility") {
                            Toggle("Hide titles in menu bar and app lists", isOn: $draft.privateTitles)
                            Toggle("Dim all attached displays at fullscreen", isOn: $draft.dimAllDisplays)
                            Toggle("Reduced motion", isOn: $draft.reducedMotion)
                            Text("Presentations use no animated effects. System accessibility and reduced transparency settings are respected by native controls.").font(.caption)
                            Toggle("Play a single alert sound", isOn: $draft.sound)
                            Slider(value: $draft.volume, in: 0...1) { Text("Sound volume") }
                            Stepper("History retention: \(draft.retentionDays) days", value: $draft.retentionDays, in: 1...365)
                        }
                        Section("System notifications — optional") {
                            Text("Permission: \(model.notificationStatus)")
                            Toggle("Fallback notifications", isOn: $draft.fallback).disabled(model.notificationStatus != "Authorized")
                            Button("Request notification permission") { model.requestNotifications() }
                            Text("Ordinary notifications may work while quit. They cannot show overlays, bypass Focus, or track source edits while this app is not running. At most 32 future notifications are scheduled.").font(.caption)
                        }
                        Section("Startup") {
                            Text(model.loginStatus)
                            HStack { Button("Enable launch at login") { model.setLogin(true) }; Button("Disable launch at login") { model.setLogin(false) }; Button("Refresh status") { model.updateLoginStatus() } }
                        }
                        Section("Local data") {
                            Text(model.databaseURL.path).font(.caption).textSelection(.enabled)
                            Button(model.storageFailed ? "Preserve failed database and recover…" : "Reset local data…", role: .destructive) { resetPrompt = true }
                        }
                    }
                }.formStyle(.grouped)
                HStack {
                    Button("Restore default settings") { draft = Preferences() }
                    Spacer()
                    Button("Save settings") { model.endDemo(); model.updatePreferences(draft) }.disabled(!draft.timing.valid || draft.grace <= 0 || draft.taskWindow <= 0)
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(20)
        .onAppear { draft = model.preferences }
        .onChange(of: model.preferences) { _, new in draft = new }
        .alert("Reset Dreadline's local data?", isPresented: $resetPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Reset local data", role: .destructive) { model.reset(); draft = model.preferences }
        } message: { Text("Cancel app timers and notifications, remove local reminders, history, selection, and preferences. Source calendars and Apple Reminders are untouched. Failed database files are preserved in a Recovery folder.") }
    }
}
struct MinuteControl: View {
    let title: String
    @Binding var minute: Int
    var body: some View {
        HStack {
            Text(title)
            Picker("Hour", selection: Binding(get: { minute / 60 }, set: { minute = $0 * 60 + minute % 60 })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 110)
            Picker("Minute", selection: Binding(get: { minute % 60 }, set: { minute = (minute / 60) * 60 + $0 })) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }.frame(width: 110)
        }
    }
}
struct SourceSettings: View {
    @ObservedObject var model: AppModel
    private func selection(_ source: SourceSnapshot) -> Binding<Bool> {
        Binding(get: { source.kind == .calendar ? model.preferences.selectedCalendars.contains(source.id) : model.preferences.selectedLists.contains(source.id) }, set: { value in
            var p = model.preferences
            if source.kind == .calendar { if value { p.selectedCalendars.insert(source.id) } else { p.selectedCalendars.remove(source.id) } }
            else { if value { p.selectedLists.insert(source.id) } else { p.selectedLists.remove(source.id) } }
            model.updatePreferences(p)
        })
    }
    var body: some View {
        Form {
            ForEach([SourceKind.calendar, .reminders], id: \.self) { kind in
                Section(kind == .calendar ? "Calendars — read only" : "Apple Reminders — completion requires Done") {
                    Text("Authorization: \(model.authorizationDescription(kind))").font(.caption)
                    Text(model.sourceStatus[kind] ?? "Unavailable").font(.caption).textSelection(.enabled)
                    Button(kind == .calendar ? "Connect calendars" : "Connect Apple Reminders") { model.connect(kind) }
                    ForEach(model.sources.filter { $0.kind == kind }, id: \.id) { source in
                        Toggle("\(source.provider) · \(source.name)\(source.writable ? "" : " (read only)")", isOn: selection(source))
                    }
                    if model.sources.filter({ $0.kind == kind }).isEmpty { Text("No available sources. Access denial does not affect local reminders.").foregroundStyle(.secondary) }
                }
            }
            Section("Calendar filtering") {
                prefToggle("Include all-day events", \.includeAllDay)
                MinuteControl(title: "All-day reminder time", minute: prefMinute(\.allDayMinute))
                MinuteControl(title: "Date-only task time", minute: prefMinute(\.dateOnlyMinute))
                prefToggle("Include free/available events", \.includeFree)
                prefToggle("Include unanswered invitations", \.includeUnanswered)
                prefToggle("Include tentative invitations", \.includeTentative)
            }
            Text("Calendars require full EventKit permission even for read-only access. Only calendars synced into macOS are available; Dreadline does not connect directly to Google, Exchange, or iCloud. Declined and cancelled events are excluded. No sources are selected automatically.").font(.caption)
            Button("Refresh sources") { Task { await model.refresh(catchUp: false) } }
        }.formStyle(.grouped)
    }
    func prefToggle(_ title: String, _ key: WritableKeyPath<Preferences, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.preferences[keyPath: key] }, set: { var p = model.preferences; p[keyPath: key] = $0; model.updatePreferences(p) }))
    }
    func prefMinute(_ key: WritableKeyPath<Preferences, Int>) -> Binding<Int> {
        Binding(get: { model.preferences[keyPath: key] }, set: { var p = model.preferences; p[keyPath: key] = $0; model.updatePreferences(p) })
    }
}
struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Delivery") {
                LabeledContent("Storage", value: model.storageFailed ? "Unavailable — recovery required" : "Ready")
                LabeledContent("Next deadline", value: model.nextAction?.formatted() ?? "None")
                LabeledContent("Pause", value: model.db.paused ? (model.db.pauseUntil?.formatted() ?? "Manual") : "Off")
                LabeledContent("Quiet hours now", value: model.preferences.quiet.contains(Date()) ? "Suppressing delivery" : "Off / outside range")
                LabeledContent("Alerts", value: model.preferences.alertsEnabled ? "Enabled" : "Disabled")
                LabeledContent("Selected source counts", value: "\(model.preferences.selectedCalendars.count) calendars · \(model.preferences.selectedLists.count) lists")
            }
            Section("Sources") {
                ForEach([SourceKind.calendar, .reminders], id: \.self) { kind in
                    Text("Authorization: \(model.authorizationDescription(kind))").font(.caption)
                    Text("\(kind.rawValue): \(model.sourceStatus[kind] ?? "unavailable")")
                    Text("Last success: \(model.lastRefresh[kind]?.formatted() ?? "Never this session")").font(.caption)
                }
            }
            Section("Redacted transition log (latest 30)") {
                ForEach(Array(model.db.logs.suffix(30).enumerated()), id: \.offset) { _, log in Text("\(log.date.formatted()) · \(log.category)").font(.caption).textSelection(.enabled) }
                Button("Export redacted diagnostics") { model.exportDiagnostics() }
            }
            Text("Public workspace lifecycle signals are used conservatively; session-active is not an unlock notification. Real overlays remain redacted and nonactivating. Delivery is unavailable while sleeping, shut down, quit, or permission/source validation is missing.").font(.caption)
        }.formStyle(.grouped)
    }
}
