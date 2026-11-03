import Foundation
import UIKit

/// Builds transcript lines from timed words, e.g. from the more accurate second pass.
enum TranscriptBuilder {
    /// A new line starts after a sentence ends, after a pause, when the speaker changes, or when
    /// a line runs long. `speakerAt` gives the speaker at a moment, when speakers are already known.
    static func segments(
        from words: [TimedWord],
        speakerAt: (TimeInterval) -> String? = { _ in nil },
        pause: TimeInterval = 1.2,
        longest: TimeInterval = 20
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var current: [TimedWord] = []
        var currentSpeaker: String?

        func finishLine() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(TranscriptSegment(
                start: first.start,
                end: last.end,
                text: current.map(\.text).joined(separator: " "),
                speakerID: currentSpeaker,
                words: current
            ))
            current = []
        }

        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let speaker = speakerAt((word.start + word.end) / 2)
            if let first = current.first, let last = current.last {
                let endsSentence = last.text.last.map { ".?!".contains($0) } ?? false
                let paused = word.start - last.end > pause
                let tooLong = word.end - first.start > longest
                if endsSentence || paused || tooLong || speaker != currentSpeaker {
                    finishLine()
                }
            }
            if current.isEmpty { currentSpeaker = speaker }
            current.append(word)
        }
        finishLine()
        return segments
    }

    /// The speaker of the line covering a moment, or of the nearest line.
    static func speaker(at time: TimeInterval, in segments: [TranscriptSegment]) -> String? {
        if let covering = segments.first(where: { $0.start <= time && time <= $0.end }) {
            return covering.speakerID
        }
        return segments.min { distance(from: time, to: $0) < distance(from: time, to: $1) }?.speakerID
    }

    /// The second pass is used unless it lost most of the words, which would mean a model problem.
    static func isUsable(_ improved: [TranscriptSegment], comparedWith original: [TranscriptSegment]) -> Bool {
        let after = wordCount(improved)
        guard after > 0 else { return false }
        let before = wordCount(original)
        return before == 0 || Double(after) >= Double(before) * 0.6
    }

    static func wordCount(_ segments: [TranscriptSegment]) -> Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    private static func distance(from time: TimeInterval, to segment: TranscriptSegment) -> TimeInterval {
        time < segment.start ? segment.start - time : max(0, time - segment.end)
    }
}

/// Names and terms the transcript should spell correctly: the user's list (Settings → Transcription
/// → My words), plus the people in the meeting and the user's own name.
enum Vocabulary {
    static var userTerms: [String] {
        let saved = UserDefaults.standard.string(forKey: SettingsKeys.customVocabulary) ?? ""
        return terms(from: saved)
    }

    /// One term per line or comma.
    static func terms(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    static func terms(for meeting: Meeting) -> [String] {
        let myName = UserDefaults.standard.string(forKey: SettingsKeys.myName) ?? ""
        let people = meeting.attendees + meeting.speakers.compactMap(\.name) + [myName]
        // Each part of a name too, so "Jayson" can become "Jason" on its own.
        let nameParts = people.flatMap { $0.split(separator: " ").map(String.init) }.filter { $0.count >= 4 }
        var seen = Set<String>()
        return (userTerms + people + nameParts).filter { term in
            let key = term.lowercased()
            return !term.isEmpty && seen.insert(key).inserted
        }
    }

    /// Whether a word is in the iPhone's English dictionary, so near misses don't replace real words.
    @MainActor
    static func isRealWord(_ word: String) -> Bool {
        let range = NSRange(location: 0, length: word.utf16.count)
        let language = UITextChecker.availableLanguages.contains("en_GB") ? "en_GB" : "en_US"
        return checker.rangeOfMisspelledWord(in: word.lowercased(), range: range, startingAt: 0, wrap: false, language: language)
            .location == NSNotFound
    }

    @MainActor private static let checker = UITextChecker()
}

/// Corrects names and terms the transcript almost certainly misheard. Deliberately cautious:
/// - the same letters ignoring case and spaces ("in tune" → "Intune", "nhsmail" → "NHSmail"),
///   except short dictionary words, so "it" never becomes "IT";
/// - a near miss (one or two letters out) only on a word that isn't in the dictionary.
enum VocabularyFixer {
    private struct Entry {
        let spelling: String
        let key: String
        let isSingleWord: Bool
    }

    static func fix(_ segments: [TranscriptSegment], terms: [String], isRealWord: (String) -> Bool) -> [TranscriptSegment] {
        let entries = prepared(terms)
        guard !entries.isEmpty else { return segments }
        return segments.map { segment in
            var segment = segment
            segment.text = fix(segment.text, entries: entries, isRealWord: isRealWord)
            return segment
        }
    }

    static func fix(_ text: String, terms: [String], isRealWord: (String) -> Bool) -> String {
        fix(text, entries: prepared(terms), isRealWord: isRealWord)
    }

    private static func prepared(_ terms: [String]) -> [Entry] {
        terms.compactMap { term in
            let key = normalized(term)
            guard key.count >= 2 else { return nil }
            return Entry(spelling: term, key: key, isSingleWord: !term.contains(" "))
        }
    }

    private static func fix(_ text: String, entries: [Entry], isRealWord: (String) -> Bool) -> String {
        guard !entries.isEmpty else { return text }
        let tokens = text.split(separator: " ").map(String.init)
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            var replacement: (text: String, length: Int)?
            // Longest first, so "in tune" is tried before "in".
            for length in stride(from: min(3, tokens.count - index), through: 1, by: -1) {
                let group = tokens[index..<(index + length)].map(punctuationSplit)
                // Punctuation inside a group means separate words, e.g. "in, tune".
                let inner = group.indices.allSatisfy { position in
                    (position == 0 || group[position].leading.isEmpty)
                        && (position == group.count - 1 || group[position].trailing.isEmpty)
                }
                guard inner, let first = group.first, let last = group.last else { continue }
                let core = group.map { $0.core }.joined()
                let key = normalized(core)
                guard !key.isEmpty else { continue }

                if let entry = entries.first(where: { $0.key == key }) {
                    let unchanged = length == 1 && first.core == entry.spelling
                    let shortRealWord = length == 1 && key.count <= 3 && isRealWord(first.core)
                    if !unchanged && !shortRealWord {
                        replacement = (first.leading + entry.spelling + last.trailing, length)
                        break
                    }
                    if unchanged { break }
                }
                if length == 1, key.count >= 5, !isRealWord(first.core),
                   let entry = entries.first(where: { $0.isSingleWord && isNearMiss(key, $0.key) }) {
                    replacement = (first.leading + entry.spelling + first.trailing, 1)
                    break
                }
            }
            if let replacement {
                result.append(replacement.text)
                index += replacement.length
            } else {
                result.append(tokens[index])
                index += 1
            }
        }
        return result.joined(separator: " ")
    }

    /// Same first letter, similar length, and one letter out (two for long words).
    private static func isNearMiss(_ heard: String, _ term: String) -> Bool {
        guard heard != term, heard.first == term.first, abs(heard.count - term.count) <= 2, term.count >= 4 else {
            return false
        }
        return editDistance(heard, term) <= (term.count >= 8 ? 2 : 1)
    }

    static func editDistance(_ first: String, _ second: String) -> Int {
        let a = Array(first), b = Array(second)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Letters and digits only, lower case: "N3i Ltd." → "n3iltd"
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// "(Intune)," → ("(", "Intune", "),")
    private static func punctuationSplit(_ token: String) -> (leading: String, core: String, trailing: String) {
        let characters = Array(token)
        var start = 0
        var end = characters.count
        while start < end, !(characters[start].isLetter || characters[start].isNumber) { start += 1 }
        while end > start, !(characters[end - 1].isLetter || characters[end - 1].isNumber) { end -= 1 }
        return (String(characters[..<start]), String(characters[start..<end]), String(characters[end...]))
    }
}
