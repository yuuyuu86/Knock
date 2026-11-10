// 内蔵加速度センサーの生データを可視化する診断ツール。
// ビルド: swiftc -O Tools/SensorProbe.swift -o dist/knock-probe
import Foundation

// MARK: - IOKit の実行時解決（アプリ本体と同じ経路）

typealias Ref = CFTypeRef
let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)!
func sym<T>(_ name: String, _ type: T.Type) -> T {
    unsafeBitCast(dlsym(handle, name)!, to: type)
}

let create = sym("IOHIDEventSystemClientCreate", (@convention(c) (CFAllocator?) -> Ref?).self)
let copyServices = sym("IOHIDEventSystemClientCopyServices", (@convention(c) (Ref) -> CFArray?).self)
let copyProperty = sym("IOHIDServiceClientCopyProperty", (@convention(c) (Ref, CFString) -> CFTypeRef?).self)
let setProperty = sym("IOHIDServiceClientSetProperty", (@convention(c) (Ref, CFString, CFTypeRef) -> Bool).self)
let schedule = sym("IOHIDEventSystemClientScheduleWithRunLoop", (@convention(c) (Ref, CFRunLoop, CFString) -> Void).self)
let registerCallback = sym("IOHIDEventSystemClientRegisterEventCallback",
    (@convention(c) (Ref, @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Ref?) -> Void,
                     UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)
let eventType = sym("IOHIDEventGetType", (@convention(c) (Ref) -> UInt32).self)
let eventFloat = sym("IOHIDEventGetFloatValue", (@convention(c) (Ref, UInt32) -> Double).self)

let ACCEL: UInt32 = 13
func field(_ i: UInt32) -> UInt32 { ACCEL << 16 | i }

// MARK: - 状態

final class Probe {
    var lowPass = (x: 0.0, y: 0.0, z: 0.0)
    var primed = false
    var lastTime: TimeInterval = 0
    var sampleCount = 0
    var startTime = ProcessInfo.processInfo.systemUptime

    var noiseFloor = 0.0
    var peakHold = 0.0
    var lastPrint: TimeInterval = 0

    // ピーク検出
    var lastPeakTime: TimeInterval = -.infinity
    var onsetLeft = 0
    var onsetLateral = 0.0
    var onsetPeak = 0.0
    var onsetAxes = (x: 0.0, y: 0.0, z: 0.0)
    var events: [(t: TimeInterval, mag: Double, x: Double, y: Double, z: Double)] = []

    func consume(x: Double, y: Double, z: Double, time: TimeInterval) {
        sampleCount += 1
        guard primed else {
            lowPass = (x, y, z); lastTime = time; primed = true; return
        }
        let dt = max(0.0005, min(0.05, time - lastTime))
        lastTime = time

        let alpha = dt / (dt + 1.0 / (2 * .pi * 3.0))
        lowPass.x += alpha * (x - lowPass.x)
        lowPass.y += alpha * (y - lowPass.y)
        lowPass.z += alpha * (z - lowPass.z)

        let hx = x - lowPass.x, hy = y - lowPass.y, hz = z - lowPass.z
        let mag = (hx * hx + hy * hy + hz * hz).squareRoot()

        noiseFloor += 0.002 * (mag - noiseFloor)
        peakHold = max(peakHold, mag)

        // 立ち上がり測定中
        if onsetLeft > 0 {
            onsetLeft -= 1
            onsetLateral += hx
            if mag > onsetPeak { onsetPeak = mag; onsetAxes = (hx, hy, hz) }
            if onsetLeft == 0 {
                events.append((time - startTime, onsetPeak, onsetAxes.x, onsetAxes.y, onsetAxes.z))
                let side = onsetLateral >= 0 ? "左?" : "右?"
                let line = String(format: "  ★ 検出 t=%5.1fs  強さ=%.5f g  (x=%+.5f y=%+.5f z=%+.5f)  横方向→%@",
                                  time - startTime, onsetPeak, onsetAxes.x, onsetAxes.y, onsetAxes.z, side)
                print("\u{1B}[2K" + line)
                onsetPeak = 0; onsetLateral = 0
            }
            return
        }

        // 非常に低いしきい値で拾う（ノイズ床の4.5倍、最低0.0015g）
        let gate = max(0.0015, noiseFloor * 4.5)
        if mag > gate, time - lastPeakTime > 0.08 {
            lastPeakTime = time
            onsetLeft = max(2, Int(0.012 / dt))
            onsetLateral = hx
            onsetPeak = mag
            onsetAxes = (hx, hy, hz)
        }

        // ライブ表示
        if time - lastPrint > 0.08 {
            lastPrint = time
            let scale = 0.03
            let filled = min(40, Int(peakHold / scale * 40))
            let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: 40 - filled)
            let hz = Double(sampleCount) / max(0.001, time - startTime)
            print(String(format: "\u{1B}[2K\r%@ %.5f g  (床 %.5f · %.0f Hz)", bar, peakHold, noiseFloor, hz),
                  terminator: "")
            fflush(stdout)
            peakHold = 0
        }
    }
}

let probe = Probe()

// MARK: - 起動

guard let client = create(kCFAllocatorDefault),
      let services = copyServices(client) as? [Ref],
      let sensor = services.first(where: { (copyProperty($0, "Product" as CFString) as? String) == "accel" })
else {
    print("加速度センサーが見つかりませんでした。")
    exit(1)
}

let interval = 2500 // 400 Hz
_ = setProperty(sensor, "ReportInterval" as CFString, NSNumber(value: interval))
_ = setProperty(sensor, "BatchInterval" as CFString, NSNumber(value: 0))

registerCallback(client, { _, _, _, event in
    guard let event, eventType(event) == ACCEL else { return }
    probe.consume(x: eventFloat(event, field(0)),
                  y: eventFloat(event, field(1)),
                  z: eventFloat(event, field(2)),
                  time: ProcessInfo.processInfo.systemUptime)
}, nil, nil)
schedule(client, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

let duration = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 30 : 30

print("""

  Knock センサー診断 — 400 Hz で \(Int(duration)) 秒間記録します

  バーが現在の振動、★ が検出したノックです。
  いろいろな場所を叩いて、どこで反応するか試してください:

    1) 左手前のパームレスト      2) 右手前のパームレスト
    3) 本体の左側面              4) 本体の右側面
    5) キーボード奥の中央        6) 画面の枠

  （各 3 回ずつ、はっきり叩いてください）

""")

CFRunLoopRunInMode(.defaultMode, duration, false)

print("\u{1B}[2K\r")
print("─── 結果 ───")
print("サンプル数: \(probe.sampleCount)  実効レート: \(String(format: "%.0f", Double(probe.sampleCount) / duration)) Hz")
print("ノイズ床: \(String(format: "%.5f", probe.noiseFloor)) g")
print("検出イベント: \(probe.events.count) 件")
if probe.events.isEmpty {
    print("\n⚠️  1件も検出されませんでした。センサーは叩きの振動を拾えていません。")
} else {
    let strengths = probe.events.map(\.mag).sorted()
    print(String(format: "強さ: 最小 %.5f / 中央 %.5f / 最大 %.5f g",
                 strengths.first!, strengths[strengths.count / 2], strengths.last!))
    let lateralShare = probe.events.filter { abs($0.x) > abs($0.y) && abs($0.x) > abs($0.z) }.count
    print("x軸(横)が最大だったもの: \(lateralShare) / \(probe.events.count) 件")
    print("\n参考: 現在のアプリのしきい値は 感度50% で 0.075 g です。")
}
