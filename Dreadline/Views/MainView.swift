import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var section = "Upcoming"
    @State private var search = ""
    @State private var source = "All"
    @State private var status = "All"
    @State private var deleting: LocalReminder?
    private var items: [Occurrence] {
        let base = section == "History" ? model.history : (section == "Pending" ? model.pending : model.upcoming)
        return base.filter { (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) && (source == "All" || $0.sourceName == source) && (status == "All" || $0.state.rawValue == status) }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Upcoming", systemImage: "calendar").tag("Upcoming")
                Label("Pending (\(model.pending.count))", systemImage: "bell.badge").tag("Pending")
                Label("History", systemImage: "clock.arrow.circlepath").tag("History")
                Label("Local reminders", systemImage: "checklist").tag("Local reminders")
                Label("Settings", systemImage: "gear").tag("Settings")
                Label("Diagnostics", systemImage: "stethoscope").tag("Diagnostics")
            }.navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            if section == "Settings" { SettingsView(model: model) }
            else if section == "Diagnostics" { DiagnosticsView(model: model) }
            else if section == "Local reminders" {
                VStack(alignment: .leading) {
                    Text("Local reminders").font(.largeTitle)
                    Text("Edit and delete apply to the whole series. History is retained; use Skip in Pending for a single occurrence.").foregroundStyle(.secondary)
                    List(model.db.locals) { local in
                        HStack {
                            VStack(alignment: .leading) { Text(local.title); Text("\(local.recurrence.frequency.rawValue) · \(local.due.formatted())").font(.caption) }
                            Spacer()
                            Button("Edit series") { model.editor = local; model.showEditor = true }
                            Button("Delete series", role: .destructive) { deleting = local }
                        }
                    }
                    Button("Create reminder") { model.editor = nil; model.showEditor = true }
                }.padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section).font(.largeTitle)
                    if !model.preferences.onboardingComplete { OnboardingView(model: model) { section = "Settings" } }
                    if model.db.paused {
                        HStack { Label("Alerts paused", systemImage: "pause.circle"); Text(model.db.pauseUntil?.formatted() ?? "Until manually resumed"); Spacer(); Button("Resume") { model.resume() } }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let error = model.error {
                        HStack { Text(error).foregroundStyle(.red).textSelection(.enabled); Button("Clear") { model.error = nil } }
                    }
                    HStack {
                        Picker("Source", selection: $source) { Text("All").tag("All"); ForEach(Array(Set(model.db.occurrences.map(\.sourceName))).sorted(), id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 280)
                        Picker("Status", selection: $status) { Text("All").tag("All"); ForEach(OccurrenceState.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.frame(maxWidth: 220)
                        if model.refreshing { ProgressView().controlSize(.small) }
                    }
                    if items.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No \(section.lowercased()) items" : "No matching items", systemImage: "calendar", description: Text(model.refreshing ? "Loading selected sources…" : "Create a local reminder or connect and select sources in Settings. Source errors appear below."))
                    } else {
                        List(items) { item in OccurrenceRow(model: model, item: item) }
                    }
                    ForEach([SourceKind.calendar, .reminders], id: \.self) { kind in Text("\(kind.rawValue.capitalized): \(model.sourceStatus[kind] ?? "Unavailable")").font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }.padding()
            }
        }
        .onExitCommand { if model.demoActive { model.endDemo() } }
        .onChange(of: model.requestedSection) { _, value in if let value { section = value; model.requestedSection = nil } }
        .searchable(text: $search, prompt: "Search commitments")
        .toolbar {
            Button { model.editor = nil; model.showEditor = true } label: { Label("Create local reminder", systemImage: "plus") }
            Button { Task { await model.refresh(catchUp: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            Menu { PauseButtons(model: model) } label: { Label("Pause", systemImage: "pause") }
        }
        .sheet(isPresented: $model.showEditor) { LocalEditor(model: model, existing: model.editor) }
        .alert("Delete entire local series?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete series", role: .destructive) { if let deleting { model.deleteSeries(deleting.id) }; deleting = nil }
        } message: { Text("This deletes the local definition and cancels unresolved occurrences. Source calendars and reminders are untouched.") }
        .onReceive(NotificationCenter.default.publisher(for: .showDreadline)) { _ in openWindow(id: "main") }
    }
}
struct OccurrenceRow: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    @State private var showOverride = false
    @State private var snoozeDate = Date().addingTimeInterval(600)
    @State private var customSnooze = false
    private var snoozeMinutes: Int { model.db.locals.first(where: { $0.id == item.seriesID })?.snoozeMinutes ?? model.preferences.snoozeMinutes }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.preferences.privateTitles ? "Commitment" : item.title).font(.headline).lineLimit(3).textSelection(.enabled)
                if item.changed { Image(systemName: "pencil.circle").help("Source details changed; previous acknowledgement is retained") }
                Spacer(); Text(item.state.rawValue).font(.caption)
            }
            Text("\(item.due?.formatted() ?? "No due date") · \(item.sourceName)").font(.subheadline).foregroundStyle(.secondary)
            if let snooze = item.snoozeUntil { Text("Snoozed until \(snooze.formatted())").font(.caption) }
            if !item.location.isEmpty && !model.preferences.privateTitles { Text(item.location).lineLimit(2) }
            Text("Policy: \((item.ceiling ?? model.preferences.ceiling).title) · gentle \(Int((item.timing ?? model.preferences.timing).gentle / 60))m before").font(.caption)
            if let outcome = item.outcome { Text(outcome).font(.caption).foregroundStyle(.secondary) }
            if !item.state.terminal {
                HStack {
                    if item.kind != .calendar {
                        Button("Done") { model.act(.done, item) }.disabled(item.kind == .reminders && (!item.writable || item.recurring)).help(item.recurring && item.kind == .reminders ? "Recurring source completion is unverified; use local acknowledgement." : "Complete this task")
                    }
                    Button("Acknowledge") { model.act(.acknowledge, item) }
                    Menu("Snooze") {
                        Button("\(snoozeMinutes) minutes") { model.act(.snooze(Date().addingTimeInterval(Double(snoozeMinutes * 60))), item) }
                        Button("15 minutes") { model.act(.snooze(Date().addingTimeInterval(900)), item) }
                        Button("Until…") { customSnooze = true }
                    }
                    Button("Skip occurrence") { model.act(.skip, item) }
                    Menu("Meeting links") {
                        ForEach(item.links, id: \.self) { link in
                            Button("Open \(SafeLinks.validate(link)?.host ?? "link")") { model.join(link, item) }
                            Button("Copy \(SafeLinks.validate(link)?.host ?? "link")") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string) }
                        }
                    }.disabled(item.links.isEmpty)
                    Button("Timing…") { showOverride = true }
                }.controlSize(.small)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
        .sheet(isPresented: $showOverride) { TimingEditor(model: model, item: item) }
        .popover(isPresented: $customSnooze) {
            VStack { DatePicker("Snooze until", selection: $snoozeDate); Button("Save snooze") { model.act(.snooze(snoozeDate), item); customSnooze = false }.disabled(snoozeDate <= Date()) }.padding()
        }
    }
}
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onContinue: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Persistent reminders, under your control").font(.headline)
            Text("Preview the gentle, prominent, and fullscreen stages. Escape stops the current queue. Local reminders work without permission; connecting a calendar requires full read access, then explicit source selection. Real alerts stay off until you enable them in Settings.")
            HStack {
                ForEach(Intensity.allCases, id: \.self) { stage in Button("Preview \(stage.title)") { model.startDemo(stage) } }
                Button("Continue to Settings") { var p = model.preferences; p.onboardingComplete = true; model.updatePreferences(p); onContinue() }
            }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
struct PauseButtons: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Button("15 minutes") { model.pause(until: Date().addingTimeInterval(900)) }
        Button("One hour") { model.pause(until: Date().addingTimeInterval(3600)) }
        Button("Until manually resumed") { model.pause(until: nil) }
        Button("Resume") { model.resume() }
    }
}
struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
    @State private var quitPrompt = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.db.paused ? "Dreadline · Paused" : "Dreadline").font(.headline)
            if model.db.paused { Text(model.db.pauseUntil?.formatted() ?? "Until manually resumed").font(.caption) }
            ForEach(Array(model.unresolved.prefix(5))) { item in
                Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: {
                    HStack { Text(model.preferences.privateTitles ? "Commitment" : item.title).lineLimit(1); Spacer(); if let due = item.due { Text(due, style: .relative).font(.caption) } }
                }.buttonStyle(.plain)
            }
            Text("\(model.pending.count) pending · \(model.upcoming.count) upcoming").font(.caption)
            Divider()
            Button("Open commitments") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Create local reminder") { openWindow(id: "main"); model.editor = nil; model.showEditor = true; NSApp.activate(ignoringOtherApps: true) }
            Menu("Pause alerts") { PauseButtons(model: model) }
            Button("Test reminder (isolated demo)") { model.startDemo() }
            Button("Settings & diagnostics") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
            Button("Diagnostics") { openWindow(id: "main"); model.requestedSection = "Diagnostics"; NSApp.activate(ignoringOtherApps: true) }
            Button("Quit") { if model.preferences.fallback { quitPrompt = true } else { model.quit(keepNotifications: false) } }
        }.padding().frame(width: 340)
        .alert("Quit Dreadline?", isPresented: $quitPrompt) {
            Button("Cancel scheduled notifications and quit") { model.quit(keepNotifications: false) }
            Button("Keep fallback notifications and quit") { model.quit(keepNotifications: true) }
            Button("Keep running", role: .cancel) {}
        } message: { Text("Custom overlays stop. Scheduled system notifications can remain, but may become stale if events change while Dreadline is quit.") }
    }
}
