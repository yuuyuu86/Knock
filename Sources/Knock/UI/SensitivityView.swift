import SwiftUI

/// Tuning pane: live meter, sensitivity, multi-tap window, side calibration.
struct SensitivityView: View {
    @Bindable var settings: Settings
    @Bindable var engine: KnockEngine

    @State private var leaseTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("感度")
                        .font(.system(size: 20, weight: .semibold))
                    Text("タイピングやトラックパッドでは反応せず、狙ったノックだけを拾うよう調整します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                meter

                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        slider(title: "ノックの感度",
                               caption: "右へ動かすほど軽いタップで反応します。",
                               value: $settings.sensitivity,
                               range: 0...1,
                               labels: ("強く叩く", "軽く叩く")) {
                            Text(String(format: "%.0f%%", settings.sensitivity * 100))
                        }

                        Divider()

                        slider(title: "連続タップの待ち時間",
                               caption: "この時間が過ぎると、それまでの回数でジェスチャーが確定します。",
                               value: $settings.multiTapWindow,
                               range: 0.2...0.7,
                               labels: ("短い", "長い")) {
                            Text(String(format: "%.0f ms", settings.multiTapWindow * 1000))
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("タイピング中・クリック中は反応しない", isOn: $settings.suppressDuringTyping)
                        Toggle("左右の判定を入れ替える", isOn: $settings.invertSides)
                        Text("左を叩いたのに右側のアクションが動く場合はここをオンにします。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            Text("サンプリングレート")
                            Spacer()
                            Picker("", selection: $settings.sampleRate) {
                                Text("100 Hz").tag(100)
                                Text("200 Hz").tag(200)
                                Text("400 Hz").tag(400)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            .labelsHidden()
                        }
                        Text("高いほど素早い 3 回タップを取りこぼしにくくなります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                sideCalibrationBox
                calibration

                HStack {
                    Button("調整を初期値に戻す") {
                        settings.resetTuning()
                        engine.applySettings()
                        engine.restartSensor()
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
            }
            .padding(22)
        }
        .onChange(of: settings.sensitivity) { engine.applySettings() }
        .onChange(of: settings.multiTapWindow) { engine.applySettings() }
        .onChange(of: settings.invertSides) { engine.applySettings() }
        .onChange(of: settings.suppressDuringTyping) { engine.applySettings() }
        .onChange(of: settings.sampleRate) { engine.restartSensor() }
        .onAppear {
            engine.renewObservation()
            // Renewing on a timer means a missed onDisappear cannot leave the
            // engine permanently muted — the lease simply lapses.
            leaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in engine.renewObservation() }
            }
        }
        .onDisappear {
            leaseTimer?.invalidate()
            leaseTimer = nil
            engine.endObservation()
        }
    }

    // MARK: live meter

    private var meter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("センサー出力")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(engine.hasSensor ? "内蔵加速度センサー" : "シミュレーション（センサー非対応）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            WaveformView(samples: engine.energyHistory, threshold: thresholdForDisplay)
                .frame(height: 96)
                .background(.quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("水平の線がしきい値です。ノックしたときだけ波形がこの線を越えるように調整してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Mirrors `TapDetector.threshold` so the line matches what the detector uses.
    private var thresholdForDisplay: Double {
        let high = 0.020, low = 0.130
        return low + (high - low) * settings.sensitivity
    }


    // MARK: guided side calibration

    private var sideCalibrationBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("左右の判別を学習する")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if settings.sideCalibration.isCalibrated {
                        Label(settings.sideCalibration.quality, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("未学習")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("実測では、叩いた振動は特定の軸だけに出るわけではありませんでした。そこで左右それぞれを数回叩いて、この個体での違いを学習します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch engine.calibrationPhase {
                case .idle:
                    HStack {
                        Button(settings.sideCalibration.isCalibrated ? "学習をやり直す" : "学習を開始") {
                            engine.startSideCalibration()
                        }
                        if settings.sideCalibration.isCalibrated {
                            Button("消去") { settings.sideCalibration = .uncalibrated; engine.applySettings() }
                                .buttonStyle(.link)
                        }
                        Spacer()
                        if let result = engine.calibrationResult {
                            Text(String(format: "分離度 %.1f", result.separation))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                case .left, .right:
                    let isLeft = engine.calibrationPhase == .left
                    let collected = isLeft ? engine.calibrationLeftSamples.count : engine.calibrationRightSamples.count
                    VStack(alignment: .leading, spacing: 8) {
                        Label(isLeft ? "左側面を 5 回叩いてください" : "右側面を 5 回叩いてください",
                              systemImage: isLeft ? "arrow.left" : "arrow.right")
                            .font(.system(size: 13, weight: .medium))
                        ProgressView(value: Double(min(collected, 5)), total: 5)
                        Text("検出済み: \(collected) 回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(isLeft ? "次へ（右側面）" : "学習を完了") {
                                engine.advanceSideCalibration()
                            }
                            .disabled(collected < 3)
                            Button("中止") { engine.cancelSideCalibration() }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: calibration

    private var calibration: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("動作テスト")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("この画面ではアクションは実行されません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("MacBook の側面を叩くと、検出結果がここに並びます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if engine.calibrationImpulses.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                        Text("側面を叩いて試してください")
                    }
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(engine.calibrationImpulses.enumerated()), id: \.offset) { _, impulse in
                            VStack(spacing: 3) {
                                Image(systemName: impulse.side.symbol)
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "%.2f", impulse.strength))
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let gesture = engine.lastGesture {
                    Text("最後の判定: \(gesture.side.label) を \(gesture.count) 回")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !engine.hasSensor {
                    Divider()
                    HStack(spacing: 8) {
                        Text("疑似ノック:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(KnockSide.allCases) { side in
                            ForEach(1...3, id: \.self) { count in
                                Button("\(side.label)\(count)") { engine.simulate(side: side, count: count) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: building blocks

    private func slider<Value: View>(title: String,
                                     caption: String,
                                     value: Binding<Double>,
                                     range: ClosedRange<Double>,
                                     labels: (String, String),
                                     @ViewBuilder readout: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                readout()
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(labels.0).font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(labels.1).font(.caption2).foregroundStyle(.secondary)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Draws the recent high-passed energy plus the current threshold.
private struct WaveformView: View {
    let samples: [Double]
    let threshold: Double

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            // Keep the vertical scale steady unless a real knock blows past it.
            let ceiling = max(threshold * 1.6, (samples.max() ?? 0) * 1.1, 0.05)
            let step = size.width / CGFloat(samples.count - 1)

            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * step
                let y = size.height - CGFloat(min(sample / ceiling, 1)) * (size.height - 8) - 4
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }

            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)

            let thresholdY = size.height - CGFloat(min(threshold / ceiling, 1)) * (size.height - 8) - 4
            var line = Path()
            line.move(to: CGPoint(x: 0, y: thresholdY))
            line.addLine(to: CGPoint(x: size.width, y: thresholdY))
            context.stroke(line,
                           with: .color(.orange.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .padding(.horizontal, 2)
    }
}
