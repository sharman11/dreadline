import SwiftUI
import AppKit

/// Settings in four short tabs. Permissions are not here: onboarding guarantees them,
/// and the app re-locks into onboarding if one is revoked.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// The demo video renders Settings without the test button.
    var showsTest = true
    @State private var resetPrompt = false
    @State private var diagnostics = false

    enum Tab: String, CaseIterable {
        case general = "General", calendars = "Calendars", haunting = "Haunting", advanced = "Advanced"
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .calendars: return "calendar"
            case .haunting: return "theatermasks"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }
    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: model.settingsTab) ?? .general }, set: { model.settingsTab = $0.rawValue })
    }

    /// A one-line description of each scare level.
    private var scareMeterCaption: String {
        switch model.preferences.scareLevel ?? .medium {
        case .low: return "A sharp shock when the meeting arrives. No screaming."
        case .medium: return "A full scream when the meeting arrives."
        case .high: return "Not for the faint of heart."
        }
    }
    private func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in
            var prefs = model.preferences; prefs[keyPath: key] = value; model.updatePreferences(prefs)
        })
    }
    private var fullHaunting: Bool { model.preferences.fullscreenEnabled && model.preferences.ceiling == .fullscreen }
    private var calendars: [SourceSnapshot] { model.sources.filter { $0.kind == .calendar } }
    private var lists: [SourceSnapshot] { model.sources.filter { $0.kind == .reminders } }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(AppStyle.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab.wrappedValue {
                    case .general: general
                    case .calendars: calendarsTab
                    case .haunting: haunting
                    case .advanced: advanced
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppStyle.canvas)
        .haunted()
        .onAppear { model.refreshPermissions() }
        .sheet(isPresented: $diagnostics) {
            VStack(spacing: 0) {
                HStack { Text("Diagnostics").font(AppStyle.display(22)); Spacer(); Button("Done") { diagnostics = false }.buttonStyle(HauntedSecondaryStyle(compact: true)) }.padding()
                DiagnosticsView(model: model)
            }.frame(width: 600, height: 520).haunted()
        }
        .alert("Reset Dreadline's local data?", isPresented: $resetPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Reset local data", role: .destructive) { model.reset() }
        } message: { Text("This removes local reminders, activity, and preferences. Your calendars and Apple Reminders stay untouched.") }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                let selected = tab.wrappedValue == item
                Button { tab.wrappedValue = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .regular)).frame(height: 20)
                        Text(item.rawValue).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selected ? AppStyle.accent : AppStyle.muted)
                    .frame(width: 84, height: 50)
                    .background(selected ? AppStyle.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34).padding(.bottom, 10)
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        SettingsCard("Startup") {
            SettingsRow("Open at login", detail: ["Enabled", "Not registered"].contains(model.loginStatus) ? "So no meeting slips past while Dreadline is closed." : model.loginStatus) {
                Toggle("", isOn: Binding(get: { model.loginStatus == "Enabled" }, set: { model.setLogin($0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            SettingsRow("Backup notifications", detail: "A plain notification if Dreadline is closed when a meeting starts.") { switchFor(\.fallback) }
        }
        SettingsCard("Quiet hours") {
            SettingsRow("Pause hauntings every day", detail: "Nothing haunts you between these times.") { switchFor(\.quiet.enabled) }
            if model.preferences.quiet.enabled {
                SettingsRow("From") { timePicker(\.quiet.startMinute) }
                SettingsRow("Until") { timePicker(\.quiet.endMinute) }
            }
        }
        SettingsCard("Privacy") {
            SettingsRow("Hide meeting titles", detail: "Show \u{201C}Upcoming commitment\u{201D} instead. Useful when sharing your screen.") { switchFor(\.privateTitles) }
            SettingsRow("Reduce motion", detail: "Calmer animations during a haunting.") { switchFor(\.reducedMotion) }
        }
    }

    // MARK: Calendars

    @ViewBuilder private var calendarsTab: some View {
        SettingsCard("Watched calendars") {
            if calendars.isEmpty {
                SettingsRow("No calendars found", detail: model.sourceStatus[.calendar]) { EmptyView() }
            }
            ForEach(calendars, id: \.id) { source in
                let on = model.preferences.selectedCalendars.contains(source.id)
                // At least one calendar must stay on, or there is nothing to haunt about.
                let last = on && model.preferences.selectedCalendars.count == 1
                SettingsRow(source.name, detail: source.provider) {
                    Toggle("", isOn: Binding(get: { on }, set: { model.setCalendar(source.id, selected: $0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).disabled(last)
                        .help(last ? "Keep at least one calendar on" : "")
                }
            }
        }
        SettingsCard("Include") {
            SettingsRow("All-day events") { switchFor(\.includeAllDay) }
            if model.preferences.includeAllDay {
                SettingsRow("Remind me about all-day events at") { timePicker(\.allDayMinute) }
            }
            SettingsRow("Events marked free") { switchFor(\.includeFree) }
            SettingsRow("Invitations I haven't answered") { switchFor(\.includeUnanswered) }
            SettingsRow("Tentative invitations") { switchFor(\.includeTentative) }
        }
        SettingsCard("Apple Reminders") {
            if !model.remindersAccessGranted {
                SettingsRow("Haunt me about reminders too", detail: "Reminders with a due date, from the lists you pick.") {
                    Button("Connect") { model.connect(.reminders) }.buttonStyle(HauntedSecondaryStyle(compact: true))
                }
            } else {
                if lists.isEmpty { SettingsRow("No reminder lists found") { EmptyView() } }
                ForEach(lists, id: \.id) { source in
                    SettingsRow(source.name, detail: source.provider) {
                        Toggle("", isOn: Binding(get: { model.preferences.selectedLists.contains(source.id) }, set: { value in
                            var p = model.preferences
                            if value { p.selectedLists.insert(source.id) } else { p.selectedLists.remove(source.id) }
                            model.updatePreferences(p)
                        })).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                }
                SettingsRow("Time for reminders without one") { timePicker(\.dateOnlyMinute) }
            }
        }
    }

    // MARK: Haunting

    @ViewBuilder private var haunting: some View {
        SettingsCard("Style") {
            SettingsRow("Haunting", detail: fullHaunting ? "The ghost clears your screen and takes over when the meeting starts." : "A reminder window appears at the side of your screen.") {
                Picker("Style", selection: Binding(get: { fullHaunting }, set: { full in
                    var p = model.preferences
                    p.fullscreenEnabled = full
                    p.ceiling = full ? .fullscreen : .prominent
                    p.poltergeistEnabled = full
                    if full { p.timing = Timing(gentle: p.timing.gentle > 0 ? p.timing.gentle : 300, prominent: 0, fullscreen: 0) }
                    model.updatePreferences(p)
                })) {
                    Text("Full screen").tag(true)
                    Text("Side window").tag(false)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if fullHaunting {
                SettingsRow("Early warning", detail: "When the ghost first shows up.") {
                    Picker("Early warning", selection: Binding(get: { Int((model.preferences.timing.gentle / 60).rounded()) }, set: { minutes in
                        var p = model.preferences; p.timing = Timing(gentle: Double(minutes * 60), prominent: 0, fullscreen: 0); model.updatePreferences(p)
                    })) {
                        Text("2 min").tag(2); Text("5 min").tag(5); Text("10 min").tag(10)
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            SettingsRow("Snooze for") {
                Stepper("\(model.preferences.snoozeMinutes) min", value: preference(\.snoozeMinutes), in: 1...60).monospacedDigit()
            }
        }
        SettingsCard("Sound") {
            SettingsRow("Sound effects") { switchFor(\.sound) }
            if model.preferences.sound {
                SettingsRow("Scare level", detail: scareMeterCaption) {
                    Picker("Scare level", selection: Binding(get: { model.preferences.scareLevel ?? .medium }, set: { level in
                        var p = model.preferences; p.scareLevel = level; model.updatePreferences(p)
                    })) {
                        ForEach(ScareLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                SettingsRow("Volume") {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").font(.caption).foregroundStyle(AppStyle.muted)
                        Slider(value: preference(\.volume), in: 0...1).frame(width: 150)
                        Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(AppStyle.muted)
                    }
                }
            }
        }
        if showsTest {
            SettingsCard("Try it") {
                SettingsRow("Test haunting", detail: model.demoActive ? "Press Esc to stop." : "Plays a sample haunting with these settings. Nothing is joined or changed.") {
                    if model.demoActive {
                        Button("Stop") { model.endDemo() }.buttonStyle(HauntedSecondaryStyle(compact: true))
                    } else {
                        Button { model.testHaunting() } label: { Label("Play", systemImage: "play.fill") }
                            .buttonStyle(HauntedPrimaryStyle(compact: true))
                    }
                }
            }
        }
    }

    // MARK: Advanced

    @ViewBuilder private var advanced: some View {
        SettingsCard("Permissions") {
            permissionRow("Calendar", granted: model.calendarAccessGranted)
            permissionRow("Window control", granted: model.accessibilityTrusted)
            permissionRow("Notifications", granted: model.notificationsGranted)
        }
        if model.preferences.poltergeistEnabled != true {
            SettingsCard("Displays") {
                SettingsRow("Dim other displays", detail: "Darken every screen during a reminder, not just the main one.") { switchFor(\.dimAllDisplays) }
            }
        }
        SettingsCard("Data") {
            SettingsRow("Keep history for") {
                Stepper("\(model.preferences.retentionDays) days", value: preference(\.retentionDays), in: 1...365).monospacedDigit()
            }
            SettingsRow("Diagnostics", detail: "A redacted log for troubleshooting.") {
                Button("Open…") { diagnostics = true }.buttonStyle(HauntedSecondaryStyle(compact: true))
            }
            SettingsRow("Reset local data", detail: "Removes reminders, activity and preferences.") {
                Button("Reset…", role: .destructive) { resetPrompt = true }
                    .buttonStyle(HauntedSecondaryStyle(compact: true)).foregroundStyle(AppStyle.blood)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.error { Text(error).font(.caption).foregroundStyle(AppStyle.blood).textSelection(.enabled) }
            Text("Changes save automatically · Everything stays on your Mac").font(.caption).foregroundStyle(AppStyle.muted)
        }.padding(.leading, 2)
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        SettingsRow(title) {
            Label(granted ? "Allowed" : "Needed", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption.weight(.medium)).foregroundStyle(granted ? AppStyle.accent : AppStyle.blood)
        }
    }

    // MARK: Controls

    private func switchFor(_ key: WritableKeyPath<Preferences, Bool>) -> some View {
        Toggle("", isOn: preference(key)).toggleStyle(.switch).labelsHidden().controlSize(.small)
    }
    /// A time-of-day picker backed by minutes since midnight.
    private func timePicker(_ key: WritableKeyPath<Preferences, Int>) -> some View {
        DatePicker("", selection: Binding(get: {
            let minutes = model.preferences[keyPath: key]
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            var p = model.preferences; p[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0); model.updatePreferences(p)
        }), displayedComponents: .hourAndMinute).datePickerStyle(.field).labelsHidden()
    }
}

// MARK: - Building blocks

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(AppStyle.signal(10)).tracking(1.4).foregroundStyle(AppStyle.muted).padding(.leading, 2)
            // Rows draw a hairline on top; shifting up one point hides the first one under the clip.
            VStack(spacing: 0) { content }
                .padding(.top, -1)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppStyle.border, lineWidth: 1))
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var trailing: Trailing
    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(AppStyle.ink)
                if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(AppStyle.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { AppStyle.border.frame(height: 1) }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Delivery") {
                LabeledContent("Window control", value: model.windowControlStatus)
                LabeledContent("Overlay", value: model.overlayStatus)
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
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(AppStyle.canvas)
    }
}
