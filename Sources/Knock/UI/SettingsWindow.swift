import SwiftUI

/// The window behind "設定…" in the menu bar.
struct SettingsWindow: View {
    @Bindable var settings: Settings
    @Bindable var engine: KnockEngine

    enum Tab: String, CaseIterable, Identifiable {
        case map, sensitivity, general
        var id: String { rawValue }

        var title: String {
            switch self {
            case .map:         "ノックマップ"
            case .sensitivity: "感度"
            case .general:     "一般"
            }
        }

        var symbol: String {
            switch self {
            case .map:         "hand.tap"
            case .sensitivity: "waveform"
            case .general:     "gearshape"
            }
        }
    }

    @State private var tab: Tab = .map

    var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases) { item in
                content(for: item)
                    .tabItem { Label(item.title, systemImage: item.symbol) }
                    .tag(item)
            }
        }
        .frame(width: 640, height: 620)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        switch tab {
        case .map:         KnockMapView(settings: settings, engine: engine)
        case .sensitivity: SensitivityView(settings: settings, engine: engine)
        case .general:     GeneralView(settings: settings, engine: engine)
        }
    }
}
