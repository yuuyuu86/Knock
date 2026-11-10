import AppKit
import SwiftUI

/// The small panel that confirms what a knock just did.
///
/// It is a borderless, click-through panel that floats above full-screen apps
/// and fades itself out, so it never steals focus from whatever you are doing.
@MainActor
final class HUD {

    static let shared = HUD()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let model = HUDModel()

    private init() {}

    func show(title: String, detail: String?, symbol: String, isFailure: Bool) {
        model.title = title
        model.detail = detail
        model.symbol = symbol
        model.isFailure = isFailure
        model.pulse += 1

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(isFailure ? 2400 : 1300))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 96),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 120))
    }
}

@MainActor
@Observable
private final class HUDModel {
    var title = ""
    var detail: String?
    var symbol = "bolt"
    var isFailure = false
    var pulse = 0
}

private struct HUDView: View {
    @Bindable var model: HUDModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(model.isFailure ? Color.orange.opacity(0.22) : Color.accentColor.opacity(0.22))
                Image(systemName: model.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(model.isFailure ? Color.orange : Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let detail = model.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 260, height: 96, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                }
        }
        .scaleEffect(1)
        .animation(.spring(duration: 0.3), value: model.pulse)
    }
}
