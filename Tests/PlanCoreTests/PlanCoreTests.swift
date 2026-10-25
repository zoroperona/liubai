import XCTest
@testable import PlanCore

final class PlanCoreTests: XCTestCase {
    func testCompletionHistoryAndRecompletion() throws {
        let a = Plan(title: "A", horizon: .current)
        let b = Plan(title: "B", horizon: .long)
        var old = Plan(title: "旧任务", horizon: .medium)
        old.completed = true
        var doc = PlanDocument(plans: [a, old, b])
        doc.setCompleted(a.id, true, at: Date(timeIntervalSince1970: 10))
        doc.setCompleted(b.id, true, at: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(doc.completedPlans.map(\.id), [b.id, a.id, old.id])
        doc.setCompleted(a.id, false)
        XCTAssertNil(doc.plans[0].completedAt)
        XCTAssertEqual(doc.completedPlans.map(\.id), [b.id, old.id])
        doc.setCompleted(a.id, true, at: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(doc.completedPlans.map(\.id), [a.id, b.id, old.id])
        XCTAssertFalse(doc.move(a.id, to: b.id))
        XCTAssertEqual(try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(doc)), doc)
    }
    func testHighlightPersistenceAndLegacyCompletedPlan() throws {
        var doc = PlanDocument(plans: [Plan(title: "旧计划", horizon: .current)])
        doc.plans[0].completed = true
        doc.mood = "中文🌿心情"
        doc.moodHighlights = [MoodHighlight(location: 2, length: 2, color: .green)]
        XCTAssertTrue(doc.moodHighlights[0].isValid(for: doc.mood))
        XCTAssertFalse(MoodHighlight(location: Int.max, length: 2, color: .blue).isValid(for: doc.mood))
        XCTAssertEqual(try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(doc)), doc)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
        legacy.removeValue(forKey: "moodHighlights")
        let decoded = try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.moodHighlights.isEmpty)
        XCTAssertTrue(decoded.plans[0].completed)
        XCTAssertNil(decoded.plans[0].completedAt)
    }
    func testReorderingPreservesLockedSlotsAndOtherTabs() {
        let a = Plan(title: "A", horizon: .current)
        var locked = Plan(title: "Locked", horizon: .current)
        locked.locked = true
        let b = Plan(title: "B", horizon: .current)
        let c = Plan(title: "C", horizon: .current)
        let other = Plan(title: "Other", horizon: .long)
        var doc = PlanDocument(plans: [a, other, locked, b, c])
        XCTAssertTrue(doc.move(c.id, to: a.id))
        XCTAssertEqual(doc.plans.map(\.title), ["C", "Other", "Locked", "A", "B"])
        XCTAssertTrue(doc.move(c.id, to: b.id))
        XCTAssertEqual(doc.plans.map(\.title), ["A", "Other", "Locked", "B", "C"])
    }
    func testInvalidMovesDoNotChangeDocument() {
        let a = Plan(title: "A", horizon: .current)
        var locked = Plan(title: "Locked", horizon: .current)
        locked.locked = true
        let other = Plan(title: "Other", horizon: .medium)
        var doc = PlanDocument(plans: [a, locked, other])
        let original = doc
        XCTAssertFalse(doc.move(locked.id, to: a.id))
        XCTAssertFalse(doc.move(a.id, to: locked.id))
        XCTAssertFalse(doc.move(a.id, to: other.id))
        XCTAssertFalse(doc.move(a.id, to: a.id))
        XCTAssertFalse(doc.move(UUID(), to: a.id))
        XCTAssertEqual(doc, original)
    }
    func testPersistenceRoundTripAndMissingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("plans.json")
        XCTAssertEqual(try PlanPersistence.read(from: url), PlanDocument())
        var plan = Plan(title: "中文计划", horizon: .medium)
        plan.notes = "多行备注\n第二行"
        plan.locked = true
        plan.completed = true
        plan.subtasks = [Subtask(title: "步骤一")]
        var doc = PlanDocument(plans: [plan])
        doc.mood = "今天很开心\n也想慢慢来。"
        try PlanPersistence.write(doc, to: url)
        XCTAssertEqual(try PlanPersistence.read(from: url), doc)
    }
    func testExistingDocumentWithoutMoodStillLoads() throws {
        let original = PlanDocument(plans: [Plan(title: "保留原有计划", horizon: .current)])
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "mood")
        let decoded = try JSONDecoder().decode(PlanDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.mood, "")
    }
    func testCorruptAndFutureDocumentsAreNotOverwrittenByReading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for value in ["not json", "{\"version\":99,\"plans\":[]}"] {
            let data = Data(value.utf8)
            try data.write(to: url)
            XCTAssertThrowsError(try PlanPersistence.read(from: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
}
