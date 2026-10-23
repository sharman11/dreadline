import SwiftUI
import Combine

/// First-run setup. Dreadline stays locked until every required step is done:
/// calendar access, at least one calendar, window control (Accessibility), and notifications.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onFinish: () -> Void
    /// Accessibility and notification settings have no change notification, so they are re-read while this window is open.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Step: Int, CaseIterable { case calendar, choose, windows, notifications }

    private var calendars: [SourceSnapshot] { model.sources.filter { $0.kind == .calendar } }
    private func done(_ step: Step) -> Bool {
        switch step {
        case .calendar: return model.calendarAccessGranted
        case .choose: return !model.preferences.selectedCalendars.isEmpty
        case .windows: return model.accessibilityTrusted
        case .notifications: return model.notificationsGranted
        }
    }
    private var doneCount: Int { Step.allCases.filter(done).count }
    /// The first unfinished step gets the highlight.
    private var current: Step? { Step.allCases.first { !done($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    step(.calendar, title: "Calendar access",
                         detail: "Dreadline reads your meetings so it knows when to haunt. It never changes them.") {
                        Button(model.calendarAccessUndetermined ? "Allow" : "Open Settings") { model.requestCalendarAccess() }
                    }
                    step(.choose, title: "Choose calendars",
                         detail: "Pick the calendars with meetings you can't miss.", available: model.calendarAccessGranted) {
                        EmptyView()
                    } extra: {
                        if model.calendarAccessGranted { calendarList }
                    }
                    step(.windows, title: "Window control",
                         detail: "Lets the ghost clear your screen during a haunting, then put every window back. Turn on Dreadline under Privacy & Security → Accessibility.") {
                        Button("Open Settings") { model.openAccessibilitySettings() }
                    }
                    step(.notifications, title: "Notifications",
                         detail: "A backup alert when Dreadline can't show the haunting itself.") {
                        Button(model.notificationStatus == "Denied" ? "Open Settings" : "Allow") { model.requestNotifications() }
                    }
                }.padding(.horizontal, 28).padding(.vertical, 4)
            }
            footer
        }
        .frame(width: 520, height: 640)
        .background(AppStyle.canvas)
        .haunted()
        .onAppear { model.refreshPermissions() }
        .onReceive(poll) { _ in model.refreshPermissions() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                StandingGhost().frame(width: 44, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Dreadline").font(AppStyle.display(26)).foregroundStyle(AppStyle.ink)
                    Text("Grant these and the haunting can begin.").font(.callout).foregroundStyle(AppStyle.muted)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppStyle.border)
                        Capsule().fill(AppStyle.accent).frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(Step.allCases.count))
                    }
                }.frame(height: 4).animation(.easeOut(duration: 0.25), value: doneCount)
                Text("\(doneCount) OF \(Step.allCases.count) DONE").font(AppStyle.signal(10)).tracking(1.2).foregroundStyle(AppStyle.muted)
            }
        }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 18)
    }

    private func step<Action: View, Extra: View>(_ step: Step, title: String, detail: String, available: Bool = true,
                                                 @ViewBuilder action: () -> Action, @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        let isDone = done(step), isCurrent = current == step
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(isDone ? AppStyle.accent : .clear).frame(width: 24, height: 24)
                    Circle().stroke(isDone || isCurrent ? AppStyle.accent : AppStyle.border, lineWidth: 1.5).frame(width: 24, height: 24)
                    if isDone { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(AppStyle.midnight) }
                    else { Text("\(step.rawValue + 1)").font(AppStyle.signal(11)).foregroundStyle(isCurrent ? AppStyle.accent : AppStyle.muted) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppStyle.ink)
                    if !isDone { Text(detail).font(.callout).foregroundStyle(AppStyle.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                if !isDone && available {
                    action().buttonStyle(isCurrent ? AnyButtonStyle(HauntedPrimaryStyle()) : AnyButtonStyle(HauntedSecondaryStyle()))
                }
            }
            extra()
        }
        .padding(14)
        .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isCurrent ? AppStyle.accent.opacity(0.5) : AppStyle.border, lineWidth: 1))
        .opacity(isDone || isCurrent || available ? 1 : 0.5)
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if calendars.isEmpty {
                Text(model.refreshing ? "Loading your calendars…" : "No calendars found. Add an account in System Settings → Internet Accounts.")
                    .font(.callout).foregroundStyle(AppStyle.muted).padding(12)
            }
            ForEach(calendars, id: \.id) { source in
                Toggle(isOn: Binding(get: { model.preferences.selectedCalendars.contains(source.id) },
                                     set: { model.setCalendar(source.id, selected: $0) })) {
                    HStack {
                        Text(source.name).foregroundStyle(AppStyle.ink)
                        Spacer()
                        Text(source.provider).font(.caption).foregroundStyle(AppStyle.muted)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 12).padding(.vertical, 7)
                if source.id != calendars.last?.id { Divider().overlay(AppStyle.border) }
            }
        }
        .background(AppStyle.canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppStyle.border, lineWidth: 1))
        .padding(.leading, 38)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(AppStyle.border)
            HStack {
                Toggle("Open at login", isOn: Binding(get: { model.loginStatus == "Enabled" }, set: { model.setLogin($0) }))
                    .toggleStyle(.checkbox).foregroundStyle(AppStyle.muted)
                Spacer()
                Button("Start Dreadline") { onFinish() }
                    .buttonStyle(HauntedPrimaryStyle())
                    .disabled(!model.requiredSetupDone)
                    .keyboardShortcut(.defaultAction)
                    .help(model.requiredSetupDone ? "" : "Finish every step first")
            }.padding(.horizontal, 28).padding(.vertical, 14)
        }
    }
}
