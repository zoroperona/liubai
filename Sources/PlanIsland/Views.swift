import SwiftUI
import UniformTypeIdentifiers
import PlanCore

private let ink = Color(red: 0.20, green: 0.24, blue: 0.22)
private let moss = Color(red: 0.32, green: 0.43, blue: 0.34)
private let paper = Color(red: 0.96, green: 0.96, blue: 0.92)
private let planDragType = UTType(exportedAs: "local.planisland.plan-id", conformingTo: .data)

struct RootView: View {
    @EnvironmentObject var store: PlanStore
    @EnvironmentObject var window: WindowController
    var body: some View {
        Group {
            if window.mode == .bubble { bubble }
            else if window.mode == .island && !window.islandExpanded { island }
            else { PlannerView() }
        }
        .preferredColorScheme(.light)
        .tint(moss)
        .alert("计划未能保存", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var bubble: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(ink.opacity(0.72)).padding(2)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(2)
            Image(systemName: "checkmark").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            WindowDragArea(click: { window.showPanel() }, finished: { window.finishDragging() })
        }
        .padding(3)
        .help("点击打开计划 · 拖动调整位置 · 右键切换模式")
        .accessibilityLabel("打开计划面板")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { window.showPanel() }
        .contextMenu {
            Button("打开计划面板") { window.showPanel() }
            Button("收纳到顶部") { window.showIsland() }
        }
    }
    private var island: some View {
        Button { window.expandIsland() } label: {
            HStack(spacing: 9) {
                Circle().fill(Color(red: 0.71, green: 0.82, blue: 0.58)).frame(width: 5, height: 5)
                Text("留白").font(.system(size: 11, weight: .medium))
                Spacer()
                Text(store.remaining == 0 ? "片刻从容" : "\(store.remaining) 件待办")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.62))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .help("点击展开计划")
        .contextMenu {
            Button("恢复悬浮面板") { window.showPanel() }
            Button("收起为小圆点") { window.showBubble() }
        }
    }
}

struct PlannerView: View {
    @EnvironmentObject var store: PlanStore
    @EnvironmentObject var window: WindowController
    @State private var newTitle = ""
    @State private var settings = false
    @FocusState private var adding: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            title
            if store.showCompleted {
                HStack {
                    Button { store.showCompleted = false } label: { Label("返回计划", systemImage: "chevron.left") }
                        .buttonStyle(.plain).font(.system(size: 11))
                    Spacer()
                    Text("已完成 · 最新在前").font(.system(size: 12, weight: .medium))
                }.padding(.horizontal, 24).padding(.bottom, 17)
            } else { tabs.padding(.horizontal, 22).padding(.bottom, 17) }
            HStack {
                Text(store.showCompleted ? "每一件完成的小事，都算数。" : store.selected.subtitle).font(.system(size: 11)).foregroundStyle(ink.opacity(0.5))
                Spacer()
                Text(store.showCompleted ? "\(store.completed.count) 件" : "\(store.visible.count) 件待办")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.opacity(0.45))
            }.padding(.horizontal, 24).padding(.bottom, 12)
            Rectangle().fill(ink.opacity(0.09)).frame(height: 1).padding(.horizontal, 22)
            if store.showCompleted { completedList }
            else if store.visible.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visible) { plan in
                            PlanRow(plan: plan)
                            Rectangle().fill(ink.opacity(0.065)).frame(height: 1).padding(.leading, 44)
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 7)
                }.frame(maxHeight: .infinity)
            }
            if !store.showCompleted { composer }
            footer
        }
        .foregroundStyle(ink)
        .background {
            ZStack { VisualEffect(); paper.opacity(window.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.7), lineWidth: 1))
        .onExitCommand {
            if store.showCompleted { store.showCompleted = false }
            else if window.mode == .island { window.collapseIsland() } else { window.showBubble() }
        }
        .onChange(of: store.selected) { _ in store.dragging = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(moss.opacity(0.8)).frame(width: 6, height: 6)
                Text("给时间留一点白").font(.system(size: 10)).tracking(1).foregroundStyle(ink.opacity(0.55))
            }.allowsHitTesting(false)
            Spacer()
            if window.mode == .island {
                iconButton("arrow.up.left.and.arrow.down.right", "恢复自由悬浮") { window.showPanel() }
                iconButton("chevron.up", "收起到顶部") { window.collapseIsland() }
            } else {
                iconButton("inset.filled.topthird.rectangle", "收纳到顶部") { window.showIsland() }
                iconButton("circle.inset.filled", "收起为小圆点") { window.showBubble() }
            }
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
        .background {
            if window.mode == .panel { WindowDragArea(finished: { window.finishDragging() }) }
        }
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("留白").font(.system(size: 30, weight: .light, design: .serif)).tracking(4)
                Text("个人计划").font(.system(size: 11)).foregroundStyle(ink.opacity(0.46))
                Spacer()
                Text(Date(), format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.opacity(0.48))
            }
            MoodEditor()
        }.padding(.horizontal, 24).padding(.top, 7).padding(.bottom, 20)
    }
    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(Array(Horizon.allCases.enumerated()), id: \.element.id) { index, horizon in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { store.selected = horizon }
                } label: {
                    HStack(spacing: 8) {
                        Text(horizon.title).font(.system(size: 12, weight: store.selected == horizon ? .semibold : .regular))
                        Text("\(store.count(horizon))").font(.system(size: 10, design: .monospaced)).opacity(0.6)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(store.selected == horizon ? Color.white.opacity(0.85) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(store.selected == horizon ? 0.04 : 0), radius: 3, y: 1)
                }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }.padding(4).background(ink.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "leaf").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(moss.opacity(0.65))
            Text("从一件小事开始").font(.system(size: 14, weight: .medium))
            Text("把想做的事记下来，留一些空间给生活。")
                .font(.system(size: 11)).foregroundStyle(ink.opacity(0.45))
            Button("写下第一件事") { adding = true }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(moss).padding(.top, 2)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 22)
    }
    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(moss)
            TextField("添加\(store.selected.title)计划…", text: $newTitle)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($adding)
                .onSubmit(addPlan)
            Button(action: addPlan) {
                Image(systemName: "return").font(.system(size: 11)).foregroundStyle(ink.opacity(0.4))
            }.buttonStyle(.plain).disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).help("添加计划（回车）")
        }
        .padding(13).background(.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ink.opacity(0.08)))
        .padding(.horizontal, 20).padding(.top, 10)
        .disabled(!store.canSave)
        .background(Button("") { adding = true }.keyboardShortcut("n", modifiers: .command).hidden())
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.canSave ? moss.opacity(0.6) : .red).frame(width: 4, height: 4)
            Text(store.canSave ? "自动保存在此 Mac" : "数据读取失败 · 已保护原文件")
                .font(.system(size: 9)).foregroundStyle(ink.opacity(0.43))
            Spacer()
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 11)) }
                .buttonStyle(.plain).disabled(!store.canUndo).help("撤销上次修改")
            Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 11)) }
                .buttonStyle(.plain).help("面板设置")
                .popover(isPresented: $settings, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("面板外观").font(.headline)
                        HStack { Text("背景浓度"); Spacer(); Text("\(Int(window.opacity * 100))%") }
                        Slider(value: $window.opacity, in: 0.15...1)
                        Text("拖动顶部空白处移动窗口\n拖动任务左侧把手调整顺序\n⌘1 / 2 / 3 切换分页 · ⌘N 新建\nEsc 收起面板 · 菜单栏随时找回")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(20).frame(width: 260)
                }
            Button { store.showCompleted.toggle(); store.dragging = nil } label: {
                Label("已完成 \(store.completed.count)", systemImage: "checkmark.circle")
                    .font(.system(size: 10)).foregroundStyle(store.showCompleted ? moss : ink.opacity(0.55))
            }.buttonStyle(.plain).help("查看所有分页的已完成任务，最新完成在前")
        }.foregroundStyle(ink.opacity(0.55)).padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 17)
    }
    private var completedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.completed.isEmpty {
                    Text("还没有已完成的计划，慢慢来。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(24)
                }
                ForEach(store.completed) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(moss)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(plan.title).font(.system(size: 13)).textSelection(.enabled)
                                HStack(spacing: 6) {
                                    Text(plan.horizon.title)
                                    if let date = plan.completedAt {
                                        Text(date, format: .dateTime.year().month().day().hour().minute())
                                    } else { Text("历史完成 · 时间未记录") }
                                }.font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("恢复") { store.setCompleted(plan.id, false) }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(moss)
                                .help("恢复到原来的分页")
                        }
                        if !plan.notes.isEmpty || !plan.subtasks.isEmpty {
                            DisclosureGroup("查看详情") {
                                VStack(alignment: .leading, spacing: 7) {
                                    if !plan.notes.isEmpty { Text(plan.notes).textSelection(.enabled) }
                                    ForEach(plan.subtasks) { task in
                                        Label(task.title, systemImage: task.completed ? "checkmark.square" : "square")
                                    }
                                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 25)
                        }
                    }.padding(.vertical, 14)
                    Divider().opacity(0.4)
                }
            }.padding(.horizontal, 24)
        }.frame(maxHeight: .infinity)
    }
    private func addPlan() {
        guard store.canSave else { return }
        store.add(newTitle)
        if store.error == nil { newTitle = "" }
    }
    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(ink.opacity(0.5)).frame(width: 22, height: 22) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct PlanRow: View {
    let plan: Plan
    @EnvironmentObject var store: PlanStore
    @State private var hovered = false
    @State private var targeted = false
    @State private var subtaskTitle = ""
    @State private var deleting = false
    private var isExpanded: Bool { store.expanded.contains(plan.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                handle.padding(.top, 3)
                Button { store.setCompleted(plan.id, !plan.completed) } label: {
                    Image(systemName: plan.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .light)).foregroundStyle(plan.completed ? moss : ink.opacity(0.28))
                }.buttonStyle(.plain).help(plan.completed ? "标记为未完成" : "完成计划").padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    TextField("计划名称", text: Binding(get: { plan.title }, set: { value in
                        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        store.update(plan.id) { $0.title = value }
                    }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .strikethrough(plan.completed).foregroundStyle(ink.opacity(plan.completed ? 0.4 : 0.95))
                    if !isExpanded && (!plan.notes.isEmpty || !plan.subtasks.isEmpty) {
                        HStack(spacing: 6) {
                            if !plan.subtasks.isEmpty {
                                Text("\(plan.subtasks.filter(\.completed).count)/\(plan.subtasks.count) 子任务")
                            }
                            if !plan.notes.isEmpty { Text(plan.notes).lineLimit(1) }
                        }.font(.system(size: 10)).foregroundStyle(ink.opacity(0.4))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.update(plan.id) { $0.locked.toggle() } } label: {
                    Image(systemName: plan.locked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10)).foregroundStyle(plan.locked ? moss : ink.opacity(hovered ? 0.35 : 0.13))
                        .frame(width: 20, height: 20)
                }.buttonStyle(.plain).help(plan.locked ? "解锁排序" : "锁定位置，禁止拖动")
                Button { withAnimation(.easeInOut(duration: 0.18)) { store.toggleExpanded(plan.id) } } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0)).frame(width: 18, height: 20)
                }.buttonStyle(.plain).foregroundStyle(ink.opacity(0.4)).help(isExpanded ? "收起详情" : "展开备注和子任务")
            }.padding(.vertical, 13).padding(.horizontal, 6)
            if isExpanded { details.padding(.leading, 45).padding(.trailing, 12).padding(.bottom, 15) }
        }
        .background(targeted && !plan.locked ? moss.opacity(0.12) : hovered ? .white.opacity(0.28) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
        .onDrop(of: [planDragType], isTargeted: $targeted) { providers in
            guard let provider = providers.first, !plan.locked else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: planDragType.identifier) { data, _ in
                guard let data, let text = String(data: data, encoding: .utf8), let source = UUID(uuidString: text) else { return }
                DispatchQueue.main.async {
                    guard store.dragging == source else { return }
                    store.move(source, to: plan.id)
                    store.dragging = nil
                }
            }
            return true
        }
        .contextMenu {
            Button(plan.locked ? "解锁位置" : "锁定位置") { store.update(plan.id) { $0.locked.toggle() } }
            Menu("移动到") {
                ForEach(Horizon.allCases.filter { $0 != plan.horizon }) { horizon in
                    Button(horizon.title) { store.transfer(plan.id, to: horizon) }
                }
            }.disabled(plan.locked)
            Divider()
            Button("删除计划…", role: .destructive) { deleting = true }
        }
        .alert("删除这项计划？", isPresented: $deleting) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { store.remove(plan.id) }
        } message: { Text("「\(plan.title)」及其子任务将一起删除，可在底部撤销。") }
    }

    @ViewBuilder private var handle: some View {
        if plan.locked {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(ink.opacity(0.08)).frame(width: 10, height: 15).help("此项已锁定位置")
        } else {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(ink.opacity(hovered ? 0.4 : 0.16)).frame(width: 10, height: 15)
                .contentShape(Rectangle()).onDrag {
                    store.dragging = plan.id
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: planDragType.identifier, visibility: .ownProcess) { completion in
                        completion(Data(plan.id.uuidString.utf8), nil)
                        return nil
                    }
                    return provider
                }.help("拖动调整顺序")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备注").font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.4))
            TextField("写下想法、步骤，或一个小提醒…", text: Binding(get: { plan.notes }, set: { value in store.update(plan.id) { $0.notes = value } }), axis: .vertical)
                .lineLimit(3...12).textFieldStyle(.plain).font(.system(size: 11)).lineSpacing(4)
                .padding(10).background(.white.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 8))
            ForEach(plan.subtasks) { subtask in
                HStack(alignment: .top, spacing: 7) {
                    Button { store.update(plan.id) { item in
                        if let index = item.subtasks.firstIndex(where: { $0.id == subtask.id }) { item.subtasks[index].completed.toggle() }
                    } } label: {
                        Image(systemName: subtask.completed ? "checkmark.square.fill" : "square")
                            .foregroundStyle(subtask.completed ? moss : ink.opacity(0.3))
                    }.buttonStyle(.plain).help(subtask.completed ? "标记子任务未完成" : "完成子任务")
                    TextField("子任务", text: Binding(get: { subtask.title }, set: { value in
                        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        store.update(plan.id) { item in
                            if let index = item.subtasks.firstIndex(where: { $0.id == subtask.id }) { item.subtasks[index].title = value }
                        }
                    }), axis: .vertical).textFieldStyle(.plain).strikethrough(subtask.completed).opacity(subtask.completed ? 0.45 : 1)
                    Button { store.update(plan.id) { $0.subtasks.removeAll { $0.id == subtask.id } } } label: {
                        Image(systemName: "xmark").font(.system(size: 8)).foregroundStyle(ink.opacity(0.3))
                    }.buttonStyle(.plain).help("删除子任务")
                }.font(.system(size: 11))
            }
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 9)).foregroundStyle(moss)
                TextField("添加子任务，回车保存", text: $subtaskTitle).textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit {
                        let title = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        store.update(plan.id) { $0.subtasks.append(Subtask(title: title)) }
                        if store.error == nil { subtaskTitle = "" }
                    }
            }
            HStack {
                if plan.locked { Label("位置已锁定", systemImage: "lock.fill").font(.system(size: 9)).foregroundStyle(moss.opacity(0.7)) }
                Spacer()
                Button("删除计划") { deleting = true }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(ink.opacity(0.4))
            }.padding(.top, 2)
        }
    }
}
