import XCTest
@testable import PlanCore

final class PlanCoreTests: XCTestCase {
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
