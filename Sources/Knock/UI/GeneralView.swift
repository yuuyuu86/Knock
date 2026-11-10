import SwiftUI
import AppKit

/// Permissions, startup behaviour, feedback and per-app exclusions.
struct GeneralView: View {
    @Bindable var settings: Settings
    @Bindable var engine: KnockEngine

    @State private var accessibilityGranted = Permissions.hasAccessibility
    @State private var permissionTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("一般")
                        .font(.system(size: 20, weight: .semibold))
                    Text("起動時の動作、フィードバック、アクセス権限を設定します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                permissionsBox
                behaviourBox
                exclusionsBox
                aboutBox
            }
            .padding(22)
        }
        .onAppear {
            accessibilityGranted = Permissions.hasAccessibility
            // The system grants access outside the app, so poll while visible.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                Task { @MainActor in accessibilityGranted = Permissions.hasAccessibility }
            }
        }
        .onDisappear {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    // MARK: permissions

    private var permissionsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    title: "アクセシビリティ",
                    detail: "キー送信とウインドウ操作に必要です。",
                    granted: accessibilityGranted,
                    action: {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    })

                Divider()

                permissionRow(
                    title: "加速度センサー",
                    detail: engine.hasSensor
                        ? "内蔵センサーを読み取れています。"
                        : "この Mac では読み取れませんでした。疑似ノックでのみ動作します。",
                    granted: engine.hasSensor,
                    action: nil)

                if case .noSensor(let reason) = engine.status {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(4)
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, action: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action, !granted {
                Button("許可する", action: action)
                    .controlSize(.small)
            }
        }
    }

    // MARK: behaviour

    private var behaviourBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("ログイン時に起動", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Divider()
                Toggle("実行内容を画面に表示する", isOn: $settings.showHUD)
                Toggle("実行時にサウンドを鳴らす", isOn: $settings.playSound)
            }
            .padding(4)
        }
    }

    // MARK: exclusions

    private var exclusionsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("このアプリでは反応しない")
                            .font(.system(size: 13, weight: .medium))
                        Text("ゲームや楽器アプリなど、誤検出しやすいアプリを登録します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("アプリを追加…") { addExcludedApp() }
                        .controlSize(.small)
                }

                if settings.excludedApps.isEmpty {
                    Text("登録されていません")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    ForEach(settings.excludedApps, id: \.self) { identifier in
                        HStack {
                            Text(displayName(for: identifier))
                                .font(.callout)
                            Text(identifier)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                settings.excludedApps.removeAll { $0 == identifier }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(4)
        }
    }

    private func displayName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !settings.excludedApps.contains(identifier)
        else { return }
        settings.excludedApps.append(identifier)
    }

    // MARK: about

    private var aboutBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Knock")
                    .font(.system(size: 13, weight: .semibold))
                Text("MacBook の側面へのノックを、macOS の操作や Apple ショートカットに変換します。検出も実行もこの Mac の中だけで完結し、外部へ送信されるデータはありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("バージョン \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(4)
        }
    }
}
