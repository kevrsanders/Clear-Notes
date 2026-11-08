import XCTest
@testable import ClearNotes

final class ActionCheckTests: XCTestCase {
    private let speakers = [
        Speaker(id: "S1", number: 1, name: "Priya Sharma"),
        Speaker(id: "S2", number: 2, name: "Tom Ellis"),
        Speaker(id: "S3", number: 3, name: "Sam Lee"),
    ]

    private func line(_ speaker: String?, _ text: String, at start: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(start: start, end: start + 4, text: text, speakerID: speaker)
    }

    private func check(_ said: [TranscriptSegment], at index: Int, task: String) -> ActionCheck.Result {
        let window = ActionCheck.window(around: index, in: said)
        return ActionCheck.rulesCheck(
            ExtractedAction(task: task, evidence: said[index].text),
            window: window,
            line: said[index],
            speakers: speakers
        )
    }

    func testTurnsAreRunsOfOneSpeaker() {
        let said = [
            line("S1", "Morning.", at: 0),
            line("S1", "Shall we start?", at: 4),
            line("S2", "Yes.", at: 8),
            line(nil, "Hello?", at: 12),
            line(nil, "Can you hear me?", at: 16),
            line("S1", "We can.", at: 20),
        ]
        XCTAssertEqual(ActionCheck.turns(in: said), [0..<2, 2..<3, 3..<4, 4..<5, 5..<6], "A line with no speaker is a turn of its own")
    }

    func testTheWindowIsTwoTurnsEitherSide() {
        let said = [
            line("S3", "Anything else on the rota?", at: 0),
            line("S1", "The weekend shifts still look thin.", at: 4),
            line("S2", "I saw that.", at: 8),
            line("S2", "Can someone fix it before Monday?", at: 12),
            line("S1", "Tom, can you send the revised rota to the ward managers?", at: 16),
            line("S2", "Yes, I'll do it by Friday.", at: 20),
            line("S1", "Great, they need it for Monday's planning meeting.", at: 24),
            line("S3", "Next item.", at: 28),
        ]
        let window = ActionCheck.window(around: 4, in: said)
        XCTAssertEqual(window.map(\.start), [4, 8, 12, 16, 20, 24], "Two turns before (Priya, Tom's two lines) and two after")

        let excerpt = ActionCheck.excerpt(window, line: said[4].id, speakers: speakers)
        XCTAssertTrue(excerpt.contains(">> [0:16] Priya Sharma: Tom, can you send"))
        XCTAssertEqual(excerpt.components(separatedBy: ">>").count, 2, "Only the line itself is marked")
    }

    func testALongWindowKeepsTheLinesNearestTheAction() {
        let long = String(repeating: "word ", count: 200)
        let said = [
            line("S1", long, at: 0),
            line("S2", long, at: 10),
            line("S1", "I'll send the minutes.", at: 20),
            line("S2", long, at: 30),
            line("S1", long, at: 40),
        ]
        let window = ActionCheck.window(around: 2, in: said)
        XCTAssertTrue(window.contains { $0.start == 20 })
        XCTAssertLessThan(window.count, 5)
        XCTAssertLessThanOrEqual(window.reduce(0) { $0 + $1.text.count + 24 }, ActionCheck.excerptCharacterLimit)
    }

    func testARequestOnlyCountsWhenTheNextSpeakerTakesItOn() {
        let accepted = [
            line("S1", "Tom, can you send the revised rota to the ward managers?", at: 0),
            line("S2", "Yes, will do.", at: 4),
        ]
        let yes = check(accepted, at: 0, task: "Send the revised rota to the ward managers")
        XCTAssertEqual(yes.verdict, .acceptedRequest)
        XCTAssertEqual(yes.action.owner, "Tom Ellis", "The person who agreed, not the person asking")

        let declined = [
            line("S1", "Can you send the rota?", at: 0),
            line("S2", "I can't, I'm away all week.", at: 4),
        ]
        XCTAssertEqual(check(declined, at: 0, task: "Send the rota").verdict, .declined)

        let unanswered = [
            line("S1", "Could you look at the budget?", at: 0),
            line("S2", "Hmm, the budget is a whole other story.", at: 4),
        ]
        XCTAssertFalse(check(unanswered, at: 0, task: "Look at the budget").verdict.isTask)
    }

    func testPromisesIdeasAndThingsAlreadyDone() {
        let promise = [line("S3", "I'll book the room for Tuesday.", at: 0)]
        let kept = check(promise, at: 0, task: "Book the room for Tuesday")
        XCTAssertEqual(kept.verdict, .promise)
        XCTAssertEqual(kept.action.owner, "Sam Lee")

        let idea = [line("S1", "We should probably think about the rollout.", at: 0)]
        XCTAssertEqual(check(idea, at: 0, task: "Think about the rollout").verdict, .idea)

        let done = [line("S2", "I've sent the budget to finance already.", at: 0)]
        XCTAssertEqual(check(done, at: 0, task: "Send the budget to finance").verdict, .alreadyDone)

        let loose = [line("S1", "I can see why that would be a problem.", at: 0)]
        XCTAssertFalse(check(loose, at: 0, task: "See why that's a problem").verdict.isTask, "\"I can\" alone isn't a promise")

        let someoneElse = [line("S1", "Priya will chase the supplier.", at: 0)]
        let passed = check(someoneElse, at: 0, task: "Chase the supplier")
        XCTAssertEqual(passed.verdict, .passedOn)
        XCTAssertEqual(passed.action.owner, "Priya")
    }

    func testRepeatsMergeKeepingEveryDetail() {
        let actions = [
            ExtractedAction(task: "Send the revised rota to the ward managers", evidence: "send the rota"),
            ExtractedAction(task: "Book the room", owner: "Sam Lee"),
            ExtractedAction(
                task: "Send the revised rota to ward managers",
                owner: "Tom Ellis",
                due: "by Fri 13 Nov",
                context: "They need it for Monday's planning meeting"
            ),
        ]
        let merged = ActionList.merged(actions)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.owner, "Tom Ellis", "The recap's details win")
        XCTAssertEqual(merged.first?.due, "by Fri 13 Nov")
        XCTAssertEqual(merged.first?.context, "They need it for Monday's planning meeting")
        XCTAssertEqual(merged.first?.evidence, "send the rota", "And it still links back to where it was first said")
        XCTAssertEqual(merged.last?.task, "Book the room")
    }

    func testCheckedActionsAreKeptWithoutCueWords() {
        var checked = ExtractedAction(task: "Draft the handover checklist", evidence: "Leave the checklist with me.")
        XCTAssertFalse(ActionPolicy.isClearCommitment(checked))
        checked.checked = true
        XCTAssertTrue(ActionPolicy.isClearCommitment(checked))
        XCTAssertFalse(ActionPolicy.isClearCommitment(ExtractedAction(task: "Think", evidence: "Let me think about it.")))
    }
}

final class DueDateTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: number, hour: 10))!
    }

    func testWeekdaysBecomeDatesFromTheMeetingDay() {
        // A Wednesday.
        let meeting = day(11)
        XCTAssertEqual(DueDate.resolved("by Friday", from: meeting, calendar: calendar), "by " + DueDate.format(day(13)))
        XCTAssertEqual(DueDate.resolved("By Friday.", from: meeting, calendar: calendar), "by " + DueDate.format(day(13)))
        XCTAssertEqual(DueDate.resolved("Friday", from: meeting, calendar: calendar), DueDate.format(day(13)))
        XCTAssertEqual(DueDate.resolved("this Friday", from: meeting, calendar: calendar), DueDate.format(day(13)))
        XCTAssertEqual(DueDate.resolved("next Friday", from: meeting, calendar: calendar), DueDate.format(day(20)), "Friday of next week")
        XCTAssertEqual(DueDate.resolved("by Wednesday", from: meeting, calendar: calendar), "by " + DueDate.format(day(18)), "Said on a Wednesday: next week's")
        XCTAssertEqual(DueDate.resolved("on Monday", from: meeting, calendar: calendar), "on " + DueDate.format(day(16)))
        XCTAssertEqual(DueDate.resolved("tomorrow", from: meeting, calendar: calendar), DueDate.format(day(12)))
        XCTAssertEqual(DueDate.resolved("by the end of the week", from: meeting, calendar: calendar), "by " + DueDate.format(day(13)))
    }

    func testAnythingElseIsLeftAsSaid() {
        let meeting = day(11)
        XCTAssertEqual(DueDate.resolved("next week", from: meeting, calendar: calendar), "next week")
        XCTAssertEqual(DueDate.resolved("by 20 November", from: meeting, calendar: calendar), "by 20 November")
        XCTAssertEqual(DueDate.resolved("end of the month", from: meeting, calendar: calendar), "end of the month")
        XCTAssertEqual(DueDate.resolved("by the end of the week", from: day(14), calendar: calendar), "by the end of the week", "Already the weekend")
    }
}
