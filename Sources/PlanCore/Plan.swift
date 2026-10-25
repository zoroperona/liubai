import Foundation

public enum Horizon: String, Codable, CaseIterable, Identifiable {
    case current, medium, long
    public var id: String { rawValue }
    public var title: String {
        switch self { case .current: return "当前"; case .medium: return "中期"; case .long: return "长期" }
    }
    public var subtitle: String {
        switch self {
        case .current: return "专注眼前，完成一件就好。"
        case .medium: return "给接下来的日子，一点方向。"
        case .long: return "慢慢来，重要的事值得等待。"
        }
    }
}

public struct Subtask: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var completed = false
    public init(title: String) { self.title = title }
}

public struct Plan: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var notes = ""
    public var horizon: Horizon
    public var completed = false
    public var locked = false
    public var completedAt: Date?
    public var subtasks: [Subtask] = []
    public init(title: String, horizon: Horizon) {
        self.title = title
        self.horizon = horizon
    }
}

public struct PlanDocument: Codable, Equatable {
    public var version = 1
    public var plans: [Plan] = []
    public var mood = ""
    public var moodHighlights: [MoodHighlight] = []
    public init(plans: [Plan] = []) { self.plans = plans }

    private enum CodingKeys: String, CodingKey { case version, plans, mood, moodHighlights }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        plans = try values.decode([Plan].self, forKey: .plans)
        mood = try values.decodeIfPresent(String.self, forKey: .mood) ?? ""
        moodHighlights = try values.decodeIfPresent([MoodHighlight].self, forKey: .moodHighlights) ?? []
    }

    public var completedPlans: [Plan] {
        plans.enumerated().filter { $0.element.completed }.sorted {
            let left = $0.element.completedAt ?? .distantPast
            let right = $1.element.completedAt ?? .distantPast
            return left == right ? $0.offset < $1.offset : left > right
        }.map(\.element)
    }

    public mutating func setCompleted(_ id: UUID, _ completed: Bool, at date: Date = Date()) {
        guard let index = plans.firstIndex(where: { $0.id == id }), plans[index].completed != completed else { return }
        plans[index].completed = completed
        plans[index].completedAt = completed ? date : nil
    }

    /// Reorder only unlocked slots. Locked rows retain their exact tab index.
    @discardableResult
    public mutating func move(_ sourceID: UUID, to targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let source = plans.first(where: { $0.id == sourceID }),
              let target = plans.first(where: { $0.id == targetID }),
              source.horizon == target.horizon, !source.locked, !target.locked,
              !source.completed, !target.completed else { return false }
        let slots = plans.indices.filter { plans[$0].horizon == source.horizon && !plans[$0].locked && !plans[$0].completed }
        var movable = slots.map { plans[$0] }
        guard let from = movable.firstIndex(where: { $0.id == sourceID }),
              let to = movable.firstIndex(where: { $0.id == targetID }) else { return false }
        movable.insert(movable.remove(at: from), at: to)
        for (index, plan) in zip(slots, movable) { plans[index] = plan }
        return true
    }
}

public enum MoodColor: String, Codable, CaseIterable {
    case yellow, pink, green, blue, purple
}

/// UTF-16 offsets match NSTextView selections, including Chinese and emoji.
public struct MoodHighlight: Codable, Equatable {
    public var location: Int
    public var length: Int
    public var color: MoodColor
    public init(location: Int, length: Int, color: MoodColor) {
        self.location = location; self.length = length; self.color = color
    }
    public func isValid(for text: String) -> Bool {
        location >= 0 && length > 0 && location <= text.utf16.count && length <= text.utf16.count - location
    }
}

public enum DocumentError: LocalizedError {
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self { case .unsupportedVersion(let version): return "数据版本 \(version) 高于当前应用支持的版本。" }
    }
}

public enum PlanPersistence {
    public static func read(from url: URL) throws -> PlanDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return PlanDocument() }
        let document = try JSONDecoder().decode(PlanDocument.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw DocumentError.unsupportedVersion(document.version) }
        return document
    }
    public static func write(_ document: PlanDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}
