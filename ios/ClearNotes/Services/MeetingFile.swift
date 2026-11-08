import CommonCrypto
import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A meeting shared from Clear Notes (a `.clearnotes` file). Declared in Info.plist.
    static let clearNotesMeeting = UTType(exportedAs: "com.clearnotes.meeting")
}

/// A meeting as shared between Clear Notes users, and later uploaded to the web app. The field
/// names are the documented file format (docs/meeting-file-format.md): new optional fields can be
/// added freely, but existing ones aren't renamed or removed without a new `formatVersion`.
///
/// Remembered voiceprints are never included: they're biometric data.
struct SharedMeeting: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    struct Person: Codable, Equatable, Sendable {
        var id: String
        var number: Int
        var name: String?
    }

    struct Line: Codable, Equatable, Sendable {
        var id: UUID
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var speakerID: String?
    }

    struct Section: Codable, Equatable, Sendable {
        var title: String
        var start: TimeInterval
        var end: TimeInterval
        var points: [String]
    }

    struct Action: Codable, Equatable, Sendable {
        var text: String
        var owner: String?
        var due: String?
        /// "suggested", "open", "done" or "dismissed".
        var status: String
        /// The transcript line it came from.
        var sourceLineID: UUID?
        /// A short line of detail, e.g. who it's for. Added in 0.3; older files don't have it.
        var context: String?
        /// Its number in the meeting (3 in WCI-3). Added in 0.3.
        var number: Int?
    }

    struct Recording: Codable, Equatable, Sendable {
        /// Size of the recording that follows the meeting in the file.
        var byteCount: Int64
        /// The recording's file type: "caf" (16 kHz mono 16-bit PCM).
        var fileExtension: String
    }

    var formatVersion: Int
    /// The same for every copy of this meeting, so importing it again can update a copy.
    var meetingID: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var sharedBy: String?
    var sharedAt: Date
    var invited: [String]
    var speakers: [Person]
    var transcript: [Line]
    var summary: String
    var topics: [Section]
    var decisions: [String]
    var actions: [Action]
    var minutes: String?
    /// The sender's own notes, only when they chose to include them.
    var privateNotes: String?
    var notesCaveat: String?
    var notesSource: String?
    var recording: Recording?
    /// What was recorded: "meeting", "catchUp" or "voiceNote". Missing (older files) means a meeting.
    var kind: String? = nil
    /// The start of the meeting's action references ("WCI" in WCI-3), so a copy keeps the same
    /// references. Added in 0.3.
    var actionPrefix: String? = nil
}

enum MeetingFileError: LocalizedError, Equatable {
    case notAMeetingFile
    case newerVersion
    case passwordRequired
    case wrongPassword
    case damaged

    var errorDescription: String? {
        switch self {
        case .notAMeetingFile: "This isn't a Clear Notes meeting file."
        case .newerVersion: "This meeting was shared from a newer version of Clear Notes. Update the app to open it."
        case .passwordRequired: "This meeting is protected with a password."
        case .wrongPassword: "That password isn't right."
        case .damaged: "This file is damaged or incomplete, so it can't be opened."
        }
    }
}

/// The `.clearnotes` container: a short header, then records. The first record is the meeting as
/// JSON, then the recording (if included) in 1 MB pieces, then an end record with the
/// recording's size and SHA-256. With a password, every record is sealed with AES-256-GCM using a
/// key derived from the password (PBKDF2-HMAC-SHA256), and each record's position is authenticated
/// so pieces can't be reordered or swapped. See docs/meeting-file-format.md.
enum MeetingFileFormat {
    static let magic = Data("CLRNOTES".utf8)
    static let version: UInt8 = 1
    static let defaultIterations: UInt32 = 600_000
    static let audioChunkSize = 1 << 20
    private static let maxRecordSize = 128 << 20

    private enum Record: UInt8 {
        case end = 0
        case meeting = 1
        case audio = 2
    }

    private struct Header {
        var isProtected: Bool
        var salt: Data
        var iterations: UInt32
    }

    // MARK: Writing

    static func write(
        _ meeting: SharedMeeting,
        audio: URL?,
        password: String?,
        to url: URL,
        iterations: UInt32 = defaultIterations
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }

        var header = magic
        header.append(version)
        var key: SymmetricKey?
        if let password, !password.isEmpty {
            let salt = randomBytes(16)
            header.append(UInt8(1))
            header.append(salt)
            header.appendBigEndian(iterations)
            key = try deriveKey(password: password, salt: salt, iterations: iterations)
        } else {
            header.append(UInt8(0))
        }
        try output.write(contentsOf: header)

        var writer = RecordWriter(handle: output, key: key)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try writer.write(.meeting, try encoder.encode(meeting))

        var hasher = SHA256()
        var audioBytes: UInt64 = 0
        if let audio {
            let input = try FileHandle(forReadingFrom: audio)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: audioChunkSize), !chunk.isEmpty {
                hasher.update(data: chunk)
                audioBytes += UInt64(chunk.count)
                try writer.write(.audio, chunk)
            }
        }
        var trailer = Data()
        trailer.appendBigEndian(audioBytes)
        trailer.append(contentsOf: hasher.finalize())
        try writer.write(.end, trailer)
    }

    // MARK: Reading

    /// Whether the file needs a password, without reading the rest.
    static func isProtected(_ url: URL) throws -> Bool {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        return try readHeader(input).isProtected
    }

    /// The meeting in a file. With `audioURL`, the recording (if any) is written there and checked;
    /// without it, only the meeting is read, e.g. for a preview.
    static func read(_ url: URL, password: String?, writingAudioTo audioURL: URL? = nil) throws -> SharedMeeting {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let header = try readHeader(input)
        var key: SymmetricKey?
        if header.isProtected {
            guard let password, !password.isEmpty else { throw MeetingFileError.passwordRequired }
            key = try deriveKey(password: password, salt: header.salt, iterations: header.iterations)
        }

        var reader = RecordReader(handle: input, key: key)
        guard let first = try reader.next(), first.type == .meeting else { throw MeetingFileError.damaged }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting: SharedMeeting
        do {
            meeting = try decoder.decode(SharedMeeting.self, from: first.data)
        } catch {
            throw MeetingFileError.damaged
        }
        guard meeting.formatVersion <= SharedMeeting.currentFormatVersion else { throw MeetingFileError.newerVersion }
        guard let audioURL else { return meeting }

        FileManager.default.createFile(atPath: audioURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: audioURL)
        defer { try? output.close() }
        var hasher = SHA256()
        var total: UInt64 = 0
        while let record = try reader.next() {
            switch record.type {
            case .audio:
                hasher.update(data: record.data)
                total += UInt64(record.data.count)
                try output.write(contentsOf: record.data)
            case .end:
                guard record.data.count == 40,
                      record.data.prefix(8).bigEndianInteger(as: UInt64.self) == total,
                      Data(hasher.finalize()) == record.data.suffix(32)
                else { throw MeetingFileError.damaged }
                return meeting
            case .meeting:
                throw MeetingFileError.damaged
            }
        }
        // No end record: the file was cut short.
        throw MeetingFileError.damaged
    }

    // MARK: Pieces

    private static func readHeader(_ input: FileHandle) throws -> Header {
        guard let start = try input.read(upToCount: 10), start.count == 10, start.prefix(8) == magic else {
            throw MeetingFileError.notAMeetingFile
        }
        let bytes = [UInt8](start)
        guard bytes[8] <= version else { throw MeetingFileError.newerVersion }
        guard bytes[9] & 1 == 1 else { return Header(isProtected: false, salt: Data(), iterations: 0) }
        guard let extra = try input.read(upToCount: 20), extra.count == 20 else { throw MeetingFileError.damaged }
        let iterations = extra.suffix(4).bigEndianInteger(as: UInt32.self)
        guard iterations > 0, iterations <= 10_000_000 else { throw MeetingFileError.damaged }
        return Header(isProtected: true, salt: Data(extra.prefix(16)), iterations: iterations)
    }

    private struct RecordWriter {
        let handle: FileHandle
        let key: SymmetricKey?
        var index: UInt32 = 0

        mutating func write(_ type: Record, _ plain: Data) throws {
            var body = plain
            if let key {
                let sealed = try AES.GCM.seal(plain, using: key, authenticating: MeetingFileFormat.additionalData(type, index))
                guard let combined = sealed.combined else { throw MeetingFileError.damaged }
                body = combined
            }
            var head = Data([type.rawValue])
            head.appendBigEndian(UInt32(body.count))
            try handle.write(contentsOf: head)
            try handle.write(contentsOf: body)
            index += 1
        }
    }

    private struct RecordReader {
        let handle: FileHandle
        let key: SymmetricKey?
        var index: UInt32 = 0

        mutating func next() throws -> (type: Record, data: Data)? {
            guard let head = try handle.read(upToCount: 5), !head.isEmpty else { return nil }
            let headBytes = [UInt8](head)
            guard headBytes.count == 5, let type = Record(rawValue: headBytes[0]) else { throw MeetingFileError.damaged }
            let length = Int(Data(headBytes[1...]).bigEndianInteger(as: UInt32.self))
            guard length <= MeetingFileFormat.maxRecordSize else { throw MeetingFileError.damaged }
            let body = length == 0 ? Data() : (try handle.read(upToCount: length) ?? Data())
            guard body.count == length else { throw MeetingFileError.damaged }
            let position = index
            index += 1
            guard let key else { return (type, body) }
            do {
                let box = try AES.GCM.SealedBox(combined: body)
                let plain = try AES.GCM.open(box, using: key, authenticating: MeetingFileFormat.additionalData(type, position))
                return (type, plain)
            } catch {
                // The first record failing to open means the key (so the password) is wrong.
                throw position == 0 ? MeetingFileError.wrongPassword : MeetingFileError.damaged
            }
        }
    }

    /// Binds each sealed record to its type and position in the file.
    private static func additionalData(_ type: Record, _ index: UInt32) -> Data {
        var data = Data("clearnotes".utf8)
        data.append(type.rawValue)
        data.appendBigEndian(index)
        return data
    }

    private static func randomBytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    /// PBKDF2-HMAC-SHA256, 256-bit key.
    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            password.utf8.count,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derived,
            derived.count
        )
        guard status == Int32(kCCSuccess) else { throw MeetingFileError.damaged }
        return SymmetricKey(data: derived)
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        for byte in (0..<(T.bitWidth / 8)).reversed() {
            append(UInt8(truncatingIfNeeded: value >> (byte * 8)))
        }
    }

    func bigEndianInteger<T: FixedWidthInteger>(as type: T.Type) -> T {
        reduce(T.zero) { ($0 << 8) | T($1) }
    }
}
