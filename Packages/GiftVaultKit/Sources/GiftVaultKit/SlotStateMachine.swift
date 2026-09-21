import Foundation

// The occasion-slot status state machine (issue #2).
//
// Legal lifecycle:  idea → chosen → bought → wrapped → given
// `given` is terminal. No backward moves and no skipping ahead — the only
// legal transition out of a state is to its immediate successor in
// `OccasionStatus.pipeline`.

public enum SlotTransitionError: Error, Equatable, Sendable {
    /// Attempted to move out of the terminal `given` state.
    case terminal(state: OccasionStatus)
    /// Attempted a move that is not the immediate next step (backward or skipping).
    case illegal(from: OccasionStatus, to: OccasionStatus)
    /// Attempted to enter `chosen` without a selected idea on the slot.
    case chosenWithoutIdea
}

extension OccasionStatus {
    /// The immediate legal successor, or nil for the terminal state.
    public var next: OccasionStatus? {
        switch self {
        case .idea: .chosen
        case .chosen: .bought
        case .bought: .wrapped
        case .wrapped: .given
        case .given: nil
        }
    }

    /// Whether a direct transition from `self` to `target` is legal.
    public func canTransition(to target: OccasionStatus) -> Bool {
        next == target
    }
}

extension OccasionSlot {
    /// Returns a copy of this slot advanced to `target`, enforcing the
    /// state machine. The `chosen` step additionally requires that a
    /// `chosenIdeaID` is set on the slot (before or in this call).
    public func byTransitioning(to target: OccasionStatus, chosenIdeaID: UUID? = nil) throws -> OccasionSlot {
        if status == .given {
            throw SlotTransitionError.terminal(state: status)
        }
        guard status.canTransition(to: target) else {
            throw SlotTransitionError.illegal(from: status, to: target)
        }
        var updated = self
        if let chosenIdeaID {
            updated.chosenIdeaID = chosenIdeaID
        }
        if target == .chosen && updated.chosenIdeaID == nil {
            throw SlotTransitionError.chosenWithoutIdea
        }
        updated.status = target
        return updated
    }

    /// Convenience: advance exactly one step (`nil` if already terminal).
    /// Throws `chosenWithoutIdea` when stepping into `chosen` without an idea.
    public func byAdvancing() throws -> OccasionSlot? {
        guard let target = status.next else { return nil }
        return try byTransitioning(to: target)
    }
}

// MARK: - Given-side ledger implication contract

/// The ledger implication produced when a slot reaches `given`.
/// `given` is terminal *and* records itself in history; this pure function
/// is the contract for what that ledger row looks like. Persistence (issue #3)
/// materializes it; the domain guarantees its shape.
public struct GivenLedgerImplication: Sendable, Hashable, Codable {
    public var direction: LedgerDirection   // always `.given`
    public var personID: UUID
    public var occasionID: UUID
    /// Item description taken from the chosen idea's note, if resolvable.
    public var itemDescription: String?
    /// Value taken from the chosen idea's price hint, if any (integer cents).
    public var valueCents: BudgetMinorUnits?
}

extension OccasionSlot {
    /// The ledger row this slot *implies* at the moment it transitions to
    /// `given`. `date` is supplied by the caller (the actual gifting day);
    /// the domain never reads clocks. Returns nil if this slot is not in
    /// the `given` state.
    public func givenLedgerImplication(on date: CalendarDate, chosenIdea: GiftIdea?) -> GivenLedgerImplication? {
        guard status == .given else { return nil }
        return GivenLedgerImplication(
            direction: .given,
            personID: personID,
            occasionID: occasionID,
            itemDescription: chosenIdea?.note,
            valueCents: chosenIdea?.priceHintCents
        )
    }

    /// Materialize the implied ledger entry for a slot in `given`.
    public func givenLedgerEntry(on date: CalendarDate, chosenIdea: GiftIdea?) -> LedgerEntry? {
        guard let implication = givenLedgerImplication(on: date, chosenIdea: chosenIdea) else {
            return nil
        }
        return LedgerEntry(
            direction: implication.direction,
            date: date,
            personID: implication.personID,
            occasionID: implication.occasionID,
            itemDescription: implication.itemDescription ?? "",
            valueCents: implication.valueCents
        )
    }
}
