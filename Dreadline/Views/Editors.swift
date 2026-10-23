import SwiftUI

struct LocalEditor: View {
    @ObservedObject var model: AppModel
    let existing: LocalReminder?
    var onSaved: () -> Void = {}
    @State private var local = LocalReminder(title: "", due: Date().addingTimeInterval(600))
    @State private var confirmSeries = false
    @FocusState private var titleFocused: Bool
    private var valid: Bool {
        !local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (local.recurrence.frequency != .weekdays || !local.recurrence.weekdays.isEmpty)
    }

    init(model: AppModel, existing: LocalReminder?, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.existing = existing
        self.onSaved = onSaved
        var draft = existing ?? LocalReminder(title: "", due: Date().addingTimeInterval(600))
        if existing == nil {
            let c = Calendar.current.dateComponents([.hour, .minute, .weekday, .day], from: draft.due)
            draft.recurrence.hour = c.hour ?? 9
            draft.recurrence.minute = c.minute ?? 0
            draft.recurrence.weekday = c.weekday ?? 2
            draft.recurrence.day = c.day ?? 1
        }
        _local = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel") { model.showEditor = false; model.editor = nil }.buttonStyle(.borderless)
                Spacer()
                Text(existing == nil ? "New reminder" : "Edit reminder").font(.headline)
                Spacer()
                Button(existing == nil ? "Create" : "Save") {
                    if existing != nil && ((existing?.recurrence.frequency ?? .none) != .none || local.recurrence.frequency != .none) { confirmSeries = true }
                    else { save() }
                }.buttonStyle(HauntedPrimaryStyle()).disabled(!valid).keyboardShortcut(.defaultAction)
            }.padding(18)
            Form {
                Section("Reminder") {
                    TextField("Title", text: $local.title).focused($titleFocused)
                    DatePicker("When", selection: $local.due)
                    Picker("Repeat", selection: $local.recurrence.frequency) {
                        Text("Never").tag(RepeatFrequency.none)
                        Text("Every day").tag(RepeatFrequency.daily)
                        Text("Selected weekdays").tag(RepeatFrequency.weekdays)
                        Text("Every week").tag(RepeatFrequency.weekly)
                        Text("Every month").tag(RepeatFrequency.monthly)
                    }
                    if local.recurrence.frequency == .weekdays {
                        HStack(spacing: 8) {
                            ForEach(1...7, id: \.self) { day in
                                Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { local.recurrence.weekdays.contains(day) }, set: { if $0 { local.recurrence.weekdays.insert(day) } else { local.recurrence.weekdays.remove(day) } })).toggleStyle(.button).font(.caption)
                            }
                        }
                    }
                    if local.recurrence.frequency == .weekly {
                        Picker("Repeat on", selection: $local.recurrence.weekday) { ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) } }
                    }
                    if local.recurrence.frequency == .monthly { Stepper("Day of month: \(local.recurrence.day)", value: $local.recurrence.day, in: 1...31) }
                    if local.recurrence.frequency != .none {
                        Text("Repeats at \(String(format: "%02d:%02d", local.recurrence.hour, local.recurrence.minute)) in your local time zone. A date beyond the end of a month uses that month's last day.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DisclosureGroup("Notes & meeting link") {
                        TextField("Notes", text: $local.notes, axis: .vertical).lineLimit(2...4)
                        TextField("Meeting link", text: $local.url)
                    }
                }
                Section {
                    DisclosureGroup("Alert options") {
                        Picker("Maximum alert style", selection: $local.intensity) { ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Toggle("Allow sound for this reminder", isOn: $local.sound)
                        Text("Sound also needs to be enabled in Settings → Alerts.").font(.caption).foregroundStyle(.secondary)
                        Stepper("Preferred snooze: \(local.snoozeMinutes) min", value: $local.snoozeMinutes, in: 1...120)
                    }
                }
                if existing != nil && local.recurrence.frequency != .none {
                    Text("Saving updates this whole repeating reminder. Completed items stay in History.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).haunted()
        .onAppear { titleFocused = true }
        .onChange(of: local.due) { _, _ in syncRepeatTime() }
        .onChange(of: local.recurrence.frequency) { _, _ in syncRepeatTime() }
        .confirmationDialog("Update this repeating reminder?", isPresented: $confirmSeries) {
            Button("Save whole series", action: save)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Future occurrences will use these changes. Completed items stay in History.") }
    }

    private func save() {
        model.addOrEdit(local)
        if !model.showEditor { onSaved() }
    }

    private func syncRepeatTime() {
        let c = Calendar.current.dateComponents([.hour, .minute, .weekday, .day], from: local.due)
        local.recurrence.hour = c.hour ?? 9
        local.recurrence.minute = c.minute ?? 0
        local.recurrence.weekday = c.weekday ?? 2
        local.recurrence.day = c.day ?? 1
    }
}
struct TimingEditor: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    var close: () -> Void
    @State private var timing = Timing()
    @State private var ceiling = Intensity.prominent
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Cancel", action: close).buttonStyle(.borderless)
                Spacer()
                Text("Alert timing").font(.headline)
                Spacer()
                Button("Save") { model.setOverride(item.id, timing: timing, ceiling: ceiling); close() }.buttonStyle(HauntedPrimaryStyle()).disabled(!timing.valid)
            }
            Text(model.preferences.privateTitles ? "This item only" : item.title).font(.title3.weight(.semibold)).lineLimit(2)
            Text("Minutes before this item is due. Set 0 to alert at its due time.").font(.callout).foregroundStyle(.secondary)
            TimingControls(timing: $timing)
            Picker("Maximum alert style", selection: $ceiling) { ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) } }
            Button("Use default timing") { model.setOverride(item.id, timing: nil, ceiling: nil); close() }.buttonStyle(.borderless)
            Spacer()
        }.padding(18).frame(maxWidth: .infinity).haunted()
        .onAppear { timing = item.timing ?? model.preferences.timing; ceiling = item.ceiling ?? model.preferences.ceiling }
    }
}
struct TimingControls: View {
    @Binding var timing: Timing
    var body: some View {
        timingField("Early warning", key: \.gentle)
        timingField("Side reminder", key: \.prominent)
        timingField("Fullscreen", key: \.fullscreen)
        if !timing.valid { Text("Early warning must come before the side reminder, then fullscreen. Use 0 or more minutes, up to one week.").font(.caption).foregroundStyle(.red) }
    }
    private func timingField(_ title: String, key: WritableKeyPath<Timing, Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Minutes", value: Binding(get: { timing[keyPath: key] / 60 }, set: { timing[keyPath: key] = $0 * 60 }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 70).accessibilityLabel(title + " minutes before due")
            Text("min").foregroundStyle(.secondary)
        }
    }
}
