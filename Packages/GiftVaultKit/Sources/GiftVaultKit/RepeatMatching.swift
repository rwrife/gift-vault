import Foundation

// Repeat-match rule (issue #2): given a person and a candidate item
// description, find prior GIVEN ledger entries for that person whose
// normalized description matches — "what did I already get Alex?"

/// Deterministic description normalization used for repeat detection.
///
/// Contract (all steps, in order):
/// 1. Fold to lowercase using simple (Unicode scalar) case folding, which
///    is locale-independent and stable across runs.
/// 2. Remove every character that is neither a letter nor a number
///    (case, whitespace, and punctuation-insensitive by construction).
///
/// The result is a bare alphanumeric run: `"Pour-over Coffee, 12oz!"` and
/// `"pour over coffee 12oz"` both normalize to `"pourovercoffee12oz"`.
/// An empty input normalizes to the empty string, which never counts as
/// a match (see `RepeatMatcher`).
public enum DescriptionNormalizer {
    public static func normalized(_ text: String) -> String {
        text.lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { result, scalar in
                result.unicodeScalars.append(scalar)
            }
    }
}

extension LedgerEntry {
    /// Normalized form of this entry's item description.
    public var normalizedDescription: String {
        DescriptionNormalizer.normalized(itemDescription)
    }
}

public enum RepeatMatcher {
    /// Prior given entries for `personID` whose normalized item description
    /// equals the normalized candidate. Empty candidates (raw or
    /// normalization-empty, e.g. "???") match nothing. Results preserve the
    /// input order so callers can keep their own sort (e.g. by date).
    public static func matches(
        candidateDescription: String,
        personID: UUID,
        in ledger: [LedgerEntry]
    ) -> [LedgerEntry] {
        let target = DescriptionNormalizer.normalized(candidateDescription)
        guard !target.isEmpty else { return [] }
        return ledger.filter { entry in
            entry.direction == .given
                && entry.personID == personID
                && entry.normalizedDescription == target
        }
    }
}
