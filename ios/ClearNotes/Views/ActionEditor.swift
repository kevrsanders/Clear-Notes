import SwiftData
import SwiftUI

/// Edits an action: what needs doing, who's doing it and by when. Saving a suggested action
/// accepts it, since the user has now checked it.
struct ActionEditor: View {
    let action: ActionItem
    /// People to pick from: the user, named speakers, invited people and other owners.
    let people: [String]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var owner: String
    @State private var due: String
    @State private var detail: String
    @State private var picksDate = false
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var confirmDelete = false

    init(action: ActionItem, people: [String]) {
        self.action = action
        self.people = people
        _text = State(initialValue: action.text)
        _owner = State(initialValue: action.owner ?? "")
        _detail = State(initialValue: action.context ?? "")
        _due = State(initialValue: action.due ?? "")
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedOwner: String { owner.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    TextField("What needs doing", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Detail, e.g. who it's for or what to include", text: $detail, axis: .vertical)
                        .lineLimit(1...4)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    TextField("Name", text: $owner)
                        .textContentType(.name)
                    ForEach(people, id: \.self) { person in
                        Button {
                            owner = person
                        } label: {
                            HStack(spacing: 10) {
                                Avatar(name: person, color: Theme.brand, size: 26, textColor: Theme.onBrand)
                                Text(person)
                                    .foregroundStyle(Color.primary)
                                Spacer(minLength: 0)
                                if trimmedOwner.caseInsensitiveCompare(person) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.brand)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                    if !trimmedOwner.isEmpty {
                        Button("Nobody yet") { owner = "" }
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Who's doing it")
                }

                Section {
                    if picksDate {
                        DatePicker("Due", selection: $date, displayedComponents: .date)
                    } else {
                        TextField("e.g. by Friday", text: $due)
                    }
                    Toggle("Pick a date", isOn: $picksDate.animation())
                } header: {
                    Text("When")
                }

                Section {
                    Button("Delete action", role: .destructive) { confirmDelete = true }
                } footer: {
                    if action.status == .suggested {
                        Text("Saving accepts this suggested action.")
                    }
                }
            }
            .navigationTitle(action.status == .suggested ? "Suggested action" : "Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedText.isEmpty)
                }
            }
            .menuSheet(isPresented: $confirmDelete) {
                MenuSheet("Delete this action?") {
                    MenuGroup {
                        MenuRow("Delete", systemImage: "trash", role: .destructive, action: delete)
                    }
                    MenuCancelButton()
                }
            }
        }
    }

    private func save() {
        action.text = trimmedText
        action.owner = trimmedOwner.isEmpty ? nil : trimmedOwner
        if picksDate {
            action.due = "by " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        } else {
            let trimmedDue = due.trimmingCharacters(in: .whitespacesAndNewlines)
            action.due = trimmedDue.isEmpty ? nil : trimmedDue
        }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        action.context = trimmedDetail.isEmpty ? nil : trimmedDetail
        if action.status == .suggested {
            action.status = .open
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let meeting = action.meeting {
            meeting.actions.removeAll { $0.persistentModelID == action.persistentModelID }
        }
        context.delete(action)
        try? context.save()
        dismiss()
    }
}

extension Meeting {
    /// People an action could be assigned to: the user, named speakers, people invited and anyone
    /// already given an action in this meeting. No duplicates.
    func assignablePeople(myName: String) -> [String] {
        let me = myName.trimmingCharacters(in: .whitespaces)
        let candidates = [me]
            + speakers.sorted { $0.number < $1.number }.compactMap(\.name)
            + attendees
            + actions.compactMap(\.owner)
        var seen = Set<String>()
        return candidates
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
