import SwiftUI

/// Contents of the status-bar menu.
struct MenuBarView: View {
    @Bindable var settings: Settings
    @Bindable var engine: KnockEngine
    let openSettings: () -> Void

    var body: some View {
        Toggle("Knock を有効にする", isOn: Binding(
            get: { settings.isEnabled },
            set: { engine.setEnabled($0) }))

        Divider()

        Section("現在の割り当て") {
            ForEach(KnockSide.allCases) { side in
                ForEach(1...3, id: \.self) { count in
                    let action = settings.bindings[side, count]
                    Button("\(side.label) \(String(repeating: "・", count: count))  \(action.isConfigured ? action.displayName : "—")") {
                        engine.preview(action)
                    }
                    .disabled(!action.isConfigured)
                }
            }
        }

        Divider()

        Text("状態: \(engine.status.label) · \(Int(engine.sampleRateObserved)) Hz · 累計 \(engine.totalSamples)")
        Text(engine.detectorDiagnostics)
        Text("観測中に遮断 \(engine.blockedByObservation) · 実行 \(engine.actionsRun)")
        if let gesture = engine.lastGesture, let time = engine.lastGestureTime {
            Text("最後のノック: \(gesture.side.label) \(gesture.count)回 · \(time.formatted(date: .omitted, time: .standard))")
        }

        Button("設定…") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Knock を終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
