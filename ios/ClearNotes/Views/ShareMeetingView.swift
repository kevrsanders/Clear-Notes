import SwiftData
import SwiftUI
import UIKit

/// Shares a meeting as a Clear Notes file that anyone with the app can import.
struct ShareMeetingSheet: View {
    let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @State private var includeNotes = false
    @State private var includeRecording = false
    @State private var protect = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var includeReadable = true
    @State private var isMaking = false
    @State private var errorMessage: String?
    @State private var shareItems: ShareItems?

    private var recordingSize: Int64? { meeting.playableAudioURL.flatMap(MeetingSharing.fileSize) }
    private var hasNotes: Bool { !meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var readableName: String { meeting.minutes.isEmpty ? "notes" : "minutes" }

    private var passwordProblem: String? {
        guard protect else { return nil }
        if password.count < 8 { return "Use at least 8 characters." }
        if password != confirmation { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Transcript, with speaker names", systemImage: "text.quote")
                    Label("Summary, topics and decisions", systemImage: "sparkles")
                    Label("Actions, with owners and dates", systemImage: "checklist")
                    if !meeting.minutes.isEmpty {
                        Label("Minutes", systemImage: "doc.plaintext")
                    }
                } header: {
                    Text("Included")
                } footer: {
                    Text("Anyone with Clear Notes can open the file and import their own copy. Remembered voices are never included.")
                }

                Section {
                    Toggle("My private notes", isOn: $includeNotes)
                        .disabled(!hasNotes)
                    Toggle(isOn: $includeRecording) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording")
                            Text(recordingSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "No recording kept")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .disabled(recordingSize == nil)
                } header: {
                    Text("Also include")
                }

                Section {
                    Toggle("Protect with a password", isOn: $protect.animation())
                    if protect {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Password again", text: $confirmation)
                            .textContentType(.newPassword)
                        if let passwordProblem, !password.isEmpty {
                            Text(passwordProblem)
                                .font(.footnote)
                                .foregroundStyle(Theme.warning)
                        }
                    }
                } footer: {
                    Text(protect
                         ? "The file is encrypted (AES-256). Tell the person the password another way, e.g. in person or by phone."
                         : "Recommended for anything sensitive, especially by email.")
                }

                Section {
                    Toggle("Also send the \(readableName) as text", isOn: $includeReadable)
                } footer: {
                    Text("So someone without Clear Notes can still read them.")
                }

                Section {
                    Text("Check what you're allowed to share and how. Work apps managed by your organisation may not accept the file.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Share meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isMaking {
                        ProgressView()
                    } else {
                        Button("Share") {
                            Task { await makeFile() }
                        }
                        .fontWeight(.semibold)
                        .disabled(passwordProblem != nil)
                    }
                }
            }
            .sheet(item: $shareItems, onDismiss: {
                MeetingSharing.clearSharedFiles()
                dismiss()
            }) { items in
                ActivityView(items: items.items)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func makeFile() async {
        isMaking = true
        errorMessage = nil
        defer { isMaking = false }
        let options = ShareOptions(
            includePrivateNotes: includeNotes,
            includeRecording: includeRecording,
            password: protect ? password : nil
        )
        do {
            let url = try await MeetingSharing.makeFile(for: meeting, options: options, sharedBy: myName)
            var items: [Any] = [url]
            if includeReadable {
                items.append(MeetingSharing.readableText(for: meeting))
            }
            shareItems = ShareItems(items: items)
        } catch {
            errorMessage = "The file couldn't be made. \(error.localizedDescription)"
        }
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The system share sheet, for sharing a file together with text.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file someone tapped "Open in Clear Notes" on.
struct ImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

extension Notification.Name {
    /// Posted with a meeting's `PersistentIdentifier` to show it, e.g. after importing it.
    static let openMeeting = Notification.Name("ClearNotes.openMeeting")
}

/// Previews a shared meeting and imports it, asking for the password first when it has one.
struct ImportMeetingView: View {
    let url: URL
    var onImported: (Meeting) -> Void

    private enum Phase {
        case loading
        case needsPassword
        case ready(SharedMeeting)
        case failed(String)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var password = ""
    @State private var passwordMessage: String?
    @State private var includeRecording = true
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Opening…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .needsPassword:
                    passwordForm
                case .ready(let shared):
                    preview(shared)
                case .failed(let message):
                    ContentUnavailableView("Can't open this file", systemImage: "doc.questionmark", description: Text(message))
                }
            }
            .navigationTitle("Shared meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                }
            }
        }
        .task { await load(password: nil) }
        .interactiveDismissDisabled(isImporting)
    }

    private var passwordForm: some View {
        Form {
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit { Task { await load(password: password) } }
                if let passwordMessage {
                    Text(passwordMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                Button("Open") { Task { await load(password: password) } }
                    .disabled(password.isEmpty)
            } header: {
                Text("This meeting is protected")
            } footer: {
                Text("Ask the person who shared it for the password.")
            }
        }
    }

    private func preview(_ shared: SharedMeeting) -> some View {
        let existing = MeetingSharing.existingCopy(of: shared, in: context)
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(shared.title)
                        .font(.title3.bold())
                    Text("\(shared.date.formatted(date: .abbreviated, time: .shortened)) · \(shared.duration.durationString)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    if let sharedBy = shared.sharedBy {
                        Text("Shared by \(sharedBy)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Label("Transcript · \(shared.transcript.count) lines", systemImage: "text.quote")
                Label("\(shared.actions.count) action\(shared.actions.count == 1 ? "" : "s") · \(shared.decisions.count) decision\(shared.decisions.count == 1 ? "" : "s")", systemImage: "checklist")
                if shared.minutes != nil {
                    Label("Minutes", systemImage: "doc.plaintext")
                }
                if shared.privateNotes != nil {
                    Label("Their notes", systemImage: "pencil.line")
                }
                if let recording = shared.recording {
                    Toggle(isOn: $includeRecording) {
                        Label("Recording · \(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))", systemImage: "waveform")
                    }
                }
            } header: {
                Text("Contains")
            }
            if let importError {
                Section {
                    Text(importError)
                        .foregroundStyle(Theme.warning)
                }
            }
            Section {
                if let existing {
                    Text("You already have a copy of this meeting.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Button("Update my copy") { Task { await importIt(shared, replacing: existing) } }
                    Button("Keep both") { Task { await importIt(shared, replacing: nil) } }
                } else {
                    Button("Import") { Task { await importIt(shared, replacing: nil) } }
                        .fontWeight(.semibold)
                }
            } footer: {
                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Importing…")
                    }
                }
            }
            .disabled(isImporting)
        }
    }

    private func load(password: String?) async {
        passwordMessage = nil
        do {
            let opened = try await MeetingSharing.open(url, password: password, withRecording: false)
            phase = .ready(opened.meeting)
        } catch MeetingFileError.passwordRequired {
            phase = .needsPassword
        } catch MeetingFileError.wrongPassword {
            phase = .needsPassword
            passwordMessage = MeetingFileError.wrongPassword.errorDescription
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func importIt(_ shared: SharedMeeting, replacing existing: Meeting?) async {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        var recording: URL?
        if shared.recording != nil, includeRecording {
            do {
                recording = try await MeetingSharing.open(url, password: password.isEmpty ? nil : password, withRecording: true).recording
            } catch {
                importError = "The recording couldn't be imported. \(error.localizedDescription)"
                return
            }
        }
        let meeting = MeetingSharing.importMeeting(shared, recording: recording, replacing: existing, into: context)
        MeetingSharing.discardIncoming(url)
        onImported(meeting)
        dismiss()
    }

    private func close() {
        MeetingSharing.discardIncoming(url)
        dismiss()
    }
}
