import AppKit
import SwiftUI
import PlanCore

private let moodMark = NSAttributedString.Key("PlanIslandMoodColor")

extension MoodColor {
    var title: String {
        switch self {
        case .yellow: return "黄色"; case .pink: return "粉色"; case .green: return "绿色"
        case .blue: return "蓝色"; case .purple: return "紫色"
        }
    }
    var nativeColor: NSColor {
        switch self {
        case .yellow: return NSColor(red: 0.98, green: 0.86, blue: 0.42, alpha: 0.55)
        case .pink: return NSColor(red: 0.96, green: 0.61, blue: 0.69, alpha: 0.45)
        case .green: return NSColor(red: 0.52, green: 0.78, blue: 0.53, alpha: 0.45)
        case .blue: return NSColor(red: 0.45, green: 0.71, blue: 0.94, alpha: 0.4)
        case .purple: return NSColor(red: 0.72, green: 0.58, blue: 0.91, alpha: 0.4)
        }
    }
}

final class MoodEditing: ObservableObject {
    weak var textView: NSTextView?
    @Published var hasSelection = false
    var save: ((String, [MoodHighlight]) -> Void)?

    static let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.22, alpha: 0.8)
    ]
    static func attributed(_ text: String, _ marks: [MoodHighlight]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: base)
        for mark in marks where mark.isValid(for: text) {
            result.addAttributes([.backgroundColor: mark.color.nativeColor, moodMark: mark.color.rawValue],
                                 range: NSRange(location: mark.location, length: mark.length))
        }
        return result
    }
    static func highlights(in value: NSAttributedString) -> [MoodHighlight] {
        var result: [MoodHighlight] = []
        value.enumerateAttribute(moodMark, in: NSRange(location: 0, length: value.length)) { value, range, _ in
            if let name = value as? String, let color = MoodColor(rawValue: name) {
                result.append(MoodHighlight(location: range.location, length: range.length, color: color))
            }
        }
        return result
    }
    func apply(_ color: MoodColor?) {
        guard let view = textView, view.isEditable, !view.hasMarkedText(), let storage = view.textStorage else { return }
        let range = view.selectedRange()
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        if let color {
            storage.addAttributes([.backgroundColor: color.nativeColor, moodMark: color.rawValue], range: range)
        } else {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(moodMark, range: range)
        }
        view.typingAttributes = Self.base
        persist()
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(range)
    }
    func persist() {
        guard let view = textView, !view.hasMarkedText(), let storage = view.textStorage else { return }
        save?(view.string, Self.highlights(in: storage))
    }
}

struct MoodEditor: View {
    @EnvironmentObject var store: PlanStore
    @StateObject private var editing = MoodEditing()
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                MoodTextView(text: store.document.mood, highlights: store.document.moodHighlights,
                             editable: store.canSave, editing: editing) { text, marks in
                    store.setMood(text, highlights: marks)
                }.frame(height: 48)
                if store.document.mood.isEmpty {
                    Text("此刻的心情，写给自己…").font(.system(size: 12))
                        .foregroundStyle(.secondary).padding(.top, 2).allowsHitTesting(false)
                }
            }
            HStack(spacing: 7) {
                Text("划重点").font(.system(size: 9)).foregroundStyle(.secondary)
                ForEach(MoodColor.allCases, id: \.rawValue) { color in
                    Button { editing.apply(color) } label: {
                        Circle().fill(Color(nsColor: color.nativeColor)).frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                    }.buttonStyle(.plain).help("选中文字后标记为\(color.title)").accessibilityLabel("\(color.title)高亮")
                }
                Button { editing.apply(nil) } label: {
                    Image(systemName: "eraser").font(.system(size: 11)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("清除选中文字的高亮")
                Spacer(minLength: 0)
                if !editing.hasSelection { Text("先选中文字").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }.disabled(!editing.hasSelection || !store.canSave)
        }
    }
}

private struct MoodTextView: NSViewRepresentable {
    let text: String
    let highlights: [MoodHighlight]
    let editable: Bool
    let editing: MoodEditing
    let save: (String, [MoodHighlight]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editing) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        view.drawsBackground = false
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticLinkDetectionEnabled = false
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("自己的心情，选中文字后可设置多色高亮")
        view.delegate = context.coordinator
        scroll.documentView = view
        editing.textView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        editing.save = save
        view.isEditable = editable
        guard !view.hasMarkedText() else { return }
        let desired = MoodEditing.attributed(text, highlights)
        if let storage = view.textStorage, !storage.isEqual(to: desired) {
            let selection = view.selectedRange()
            storage.setAttributedString(desired)
            let start = min(selection.location, storage.length)
            view.setSelectedRange(NSRange(location: start, length: min(selection.length, storage.length - start)))
        }
        view.typingAttributes = MoodEditing.base
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let editing: MoodEditing
        init(_ editing: MoodEditing) { self.editing = editing }
        func textDidChange(_ notification: Notification) { editing.persist() }
        func textViewDidChangeSelection(_ notification: Notification) {
            let selected = (editing.textView?.selectedRange().length ?? 0) > 0
            DispatchQueue.main.async { [weak self] in self?.editing.hasSelection = selected }
        }
    }
}
