import AppKit
import SwiftUI
import Combine

enum DisplayMode: String { case panel, bubble, island }

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var mode: DisplayMode = .panel
    @Published private(set) var islandExpanded = false
    @Published var opacity: Double = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 0.82 {
        didSet { UserDefaults.standard.set(opacity, forKey: "opacity") }
    }
    private var panel: FloatingPanel!
    private var regularFrame = NSRect(x: 160, y: 200, width: 390, height: 560)
    private var screenObserver: NSObjectProtocol?
    private var trackingTimer: Timer?
    private var outsideSince: Date?
    private var dockScreen: NSScreen?
    private var changingFrame = false

    func start(store: PlanStore) {
        if let saved = UserDefaults.standard.string(forKey: "panelFrame") {
            regularFrame = NSRectFromString(saved)
        } else if let screen = NSScreen.main {
            regularFrame.origin = NSPoint(x: screen.visibleFrame.maxX - 430, y: screen.visibleFrame.midY - 280)
        }
        panel = FloatingPanel(contentRect: regularFrame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "留白 · 个人计划"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RootView().environmentObject(store).environmentObject(self))
        panel.minSize = NSSize(width: 350, height: 380)
        panel.maxSize = NSSize(width: 540, height: 1000)
        setFrame(clamped(regularFrame))
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.mode == .island { self.dockScreen = NSScreen.main; self.layoutIsland() }
            else { self.setFrame(self.clamped(self.panel.frame)) }
        }
        // Global pointer position needs no Accessibility permission. Only monitor our docked panel.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.mode == .island, self.islandExpanded else { return }
            let interacting = NSApp.keyWindow === self.panel && self.panel.firstResponder is NSTextView
            if self.panel.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) || interacting || NSEvent.pressedMouseButtons != 0 {
                self.outsideSince = nil
            } else if let since = self.outsideSince {
                if Date().timeIntervalSince(since) > 0.9 { self.collapseIsland() }
            } else { self.outsideSince = Date() }
        }
    }

    func showPanel() {
        mode = .panel
        islandExpanded = false
        panel.level = .floating
        panel.styleMask.insert(.resizable)
        panel.minSize = NSSize(width: 350, height: 380)
        panel.maxSize = NSSize(width: 540, height: 1000)
        setFrame(clamped(regularFrame))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showBubble() {
        rememberFrame()
        let previous = panel.frame
        mode = .bubble
        islandExpanded = false
        configureCompact()
        setFrame(clamped(NSRect(x: previous.maxX - 40, y: previous.maxY - 40, width: 40, height: 40)))
        panel.orderFrontRegardless()
    }

    func showIsland() {
        rememberFrame()
        dockScreen = panel.screen ?? NSScreen.main
        mode = .island
        islandExpanded = false
        configureCompact()
        layoutIsland()
        panel.orderFrontRegardless()
    }

    func expandIsland() {
        outsideSince = nil
        islandExpanded = true
        layoutIsland()
        panel.makeKeyAndOrderFront(nil)
    }
    func collapseIsland() {
        panel.makeFirstResponder(nil)
        islandExpanded = false
        outsideSince = nil
        layoutIsland()
    }
    private func configureCompact() {
        panel.styleMask.remove(.resizable)
        panel.minSize = NSSize(width: 1, height: 1)
        panel.maxSize = NSSize(width: 1000, height: 1200)
        panel.level = mode == .island ? .statusBar : .floating
    }
    private func layoutIsland() {
        guard let screen = dockScreen ?? NSScreen.main else { return }
        // Stay below the physical camera housing, which no application can draw over.
        let safeTop = screen.frame.maxY - screen.safeAreaInsets.top
        let size = islandExpanded ? NSSize(width: 390, height: min(560, screen.visibleFrame.height - 40)) : NSSize(width: 184, height: 32)
        setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: safeTop - size.height - (screen.safeAreaInsets.top > 0 ? 0 : 4), width: size.width, height: size.height))
    }
    private func rememberFrame() {
        if mode == .panel { regularFrame = panel.frame; UserDefaults.standard.set(NSStringFromRect(regularFrame), forKey: "panelFrame") }
    }
    private func setFrame(_ frame: NSRect) {
        changingFrame = true
        panel.setFrame(frame, display: true)
        changingFrame = false
    }
    private func clamped(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { left, right in
            let a = left.visibleFrame.intersection(frame), b = right.visibleFrame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return frame }
        var result = frame
        result.size.width = min(max(1, result.width), bounds.width)
        result.size.height = min(max(1, result.height), bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }
    func windowDidMove(_ notification: Notification) {
        guard !changingFrame else { return }
        rememberFrame()
    }
    func windowDidResize(_ notification: Notification) {
        guard !changingFrame else { return }
        rememberFrame()
    }
    func windowDidResignKey(_ notification: Notification) { panel.makeFirstResponder(nil) }
    func finishDragging() {
        if mode != .island { setFrame(clamped(panel.frame)); rememberFrame() }
    }

    func capture(to url: URL) throws {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try data.write(to: url)
    }

    var frameForTesting: NSRect { panel.frame }
}

struct WindowDragArea: NSViewRepresentable {
    var click: (() -> Void)? = nil
    var finished: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.click = click; view.finished = finished; return view }
    func updateNSView(_ view: DragView, context: Context) { view.click = click; view.finished = finished }
    final class DragView: NSView {
        var click: (() -> Void)?
        var finished: (() -> Void)?
        private var startPointer: NSPoint?
        private var startOrigin = NSPoint.zero
        private var didDrag = false
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startPointer = window.convertPoint(toScreen: event.locationInWindow)
            startOrigin = window.frame.origin
            didDrag = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let startPointer else { return }
            // Remember the gesture, even if it returns to its original position.
            didDrag = true
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: startOrigin.x + pointer.x - startPointer.x,
                                          y: startOrigin.y + pointer.y - startPointer.y))
        }
        override func mouseUp(with event: NSEvent) {
            guard startPointer != nil else { return }
            let shouldClick = !didDrag && bounds.contains(convert(event.locationInWindow, from: nil))
            startPointer = nil
            didDrag = false
            finished?()
            if shouldClick { click?() }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
