import SwiftUI

/// The six slots: left and right side, one/two/three taps.
struct KnockMapView: View {
    @Bindable var settings: Settings
    @Bindable var engine: KnockEngine

    @State private var editing: SlotID?

    struct SlotID: Identifiable, Equatable {
        var side: KnockSide
        var count: Int
        var id: String { "\(side.rawValue)-\(count)" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(alignment: .top, spacing: 16) {
                    sidePanel(.left)
                    sidePanel(.right)
                }

                HStack {
                    Button("初期設定に戻す") { settings.resetBindings() }
                        .buttonStyle(.link)
                    Spacer()
                    Text("スロットをクリックしてアクションを選びます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
        }
        .sheet(item: $editing) { slot in
            ActionPickerView(
                action: Binding(
                    get: { settings.bindings[slot.side, slot.count] },
                    set: { settings.bindings[slot.side, slot.count] = $0 }),
                title: "\(slot.side.label) · \(slot.count) 回タップ")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ノックマップ")
                    .font(.system(size: 20, weight: .semibold))
                Text("側面を選び、回数を選び、起きることを選びます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(engine.status.isHealthy ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(engine.status.label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }

    private func sidePanel(_ side: KnockSide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: side.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(side.label)
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
            .foregroundStyle(.secondary)

            ForEach(1...3, id: \.self) { count in
                slotRow(side: side, count: count)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func slotRow(side: KnockSide, count: Int) -> some View {
        let action = settings.bindings[side, count]
        let isRecent = engine.lastGesture == KnockGesture(side: side, count: count)
            && (engine.lastGestureTime.map { Date.now.timeIntervalSince($0) < 1.2 } ?? false)

        return Button {
            editing = SlotID(side: side, count: count)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { _ in
                        Circle()
                            .fill(isRecent ? Color.accentColor : Color.primary.opacity(0.75))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) 回タップ")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(action.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(action.isConfigured ? .primary : .secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: action.kind.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isRecent ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isRecent ? Color.accentColor.opacity(0.7) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isRecent)
        .contextMenu {
            Button("いま実行して試す") { engine.preview(action) }
                .disabled(!action.isConfigured)
            Button("この割り当てを消す") {
                settings.bindings[side, count] = .empty
            }
        }
    }
}

/// Category list plus the actions inside it, with the parameter field for the
/// four actions that need one.
struct ActionPickerView: View {
    @Binding var action: KnockAction
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var category: ActionCategory
    @State private var draft: KnockAction

    init(action: Binding<KnockAction>, title: String) {
        self._action = action
        self.title = title
        self._draft = State(initialValue: action.wrappedValue)
        self._category = State(initialValue: action.wrappedValue.kind.category == .none
                               ? .clipboard
                               : action.wrappedValue.kind.category)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text("アクションを選択").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("割り当てなし") { draft = .empty }
                    .buttonStyle(.link)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                List(selection: $category) {
                    ForEach(ActionCategory.allCases.filter { $0 != .none }) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 210)

                Divider()

                List {
                    ForEach(category.actions) { kind in
                        Button {
                            draft.kind = kind
                            if kind.parameterPrompt == nil { draft.parameter = "" }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: kind.symbol)
                                    .frame(width: 18)
                                    .foregroundStyle(draft.kind == kind ? Color.accentColor : .secondary)
                                Text(kind.title)
                                Spacer()
                                if draft.kind == kind {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 300)
            }
            .frame(height: 320)

            if let prompt = draft.kind.parameterPrompt {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt).font(.caption).foregroundStyle(.secondary)
                    TextField("", text: $draft.parameter)
                        .textFieldStyle(.roundedBorder)
                    if draft.kind == .pressShortcut {
                        Text("修飾キーは cmd / shift / opt / ctrl、キーは英数字か space・tab・up などで指定します。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("キャンセル") { dismiss() }
                Spacer()
                Button("保存") {
                    action = draft
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.kind != .none && !draft.isConfigured)
            }
            .padding(16)
        }
        .frame(width: 560)
    }
}
