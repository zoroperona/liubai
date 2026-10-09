import SwiftUI
import PlanCore

final class PlanStore: ObservableObject {
    @Published private(set) var document = PlanDocument()
    @Published var selected: Horizon = .current
    @Published var expanded: Set<UUID> = []
    @Published var dragging: UUID?
    @Published var error: String?
    @Published private(set) var canSave = true
    private var undoDocument: PlanDocument?
    @Published private(set) var canUndo = false
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlanIsland/plans.json")
        do { document = try PlanPersistence.read(from: self.url) }
        catch {
            canSave = false
            self.error = "读取计划失败，原文件已保留。请从菜单打开数据文件夹，修复后重新启动。\n\(error.localizedDescription)"
        }
    }
    var visible: [Plan] { document.plans.filter { $0.horizon == selected } }
    var remaining: Int { document.plans.filter { !$0.completed }.count }
    func count(_ horizon: Horizon) -> Int { document.plans.filter { $0.horizon == horizon && !$0.completed }.count }

    private func commit(_ change: (inout PlanDocument) -> Void) {
        guard canSave else { return }
        var next = document
        change(&next)
        guard next != document else { return }
        do {
            try PlanPersistence.write(next, to: url)
            undoDocument = document
            canUndo = true
            document = next
        } catch { self.error = "保存失败，本次更改未应用：\(error.localizedDescription)" }
    }
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        commit { $0.plans.append(Plan(title: title, horizon: selected)) }
    }
    func setMood(_ text: String) { commit { $0.mood = text } }
    func update(_ id: UUID, _ change: (inout Plan) -> Void) {
        commit { doc in
            guard let index = doc.plans.firstIndex(where: { $0.id == id }) else { return }
            change(&doc.plans[index])
        }
    }
    func remove(_ id: UUID) {
        commit { $0.plans.removeAll { $0.id == id } }
        expanded.remove(id)
    }
    func move(_ source: UUID, to target: UUID) { commit { _ = $0.move(source, to: target) } }
    func transfer(_ id: UUID, to horizon: Horizon) {
        guard let plan = document.plans.first(where: { $0.id == id }), !plan.locked else { return }
        update(id) { $0.horizon = horizon }
    }
    func toggleExpanded(_ id: UUID) {
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }
    func undo() {
        guard let previous = undoDocument, canSave else { return }
        do {
            try PlanPersistence.write(previous, to: url)
            document = previous
            undoDocument = nil
            canUndo = false
        } catch { self.error = "撤销失败：\(error.localizedDescription)" }
    }
}
