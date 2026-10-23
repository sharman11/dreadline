import Foundation

struct DeliveryGates {
    var activeSession = true
    var validated: Set<SourceKind> = [.local]
    var demo = false
}
/// dash: the ghost streaks across the screen ahead of the early warning.
/// prelude: the early warning (minimize, peek, restore). reminder: the meeting alert.
enum HauntPhase: Equatable { case reminder, prelude, dash }
struct Presentation: Equatable {
    var items: [Occurrence]
    var intensity: Intensity
    var catchUp: Bool
    var phase: HauntPhase = .reminder
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
            if item.arrivalShownFor == item.due { item.arrivalUntil = now }
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
        var preludeIDs = Set<UUID>()
        var dashing: [Occurrence] = []
        let deliverable = !db.paused && !p.quiet.contains(now) && gates.activeSession && (p.alertsEnabled || gates.demo)
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
            let haunt = p.poltergeistEnabled == true && p.fullscreenEnabled && p.ceiling == .fullscreen && (item.ceiling ?? p.ceiling) == .fullscreen
            // The dash: once per due time, in the seconds before the early warning.
            if haunt, item.state == .scheduled, now < first, now >= first.addingTimeInterval(-Haunt.dashLead),
               timing.gentle > Haunt.arrivalLead {
                if item.dashShownFor != due {
                    item.dashShownFor = due
                    item.dashUntil = catchUp || !deliverable ? nil : min(now.addingTimeInterval(Haunt.dashSeconds), first)
                    db.occurrences[i] = item
                    if item.dashUntil != nil { db.log("delivery.dash", now: now) }
                }
                if !catchUp, deliverable, let until = item.dashUntil, now < until { dashing.append(item) }
                continue
            }
            if item.state == .snoozed {
                // Running snoozes use sleep-inclusive monotonic time; restarted ones use the saved deadline.
                if let monotonic = runningSnoozes[item.id] {
                    if clock.uptime < monotonic { continue }
                } else if let deadline = item.snoozeUntil, now < deadline { continue }
                item.state = now < first ? .scheduled : .eligible; item.snoozeUntil = nil; runningSnoozes[item.id] = nil
                db.occurrences[i] = item
            }
            if now < first {
                if item.state != priorState { db.log("state.\(item.state.rawValue)", now: now) }
                continue
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
            let arrivalStart = due.addingTimeInterval(-Haunt.arrivalLead)
            if haunt && now < arrivalStart {
                // A prelude is at most once per due date and never replayed after wake/restart.
                if catchUp {
                    item.preludeShownFor = due; item.preludeUntil = nil
                    db.occurrences[i] = item; continue
                }
                if item.preludeShownFor != due {
                    item.preludeShownFor = due
                    let ongoing = db.occurrences.compactMap(\.preludeUntil).filter { $0 > now }.min()
                    item.preludeUntil = min(ongoing ?? now.addingTimeInterval(Haunt.preludeSeconds), now.addingTimeInterval(Haunt.preludeSeconds), arrivalStart)
                }
                guard let until = item.preludeUntil, now < until else {
                    db.occurrences[i] = item; continue
                }
                stage = .gentle; preludeIDs.insert(item.id)
            } else if haunt {
                if item.arrivalShownFor != due {
                    item.arrivalShownFor = due
                    item.arrivalUntil = catchUp ? now : now.addingTimeInterval(Haunt.arrivalSeconds)
                }
                if catchUp { item.arrivalUntil = now }
                // Once the entrance has been seen, snooze/restart never triggers another jump.
                stage = !catchUp && now < (item.arrivalUntil ?? now) ? .fullscreen : .prominent
            }
            if catchUp { stage = min(stage, .prominent) }
            item.state = .presenting
            item.lastStage = max(item.lastStage ?? .gentle, stage)
            db.occurrences[i] = item
            if priorState != .presenting || priorStage != stage { db.log("delivery.\(stage.title.lowercased())", now: now) }
            active.append(item); level = max(level, stage)
        }
        // Retain the existing queue without re-sounding; presentation sinks compare identity/stage.
        guard !active.isEmpty else {
            return dashing.isEmpty ? nil : Presentation(items: dashing.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) },
                                                        intensity: .gentle, catchUp: false, phase: .dash)
        }
        let displayed = active.filter { min($0.ceiling ?? p.ceiling, p.ceiling) >= level && (level == .gentle || !preludeIDs.contains($0.id)) }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return Presentation(items: displayed, intensity: level, catchUp: catchUp,
                            phase: displayed.allSatisfy { preludeIDs.contains($0.id) } ? .prelude : .reminder)
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
            let p = db.preferences
            if p.poltergeistEnabled == true && p.fullscreenEnabled && p.ceiling == .fullscreen && (item.ceiling ?? p.ceiling) == .fullscreen {
                dates += [due.addingTimeInterval(-Haunt.arrivalLead), due.addingTimeInterval(-t.gentle - Haunt.dashLead)]
            }
            if let until = item.dashUntil { dates.append(until) }
            if let until = item.preludeUntil { dates.append(until) }
            if let until = item.arrivalUntil { dates.append(until) }
            dates.append(due)
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
    /// Minimum move that counts as a reschedule; smaller drifts keep the user's decision.
    static let rescheduleThreshold: TimeInterval = 60
    static func revives(_ old: Occurrence, as incoming: Occurrence, now: Date) -> Bool {
        guard let due = incoming.due, due > now else { return false }
        if old.state == .cancelled { return true }
        guard old.state == .acknowledged || old.state == .expired else { return false }
        guard let previous = old.due else { return true }
        return abs(due.timeIntervalSince(previous)) >= rescheduleThreshold
    }
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
                incoming.preludeShownFor = old.preludeShownFor; incoming.preludeUntil = old.preludeUntil
                incoming.arrivalShownFor = old.arrivalShownFor; incoming.arrivalUntil = old.arrivalUntil
                incoming.dashShownFor = old.dashShownFor; incoming.dashUntil = old.dashUntil
                incoming.outcome = old.outcome == "Identity ambiguous; delivery suppressed" ? nil : old.outcome
                incoming.changed = old.changed || old.due != incoming.due || old.title != incoming.title || old.links != incoming.links || old.location != incoming.location
                if incoming.due != old.due, !old.state.terminal { incoming.lastStage = nil }
                if old.state.terminal, revives(old, as: incoming, now: now) {
                    // A dismissed/ended item that moved to a new future time, or a system-cancelled
                    // item that reappeared at its source, is a fresh commitment again. Skip and Done stick.
                    incoming.state = .scheduled; incoming.resolvedAt = nil; incoming.outcome = nil
                    incoming.snoozeUntil = nil; incoming.deliveryWindowEnd = nil; incoming.lastStage = nil
                    incoming.preludeUntil = nil; incoming.arrivalUntil = nil; incoming.dashUntil = nil
                    db.log("state.revived", now: now)
                }
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
