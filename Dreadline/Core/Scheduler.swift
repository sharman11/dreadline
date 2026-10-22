import Foundation

struct DeliveryGates {
    var activeSession = true
    var validated: Set<SourceKind> = [.local]
    var demo = false
}
struct Presentation: Equatable {
    var items: [Occurrence]
    var intensity: Intensity
    var catchUp: Bool
}
enum Command { case acknowledge, skip, done, snooze(Date), linkOpened }
struct Scheduler {
    var clock: any Clock = SystemClock()
    // Monotonic deadlines apply for this process only. Absolute deadlines recover after restart.
    var runningSnoozes: [UUID: TimeInterval] = [:]
    mutating func apply(_ command: Command, id: UUID, to db: inout Database) throws {
        guard let index = db.occurrences.firstIndex(where: { $0.id == id }) else { throw DomainError.invalid("Reminder no longer exists.") }
        var item = db.occurrences[index]
        if item.state.terminal { return }
        let now = clock.now
        switch command {
        case .acknowledge: item.state = .acknowledged; item.outcome = "Acknowledged locally"
        case .skip: item.state = .skipped; item.outcome = "Skipped occurrence"
        case .linkOpened: item.state = .acknowledged; item.outcome = "Link opened"
        case .done:
            guard item.kind != .calendar else { throw DomainError.invalid("Calendar events cannot be completed.") }
            item.state = .completed; item.outcome = "Completed"
        case .snooze(let deadline):
            guard deadline > now else { throw DomainError.invalid("Choose a future snooze time.") }
            let capped = item.kind == .calendar ? min(deadline, item.expiry(db.preferences) ?? deadline) : deadline
            guard capped > now.addingTimeInterval(1) else { throw DomainError.invalid("This event has ended. Use Skip instead.") }
            item.state = .snoozed; item.snoozeUntil = capped
            runningSnoozes[id] = clock.uptime + capped.timeIntervalSince(now)
            item.lastStage = nil
            if item.kind != .calendar { item.deliveryWindowEnd = capped.addingTimeInterval(db.preferences.taskWindow) }
        }
        if item.state.terminal { item.resolvedAt = now; item.snoozeUntil = nil; runningSnoozes[id] = nil }
        item.updated = now
        db.occurrences[index] = item
        db.log("action.\(item.state.rawValue)", now: now)
        if item.state.terminal, item.kind == .local, let series = item.seriesID,
           let local = db.locals.first(where: { $0.id == series }),
           let next = local.recurrence.next(after: max(now, item.due ?? now)) {
            db.occurrences.append(Self.occurrence(local, due: next))
        }
    }
    static func occurrence(_ local: LocalReminder, due: Date? = nil) -> Occurrence {
        Occurrence(kind: .local, sourceID: "local", sourceName: "Local", providerID: local.id.uuidString,
                   anchor: due ?? local.due, seriesID: local.id, title: local.title,
                   links: SafeLinks.extract(structured: local.url, notes: local.notes).map(\.absoluteString),
                   due: due ?? local.due, ceiling: local.intensity, recurring: local.recurrence.frequency != .none)
    }
    mutating func evaluate(_ db: inout Database, gates: DeliveryGates, catchUp: Bool = false) -> Presentation? {
        let now = clock.now
        if db.paused, let until = db.pauseUntil, until <= now { db.paused = false; db.pauseUntil = nil }
        let p = db.preferences
        var active: [Occurrence] = []
        var level: Intensity = .gentle
        for i in db.occurrences.indices {
            var item = db.occurrences[i]
            let priorState = item.state
            let priorStage = item.lastStage
            guard !item.state.terminal, item.outcome != "Identity ambiguous; delivery suppressed" else { continue }
            if item.kind == .calendar, let expiry = item.expiry(p), expiry <= now {
                item.state = .expired; item.outcome = "Event ended"; item.resolvedAt = now
                db.occurrences[i] = item; db.log("state.expired", now: now); continue
            }
            guard gates.validated.contains(item.kind), let due = item.due else { continue }
            let timing = item.timing ?? p.timing
            guard timing.valid else { continue }
            let first = due.addingTimeInterval(-timing.gentle)
            if now < first { continue }
            if item.state == .snoozed {
                if let monotonic = runningSnoozes[item.id] {
                    if clock.uptime < monotonic { continue }
                } else if let deadline = item.snoozeUntil, now < deadline { continue }
                item.state = .eligible; item.snoozeUntil = nil; runningSnoozes[item.id] = nil
            }
            if item.state == .scheduled { item.state = .eligible }
            db.occurrences[i] = item
            if item.state != priorState { db.log("state.\(item.state.rawValue)", now: now) }
            guard !db.paused, !p.quiet.contains(now), gates.activeSession, (p.alertsEnabled || gates.demo) else { continue }
            // Tasks remain pending after the interruption window, and appear only in catch-up.
            if item.kind != .calendar, let expiry = item.expiry(p), now >= expiry, !catchUp { continue }
            var stage: Intensity = now >= due.addingTimeInterval(-timing.fullscreen) ? .fullscreen : (now >= due.addingTimeInterval(-timing.prominent) ? .prominent : .gentle)
            stage = min(stage, item.ceiling ?? p.ceiling, p.ceiling)
            if !p.fullscreenEnabled { stage = min(stage, .prominent) }
            if catchUp { stage = min(stage, .prominent) }
            item.state = .presenting
            item.lastStage = max(item.lastStage ?? .gentle, stage)
            db.occurrences[i] = item
            if priorState != .presenting || priorStage != stage { db.log("delivery.\(stage.title.lowercased())", now: now) }
            active.append(item); level = max(level, stage)
        }
        // Retain the existing queue without re-sounding; presentation sinks compare identity/stage.
        return active.isEmpty ? nil : Presentation(items: active.filter { min($0.ceiling ?? p.ceiling, p.ceiling) >= level }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }, intensity: level, catchUp: catchUp)
    }
    func nextDeadline(_ db: Database) -> Date? {
        let now = clock.now
        var dates: [Date] = []
        if let pause = db.pauseUntil { dates.append(pause) }
        if let quiet = db.preferences.quiet.nextBoundary(after: now) { dates.append(quiet) }
        for item in db.occurrences where !item.state.terminal {
            guard let due = item.due else { continue }
            let t = item.timing ?? db.preferences.timing
            dates += [due.addingTimeInterval(-t.gentle), due.addingTimeInterval(-t.prominent), due.addingTimeInterval(-t.fullscreen)]
            if let deadline = item.snoozeUntil {
                if let mono = runningSnoozes[item.id] { dates.append(now.addingTimeInterval(max(0, mono - clock.uptime))) }
                else { dates.append(deadline) }
            }
            if let expiry = item.expiry(db.preferences) { dates.append(expiry) }
        }
        return dates.filter { $0 > now.addingTimeInterval(0.05) }.min()
    }
}

struct Reconciler {
    static func merge(_ result: SourceResult, into db: inout Database, now: Date) {
        let selected = result.kind == .calendar ? db.preferences.selectedCalendars : db.preferences.selectedLists
        let available = Set(result.sources.map(\.id))
        var matched = Set<UUID>()
        for var incoming in result.items where selected.contains(incoming.sourceID) {
            let candidates = db.occurrences.indices.filter { i in
                let old = db.occurrences[i]
                guard old.kind == incoming.kind, old.sourceID == incoming.sourceID, old.accountID == incoming.accountID, !matched.contains(old.id) else { return false }
                let provider = old.providerID == incoming.providerID || (!old.externalID.isEmpty && old.externalID == incoming.externalID)
                // Recurring anchors must match. Nonrecurring identity can survive time edits.
                return provider && (!(old.recurring || incoming.recurring) || old.anchor == incoming.anchor)
            }
            if candidates.count > 1 {
                db.log("identity.ambiguous", now: now)
                // Preserve old state, but suppress both candidates until ambiguity is resolved.
                for i in candidates { matched.insert(db.occurrences[i].id); db.occurrences[i].outcome = "Identity ambiguous; delivery suppressed" }
                continue
            }
            if let i = candidates.first {
                let old = db.occurrences[i]
                incoming.id = old.id; incoming.state = old.state; incoming.resolvedAt = old.resolvedAt
                incoming.snoozeUntil = old.snoozeUntil; incoming.deliveryWindowEnd = old.deliveryWindowEnd; incoming.lastStage = old.lastStage
                incoming.timing = old.timing; incoming.ceiling = old.ceiling
                incoming.outcome = old.outcome == "Identity ambiguous; delivery suppressed" ? nil : old.outcome
                incoming.changed = old.changed || old.due != incoming.due || old.title != incoming.title || old.links != incoming.links || old.location != incoming.location
                if incoming.due != old.due, !old.state.terminal { incoming.lastStage = nil }
                db.occurrences[i] = incoming; matched.insert(old.id)
            } else {
                incoming.updated = now; db.occurrences.append(incoming); matched.insert(incoming.id)
            }
        }
        for i in db.occurrences.indices where db.occurrences[i].kind == result.kind && !matched.contains(db.occurrences[i].id) && !db.occurrences[i].state.terminal {
            db.occurrences[i].state = .cancelled
            db.occurrences[i].resolvedAt = now
            db.occurrences[i].outcome = !selected.contains(db.occurrences[i].sourceID) ? "Source deselected" : (!available.contains(db.occurrences[i].sourceID) ? "Source unavailable" : "Removed or completed at source")
        }
    }
}
