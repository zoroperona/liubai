import AppKit
import SwiftUI
import PlanCore

@main
struct PlanIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: PlanStore = {
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            return PlanStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("PlanIsland-smoke-\(UUID().uuidString)/plans.json"))
        }
        return PlanStore()
    }()
    private let controller = WindowController()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start(store: store)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "留白计划")
        statusItem.button?.toolTip = "留白 · 个人计划"
        let menu = NSMenu()
        add("打开计划面板", #selector(openPanel), "o", to: menu)
        add("收起为小圆点", #selector(bubble), "", to: menu)
        add("收纳到顶部", #selector(island), "", to: menu)
        menu.addItem(.separator())
        add("打开数据文件夹", #selector(openData), "", to: menu)
        menu.addItem(.separator())
        add("退出留白", #selector(quit), "q", to: menu)
        statusItem.menu = menu

        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        appItem.submenu = menu.copy() as? NSMenu
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        main.addItem(editItem)
        editItem.submenu = edit
        NSApp.mainMenu = main
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { runSmokeTest() }
    }
    private func add(_ title: String, _ selector: Selector, _ key: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc private func openPanel() { controller.showPanel() }
    @objc private func bubble() { controller.showBubble() }
    @objc private func island() { controller.showIsland() }
    @objc private func openData() {
        do {
            try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            NSWorkspace.shared.open(store.url.deletingLastPathComponent())
        } catch { store.error = error.localizedDescription }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func runSmokeTest() {
        verifyBubbleDrag()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PLAN_ISLAND_TEST_OUTPUT"] ?? "/tmp/PlanIsland-smoke")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        store.setMood("今天慢一点，也没关系。", highlights: [MoodHighlight(location: 2, length: 3, color: .yellow), MoodHighlight(location: 6, length: 4, color: .green)])
        store.add("整理今天的想法")
        store.add("留半小时，读几页书")
        store.add("散步，看看傍晚的天空")
        if let first = store.visible.first {
            store.update(first.id) {
                $0.notes = "把脑海里的事情写下来，一次只专注一件。"
                $0.subtasks = [Subtask(title: "整理笔记"), Subtask(title: "选出最重要的一件事")]
            }
            store.toggleExpanded(first.id)
        }
        if let last = store.visible.last { store.update(last.id) { $0.locked = true } }
        store.selected = .medium
        store.add("完成一个自己的小项目")
        store.selected = .long
        store.add("去一个一直想去的地方")
        store.selected = .current

        store.add("完成一次小小的整理")
        if let item = store.visible.last { store.setCompleted(item.id, true) }
        verifyMoodHighlights()
        var steps: [(String, () -> Void)] = []
        steps.append(("panel", { self.store.expanded.removeAll(); self.controller.showPanel() }))
        steps.append(("details", {
            if let first = self.store.visible.first { self.store.toggleExpanded(first.id) }
        }))
        steps.append(("completed", { self.store.showCompleted = true }))
        steps.append(("bubble", { self.store.showCompleted = false; self.controller.showBubble() }))
        steps.append(("island", { self.controller.showIsland() }))
        steps.append(("island-expanded", { self.controller.expandIsland() }))
        steps.append(("panel-restored", { self.controller.showPanel() }))
        func next(_ index: Int) {
            guard index < steps.count else {
                do {
                    let restored = try PlanPersistence.read(from: store.url)
                    guard restored == store.document else { throw NSError(domain: "SmokeTest", code: 1) }
                    try "PASS: click/drag separation; 7 window snapshots captured; fixture persisted and restored.\n".write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
                    try FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
                } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
                NSApp.terminate(nil)
                return
            }
            let (name, action) = steps[index]
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                do {
                    let frame = self.controller.frameForTesting
                    if name == "bubble" && (abs(frame.width - 40) > 1 || abs(frame.height - 40) > 1) { throw NSError(domain: "BubbleSize", code: 2) }
                    if name == "island" && abs(frame.width - 184) > 1 { throw NSError(domain: "IslandWidth", code: 3) }
                    try self.controller.capture(to: output.appendingPathComponent("\(name).png"))
                    next(index + 1)
                } catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next(0) }
    }

    private func verifyMoodHighlights() {
        let editor = MoodEditing()
        let view = NSTextView()
        editor.textView = view
        view.textStorage?.setAttributedString(MoodEditing.attributed("慢慢来🌿也很好", []))
        view.setSelectedRange(NSRange(location: 0, length: 3))
        editor.apply(.yellow)
        view.setSelectedRange(NSRange(location: 5, length: 3))
        editor.apply(.blue)
        let marks = MoodEditing.highlights(in: view.attributedString())
        guard marks.count == 2, marks[0].color == .yellow, marks[1].color == .blue else { exit(1) }
        view.textStorage?.insert(NSAttributedString(string: "今天", attributes: MoodEditing.base), at: 0)
        guard MoodEditing.highlights(in: view.attributedString()).first?.location == 2 else { exit(1) }
        view.setSelectedRange(NSRange(location: 2, length: 3))
        editor.apply(nil)
        guard MoodEditing.highlights(in: view.attributedString()).count == 1 else { exit(1) }
    }

    private func verifyBubbleDrag() {
        let testWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false
        defer { testWindow.close() }
        let view = WindowDragArea.DragView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        testWindow.contentView = view
        var clicks = 0
        view.click = { clicks += 1 }
        func event(_ type: NSEvent.EventType, _ x: CGFloat = 10) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 10), modifierFlags: [], timestamp: 0,
                              windowNumber: testWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func check(_ condition: Bool, _ message: String) {
            if !condition { fputs("Drag regression: \(message)\n", stderr); exit(1) }
        }
        view.mouseDown(with: event(.leftMouseDown))
        check(clicks == 0, "mouse down must not expand")
        view.mouseUp(with: event(.leftMouseUp))
        check(clicks == 1, "click must expand on release")
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseDragged(with: event(.leftMouseDragged, 40))
        check(abs(testWindow.frame.minX - 130) < 1, "drag must move the window")
        view.mouseUp(with: event(.leftMouseUp))
        check(clicks == 1, "drag must not expand")
        testWindow.setFrameOrigin(NSPoint(x: 100, y: 100))
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseDragged(with: event(.leftMouseDragged, 40))
        view.mouseDragged(with: event(.leftMouseDragged, -20))
        view.mouseUp(with: event(.leftMouseUp))
        check(abs(testWindow.frame.minX - 100) < 1 && clicks == 1, "dragging back to the start must not expand")
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseUp(with: event(.leftMouseUp))
        check(clicks == 2, "click must work after dragging")
    }
}
