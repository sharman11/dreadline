import SwiftUI

struct LocalEditor: View {
    @ObservedObject var model: AppModel
    let existing: LocalReminder?
    @Environment(\.dismiss) var dismiss
    @State private var local = LocalReminder(title: "", due: Date().addingTimeInterval(600))
    @State private var confirmSeries = false
    var body: some View {
        VStack(alignment: .leading) {
            Text(existing == nil ? "Create local reminder" : "Edit local series").font(.title2)
            Form {
                TextField("Title", text: $local.title)
                TextField("Notes", text: $local.notes, axis: .vertical).lineLimit(3...6)
                TextField("Optional URL", text: $local.url)
                DatePicker("First due date & time", selection: $local.due)
                Picker("Repeat", selection: $local.recurrence.frequency) { ForEach(RepeatFrequency.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                if local.recurrence.frequency != .none {
                    HStack { Stepper("Hour: \(local.recurrence.hour)", value: $local.recurrence.hour, in: 0...23); Stepper("Minute: \(local.recurrence.minute)", value: $local.recurrence.minute, in: 0...59) }
                    if local.recurrence.frequency == .weekdays {
                        HStack { ForEach(1...7, id: \.self) { day in
                            Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { local.recurrence.weekdays.contains(day) }, set: { if $0 { local.recurrence.weekdays.insert(day) } else { local.recurrence.weekdays.remove(day) } })).toggleStyle(.checkbox)
                        } }
                    }
                    if local.recurrence.frequency == .weekly { Picker("Weekday", selection: $local.recurrence.weekday) { ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) } } }
                    if local.recurrence.frequency == .monthly { Stepper("Day: \(local.recurrence.day) (clamped to month's last day)", value: $local.recurrence.day, in: 1...31) }
                    Text("Later occurrences follow local wall-clock time when traveling. DST gaps use the next valid time; folds use the first. Completion schedules the next occurrence.").font(.caption)
                }
                Picker("Intensity ceiling", selection: $local.intensity) { ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Sound (also requires global sound opt-in)", isOn: $local.sound)
                Stepper("Preferred snooze: \(local.snoozeMinutes) min", value: $local.snoozeMinutes, in: 1...120)
            }.formStyle(.grouped)
            if let error = model.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(existing == nil ? "Create" : "Save entire series") {
                    if existing == nil { model.addOrEdit(local) } else { confirmSeries = true }
                }.disabled(local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (local.recurrence.frequency == .weekdays && local.recurrence.weekdays.isEmpty))
            }
        }.padding(24).frame(width: 620, height: 650)
        .onAppear {
            if let existing { local = existing }
            else { let c = Calendar.current.dateComponents([.hour, .minute, .weekday, .day], from: local.due); local.recurrence.hour = c.hour ?? 9; local.recurrence.minute = c.minute ?? 0; local.recurrence.weekday = c.weekday ?? 2; local.recurrence.day = c.day ?? 1 }
        }
        .confirmationDialog("Replace unresolved occurrences of this entire local series?", isPresented: $confirmSeries) { Button("Save entire series") { model.addOrEdit(local) }; Button("Cancel", role: .cancel) {} }
    }
}
struct TimingEditor: View {
    @ObservedObject var model: AppModel
    let item: Occurrence
    @Environment(\.dismiss) var dismiss
    @State private var timing = Timing()
    @State private var ceiling = Intensity.prominent
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Override this occurrence").font(.headline)
            TimingControls(timing: $timing)
            Picker("Ceiling", selection: $ceiling) { ForEach(Intensity.allCases, id: \.self) { Text($0.title).tag($0) } }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Reset override") { model.setOverride(item.id, timing: nil, ceiling: nil); dismiss() }
                Button("Save") { model.setOverride(item.id, timing: timing, ceiling: ceiling); dismiss() }.disabled(!timing.valid)
            }
        }.padding(24).frame(width: 480)
        .onAppear { timing = item.timing ?? model.preferences.timing; ceiling = item.ceiling ?? model.preferences.ceiling }
    }
}
struct TimingControls: View {
    @Binding var timing: Timing
    var body: some View {
        TextField("Gentle: seconds before due", value: $timing.gentle, format: .number)
        TextField("Prominent: seconds before due", value: $timing.prominent, format: .number)
        TextField("Fullscreen: seconds before due", value: $timing.fullscreen, format: .number)
        if !timing.valid { Text("Use gentle ≥ prominent ≥ fullscreen ≥ 0.").foregroundStyle(.red) }
    }
}
