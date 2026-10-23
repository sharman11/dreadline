import SwiftUI
import AppKit

/// The menu bar popover: what's next and what's later. Testing the haunting lives in Settings.
struct MainView: View {
    @ObservedObject var model: AppModel
    var openSettings: (String?) -> Void
    var closeMenu: () -> Void
    @State private var timingItem: Occurrence?
    @State private var deleting: LocalReminder?
    @State private var listHeight: CGFloat = 220
    private var editing: Bool { model.showEditor || timingItem != nil }
    static let width: CGFloat = 360
    /// The agenda grows with its content up to this height, then scrolls.
    static let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            if model.showEditor {
                LocalEditor(model: model, existing: model.editor).frame(height: 500)
            } else if let item = timingItem {
                TimingEditor(model: model, item: item, close: { timingItem = nil })
                    .frame(height: 420, alignment: .top)
            } else {
                header
                Divider().overlay(AppStyle.border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        banners
                        agenda
                    }
                    .padding(14)
                    .background(GeometryReader { Color.clear.preference(key: ListHeightKey.self, value: $0.size.height) })
                }
                .frame(height: min(max(listHeight, 120), Self.maxListHeight))
                .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
                footer
            }
        }
        .frame(width: Self.width)
        .background(AppStyle.canvas).haunted()
        .onExitCommand {
            if model.demoActive { model.endDemo() }
            else if model.showEditor { model.showEditor = false; model.editor = nil }
            else if timingItem != nil { timingItem = nil }
            else { closeMenu() }
        }
        .alert("Delete this reminder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { model.deleteSeries(deleting.id) }; deleting = nil }
        } message: { Text("The reminder and its future repeats will be removed.") }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusLive ? AppStyle.accent : AppStyle.muted).frame(width: 7, height: 7)
                .shadow(color: statusLive ? AppStyle.accent.opacity(0.6) : .clear, radius: 4)
            Text(statusText).font(.system(size: 12, weight: .medium)).foregroundStyle(AppStyle.muted)
            Spacer()
            IconButton(symbol: "plus", help: "New reminder") { model.editor = nil; model.showEditor = true }
                .keyboardShortcut("n", modifiers: .command)
        }.padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 8)
    }
    private var statusLive: Bool { model.preferences.alertsEnabled && !model.db.paused }
    private var statusText: String {
        if model.db.paused { return model.db.pauseUntil.map { "Paused until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Paused" }
        if !model.preferences.alertsEnabled { return "Alerts off" }
        let count = model.preferences.selectedCalendars.count
        return "Watching \(count) calendar\(count == 1 ? "" : "s")"
    }

    // MARK: Body

    @ViewBuilder private var banners: some View {
        if let error = model.error {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AppStyle.blood)
                Text(error).font(.callout).foregroundStyle(AppStyle.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { model.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(AppStyle.muted).accessibilityLabel("Dismiss error")
            }.padding(12).background(AppStyle.blood.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        if model.db.paused {
            banner("moon.zzz", "Hauntings are paused", action: "Resume") { model.resume() }
        } else if !model.preferences.alertsEnabled {
            banner("bell.slash", "Alerts are off", action: "Turn on") { var p = model.preferences; p.alertsEnabled = true; model.updatePreferences(p) }
        }
        if model.windowMinimizer.pendingRestorations > 0 {
            banner("macwindow.on.rectangle", "Some windows are still minimized", action: "Restore") { model.restoreWorkspace() }
        }
    }
    private func banner(_ symbol: String, _ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(AppStyle.accent)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(AppStyle.ink)
            Spacer()
            Button(action, action: perform).buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(AppStyle.accent)
        }.padding(.horizontal, 12).padding(.vertical, 10)
        .background(AppStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var agenda: some View {
        if let next = model.unresolved.first {
            NextUpCard(model: model, item: next, editTiming: { timingItem = next }, delete: { deleting = $0 })
            let later = Array(model.unresolved.dropFirst())
            if !later.isEmpty {
                Text("LATER").font(AppStyle.signal(10)).tracking(1.4).foregroundStyle(AppStyle.muted).padding(.top, 4).padding(.leading, 2)
                VStack(spacing: 0) {
                    ForEach(later) { item in
                        AgendaRow(model: model, item: item, editTiming: { timingItem = item }, delete: { deleting = $0 })
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                GhostGathering().frame(width: 64, height: 64)
                Text("Nothing coming up").font(AppStyle.display(18)).foregroundStyle(AppStyle.ink)
                Text("Your next meeting will show up here.").font(.callout).foregroundStyle(AppStyle.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppStyle.border)
            HStack(spacing: 4) {
                if model.db.paused {
                    Button { model.resume() } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(PillStyle(active: true)).help("Resume hauntings")
                } else {
                    Menu { PauseButtons(model: model) } label: {
                        Label("Pause", systemImage: "moon.zzz").font(.system(size: 12, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(AppStyle.accent)
                    .help("Pause hauntings, for example before you share your screen")
                }
                Spacer()
                IconButton(symbol: "gearshape", help: "Settings") { openSettings(nil) }
                    .keyboardShortcut(",", modifiers: .command)
                IconButton(symbol: "power", help: "Quit Dreadline") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .foregroundStyle(AppStyle.ink)
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A borderless square icon button that lights up on hover.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = AppStyle.ink
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(AppStyle.ink.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// A compact capsule button for the popover footer.
private struct PillStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).labelStyle(.titleAndIcon)
            .foregroundStyle(active ? AppStyle.midnight : AppStyle.accent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((active ? AppStyle.accent : AppStyle.accent.opacity(configuration.isPressed ? 0.2 : 0.12)), in: Capsule())
    }
}

/// "in 12 min", "in 1 h 5 min", "now", "started 3 min ago".
func countdown(to due: Date, from now: Date) -> String {
    let minutes = Int((due.timeIntervalSince(now) / 60).rounded(.up))
    if minutes <= 0 { return minutes > -1 ? "now" : "started \(-minutes) min ago" }
    if minutes < 60 { return "in \(minutes) min" }
    if minutes < 24 * 60 { return minutes % 60 == 0 ? "in \(minutes / 60) h" : "in \(minutes / 60) h \(minutes % 60) min" }
    return due.formatted(.dateTime.weekday(.wide))
}

/// Shared actions for an agenda item: snooze, dismiss, skip, timing, and editing local reminders.
private struct ItemMenu: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    var includeSnoozeAndDismiss = true
    var editTiming: () -> Void
    var delete: (LocalReminder) -> Void
    private var local: LocalReminder? { item.kind == .local ? model.db.locals.first { $0.id == item.seriesID } : nil }
    var body: some View {
        Menu {
            if includeSnoozeAndDismiss {
                Button(model.snoozeLabel(item)) { model.escape(item) }
                Button("Dismiss") { model.act(.acknowledge, item) }
            }
            Button("Skip this one") { model.act(.skip, item) }
            Button("Alert timing…", action: editTiming)
            if let local {
                Divider()
                Button("Edit reminder…") { model.editor = local; model.showEditor = true }
                Button("Delete reminder…", role: .destructive) { delete(local) }
            }
        } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppStyle.muted).frame(width: 24, height: 24).contentShape(Rectangle()) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(AppStyle.muted).help("More actions").accessibilityLabel("More actions")
    }
}

private struct NextUpCard: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    var editTiming: () -> Void
    var delete: (LocalReminder) -> Void
    private var canComplete: Bool { item.kind == .local || (item.kind == .reminders && item.writable && !item.recurring) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NEXT UP").font(AppStyle.signal(10)).tracking(1.4).foregroundStyle(AppStyle.muted)
                Spacer()
                if let due = item.due {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(countdown(to: due, from: context.date)).font(AppStyle.signal(11)).foregroundStyle(AppStyle.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(AppStyle.accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.preferences.privateTitles ? "Upcoming commitment" : item.title)
                    .font(AppStyle.display(19)).foregroundStyle(AppStyle.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let due = item.due {
                    Text(timeLine(due)).font(.caption).foregroundStyle(AppStyle.muted).lineLimit(1)
                }
            }
            if item.state == .snoozed, let until = item.snoozeUntil, until > Date() {
                Label("Snoozed until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz").font(.caption).foregroundStyle(AppStyle.accent)
            }
            HStack(spacing: 8) {
                JoinButton(model: model, item: item, compact: true)
                if canComplete {
                    Button("Done") { model.act(.done, item) }
                        .buttonStyle(item.links.isEmpty ? AnyButtonStyle(HauntedPrimaryStyle(compact: true)) : AnyButtonStyle(HauntedSecondaryStyle(compact: true)))
                }
                Button(model.snoozeLabel(item)) { model.escape(item) }.buttonStyle(HauntedSecondaryStyle(compact: true))
                Spacer(minLength: 0)
                ItemMenu(model: model, item: item, includeSnoozeAndDismiss: false, editTiming: editTiming, delete: delete)
            }
        }
        .padding(14)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppStyle.accent.opacity(0.25), lineWidth: 1))
    }
    private func timeLine(_ due: Date) -> String {
        var parts = [due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened)]
        if let end = item.end, end > due { parts[0] += " – " + end.formatted(date: .omitted, time: .shortened) }
        parts.append(model.preferences.privateTitles ? (item.kind == .calendar ? "Calendar" : "Reminder") : (item.kind == .local ? "Reminder" : item.sourceName))
        return parts.joined(separator: "  ·  ")
    }
}

private struct AgendaRow: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    var editTiming: () -> Void
    var delete: (LocalReminder) -> Void
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.due.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                if let due = item.due, !Calendar.current.isDateInToday(due) {
                    Text(due.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption2).foregroundStyle(AppStyle.muted)
                }
            }.frame(width: 64, alignment: .leading).foregroundStyle(AppStyle.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.preferences.privateTitles ? "Upcoming commitment" : item.title).font(.system(size: 13)).lineLimit(1).foregroundStyle(AppStyle.ink)
                Text(item.kind == .local ? "Reminder" : (model.preferences.privateTitles ? "Calendar" : item.sourceName))
                    .font(.caption).foregroundStyle(AppStyle.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = item.links.first, item.links.count == 1 {
                Button { model.join(link, item) } label: { Image(systemName: "video.fill").font(.system(size: 11)).foregroundStyle(AppStyle.accent).frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Join meeting").accessibilityLabel("Join meeting")
            }
            ItemMenu(model: model, item: item, editTiming: editTiming, delete: delete)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(AppStyle.ink.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }
}

/// Lets one call site pick between two concrete button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct JoinButton: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    var demo = false
    /// On the haunting itself, Join plays the vanish exit before the link opens.
    var fromOverlay = false
    var compact = false
    private func open(_ link: String) {
        if fromOverlay { model.joinFromOverlay(link, item) }
        else if demo { model.endDemo(animated: true) }
        else { model.join(link, item) }
    }
    var body: some View {
        if item.links.count == 1, let link = item.links.first {
            Button { open(link) } label: { Label(compact ? "Join" : "Join meeting", systemImage: "video.fill").lineLimit(1).fixedSize() }.buttonStyle(HauntedPrimaryStyle(compact: compact))
        } else if !item.links.isEmpty {
            Menu {
                ForEach(item.links, id: \.self) { link in Button(SafeLinks.validate(link)?.host ?? "Meeting link") { open(link) } }
            } label: { Label(compact ? "Join" : "Join meeting", systemImage: "video.fill") }.menuStyle(.borderlessButton).fixedSize()
        }
    }
}

struct PauseButtons: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Button("Pause for 1 hour") { model.pause(until: Date().addingTimeInterval(3600)) }
        Button("Pause for 15 minutes") { model.pause(until: Date().addingTimeInterval(900)) }
        Button("Until I resume") { model.pause(until: nil) }
        if model.db.paused { Button("Resume alerts") { model.resume() } }
    }
}
