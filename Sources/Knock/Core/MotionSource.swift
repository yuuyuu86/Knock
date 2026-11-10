import Foundation
import os

/// One accelerometer reading, in g, taken from the MacBook chassis.
///
/// Axes follow the built-in sensor's own frame while the notebook sits flat on a
/// desk: `x` runs across the chassis (left ↔ right), `y` runs front ↔ back and
/// `z` carries gravity (≈ -1.0 when the lid is open on a level surface).
struct MotionSample {
    var x: Double
    var y: Double
    var z: Double
    /// Seconds since boot, taken when the sample reached us.
    var time: TimeInterval
}

/// Anything that can push chassis motion into the detector.
protocol MotionSource: AnyObject {
    var onSample: ((MotionSample) -> Void)? { get set }
    /// Nil while the source is healthy, otherwise a human-readable reason.
    var failureReason: String? { get }
    func start(intervalMicroseconds: Int) throws
    func stop()
}

enum MotionSourceError: LocalizedError {
    case frameworkUnavailable
    case clientUnavailable
    case sensorNotFound

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable: "IOKit のイベントシステムに接続できませんでした。"
        case .clientUnavailable:    "HID イベントクライアントを作成できませんでした。"
        case .sensorNotFound:       "この Mac では内蔵の加速度センサーが見つかりませんでした。"
        }
    }
}

// MARK: - IOKit HID event system

/// Reads the built-in accelerometer that Apple silicon MacBooks expose on the
/// SPU HID transport (`Product == "accel"`, usage page 0xFF00).
///
/// The service is idle until a client asks for a report interval, so `start`
/// sets one and then listens on the shared event callback. Everything here goes
/// through `IOHIDEventSystemClient`, which is resolved at runtime — the symbols
/// are not in the public SDK headers.
final class HIDAccelerometerSource: MotionSource {

    var onSample: ((MotionSample) -> Void)?
    private(set) var failureReason: String?

    private var client: CFTypeRef?
    private var service: CFTypeRef?
    private var running = false
    private let log = Logger(subsystem: "app.knock", category: "motion")

    // Event type / field identifiers used by the HID event system.
    private static let accelerometerEventType: Int32 = 13
    private static func field(_ index: UInt32) -> UInt32 {
        UInt32(accelerometerEventType) << 16 | index
    }

    // MARK: dynamically resolved IOKit entry points

    private typealias FnCreate        = @convention(c) (CFAllocator?) -> CFTypeRef?
    private typealias FnCopyServices  = @convention(c) (CFTypeRef) -> CFArray?
    private typealias FnCopyProperty  = @convention(c) (CFTypeRef, CFString) -> CFTypeRef?
    private typealias FnSetProperty   = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    private typealias FnRegisterCB    = @convention(c) (
        CFTypeRef,
        @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, CFTypeRef?) -> Void,
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias FnUnregisterCB  = @convention(c) (CFTypeRef, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias FnSchedule      = @convention(c) (CFTypeRef, CFRunLoop, CFString) -> Void
    private typealias FnUnschedule    = @convention(c) (CFTypeRef, CFRunLoop, CFString) -> Void

    private struct IOKitBridge {
        let create: FnCreate
        let copyServices: FnCopyServices
        let copyProperty: FnCopyProperty
        let setProperty: FnSetProperty
        let registerCallback: FnRegisterCB
        let unregisterCallback: FnUnregisterCB
        let schedule: FnSchedule
        let unschedule: FnUnschedule

        init?() {
            guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
            func load<T>(_ name: String, as type: T.Type) -> T? {
                guard let pointer = dlsym(handle, name) else { return nil }
                return unsafeBitCast(pointer, to: type)
            }
            guard
                let create       = load("IOHIDEventSystemClientCreate", as: FnCreate.self),
                let services     = load("IOHIDEventSystemClientCopyServices", as: FnCopyServices.self),
                let copyProperty = load("IOHIDServiceClientCopyProperty", as: FnCopyProperty.self),
                let setProperty  = load("IOHIDServiceClientSetProperty", as: FnSetProperty.self),
                let register     = load("IOHIDEventSystemClientRegisterEventCallback", as: FnRegisterCB.self),
                let unregister   = load("IOHIDEventSystemClientUnregisterEventCallback", as: FnUnregisterCB.self),
                let schedule     = load("IOHIDEventSystemClientScheduleWithRunLoop", as: FnSchedule.self),
                let unschedule   = load("IOHIDEventSystemClientUnscheduleFromRunLoop", as: FnUnschedule.self)
            else { return nil }
            self.create = create
            self.copyServices = services
            self.copyProperty = copyProperty
            self.setProperty = setProperty
            self.registerCallback = register
            self.unregisterCallback = unregister
            self.schedule = schedule
            self.unschedule = unschedule
        }
    }

    private static let bridge = IOKitBridge()

    /// Reads `IOHIDEventGetFloatValue` lazily — the event callback needs it as a
    /// plain C function and cannot capture context.
    private static let eventFloat: (@convention(c) (CFTypeRef, UInt32) -> Double)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let pointer = dlsym(handle, "IOHIDEventGetFloatValue") else { return nil }
        return unsafeBitCast(pointer, to: (@convention(c) (CFTypeRef, UInt32) -> Double).self)
    }()

    private static let eventType: (@convention(c) (CFTypeRef) -> UInt32)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let pointer = dlsym(handle, "IOHIDEventGetType") else { return nil }
        return unsafeBitCast(pointer, to: (@convention(c) (CFTypeRef) -> UInt32).self)
    }()

    /// `true` when this machine exposes an accelerometer we can read.
    static var isSupported: Bool {
        guard let bridge, let client = bridge.create(kCFAllocatorDefault),
              let services = bridge.copyServices(client) as? [CFTypeRef] else { return false }
        return services.contains { (bridge.copyProperty($0, "Product" as CFString) as? String) == "accel" }
    }

    // MARK: lifecycle

    func start(intervalMicroseconds: Int) throws {
        guard !running else { return }
        guard let bridge = Self.bridge else {
            failureReason = MotionSourceError.frameworkUnavailable.localizedDescription
            throw MotionSourceError.frameworkUnavailable
        }
        guard let client = bridge.create(kCFAllocatorDefault) else {
            failureReason = MotionSourceError.clientUnavailable.localizedDescription
            throw MotionSourceError.clientUnavailable
        }
        guard let services = bridge.copyServices(client) as? [CFTypeRef],
              let sensor = services.first(where: { (bridge.copyProperty($0, "Product" as CFString) as? String) == "accel" })
        else {
            failureReason = MotionSourceError.sensorNotFound.localizedDescription
            throw MotionSourceError.sensorNotFound
        }

        self.client = client
        self.service = sensor

        // Asking for a report interval is what actually wakes the sensor up.
        _ = bridge.setProperty(sensor, "ReportInterval" as CFString, NSNumber(value: intervalMicroseconds))
        _ = bridge.setProperty(sensor, "BatchInterval" as CFString, NSNumber(value: 0))

        let context = Unmanaged.passUnretained(self).toOpaque()
        bridge.registerCallback(client, { target, _, _, event in
            guard let target, let event,
                  let readType = HIDAccelerometerSource.eventType,
                  let readFloat = HIDAccelerometerSource.eventFloat,
                  readType(event) == UInt32(HIDAccelerometerSource.accelerometerEventType)
            else { return }
            let source = Unmanaged<HIDAccelerometerSource>.fromOpaque(target).takeUnretainedValue()
            source.onSample?(MotionSample(
                x: readFloat(event, HIDAccelerometerSource.field(0)),
                y: readFloat(event, HIDAccelerometerSource.field(1)),
                z: readFloat(event, HIDAccelerometerSource.field(2)),
                time: ProcessInfo.processInfo.systemUptime))
        }, context, nil)

        bridge.schedule(client, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        running = true
        failureReason = nil
        log.info("accelerometer started at \(intervalMicroseconds, privacy: .public)µs")
    }

    func stop() {
        guard running, let bridge = Self.bridge, let client else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        bridge.unregisterCallback(client, context, nil, nil)
        bridge.unschedule(client, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.client = nil
        self.service = nil
        running = false
        log.info("accelerometer stopped")
    }

    deinit { stop() }
}

// MARK: - Simulated source

/// Stands in for the hardware on machines without a readable sensor, and backs
/// the "テスト" button in the sensitivity pane.
final class SimulatedMotionSource: MotionSource {
    var onSample: ((MotionSample) -> Void)?
    var failureReason: String? { nil }

    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 0.005
    private var pending: [(delay: TimeInterval, x: Double)] = []
    private var elapsed: TimeInterval = 0

    func start(intervalMicroseconds: Int) {
        stop()
        interval = TimeInterval(intervalMicroseconds) / 1_000_000
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        pending.removeAll()
        elapsed = 0
    }

    /// Queues an impulse that looks like a knock on the given side.
    func injectTap(side: KnockSide, strength: Double = 0.22, after delay: TimeInterval = 0) {
        pending.append((elapsed + delay, side == .left ? strength : -strength))
    }

    private func tick() {
        elapsed += interval
        var impulse = 0.0
        pending.removeAll { entry in
            guard elapsed >= entry.delay, elapsed < entry.delay + 0.012 else { return false }
            impulse = entry.x
            return true
        }
        let noise = { Double.random(in: -0.0016...0.0016) }
        onSample?(MotionSample(x: impulse + noise(),
                               y: noise(),
                               z: -0.986 + noise() + impulse * 0.4,
                               time: ProcessInfo.processInfo.systemUptime))
    }
}
