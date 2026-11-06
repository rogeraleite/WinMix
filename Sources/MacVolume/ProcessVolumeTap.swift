import CoreAudio
import Foundation

/// One tap and the private aggregate device playing it into one output device.
///
/// Each route has its own tap because destroying an aggregate stops its tap for every other
/// aggregate sharing it (seen on macOS 27.2: the survivor keeps running but reads silence).
private final class OutputRoute {
    let tapDescription: CATapDescription
    var tapID = AudioObjectID.unknown
    var aggregateID = AudioObjectID.unknown
    var ioProcID: AudioDeviceIOProcID?
    let startedAt = Date()
    /// Written by the IO thread; proves this route is actually reading the tap.
    let callbacks = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    init(tapDescription: CATapDescription) {
        self.tapDescription = tapDescription
        callbacks.initialize(to: 0)
    }

    deinit {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        if aggregateID != .unknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID) }
        callbacks.deallocate()
    }
}

/// Routes a set of processes' audio (usually one app and its helpers) through a Core Audio
/// process tap and a private aggregate device, applying a gain on its way to an output device.
///
/// The tap mutes the processes' normal output while we read it (`.mutedWhenTapped`),
/// so what you hear is only our gained copy. That mute lasts only while something reads the
/// tap, so `moveOutput` starts the new route before retiring the old one.
final class ProcessVolumeTap {
    struct Diagnostics {
        var outputDevice = ""
        var sampleRate: Double = 0
        var bufferFrames: UInt32 = 0
        var inputLatencyFrames: UInt32 = 0
        var outputLatencyFrames: UInt32 = 0
        var tapFormat = AudioStreamBasicDescription()
        var outputFormat = AudioStreamBasicDescription()

        func ms(_ frames: UInt32) -> Double { sampleRate > 0 ? Double(frames) / sampleRate * 1000 : 0 }

        /// Device-reported estimate, not an acoustic measurement: the tapped audio reaches
        /// us one IO buffer plus the input-side latency later than it would have played.
        var estimatedAddedDelayMs: Double { ms(bufferFrames + inputLatencyFrames) }

        var rows: [(String, String)] {
            [
                ("Output device", outputDevice),
                ("Tap format", tapFormat.summary),
                ("Output format", outputFormat.summary),
                ("IO buffer", "\(bufferFrames) frames (\(String(format: "%.1f", ms(bufferFrames))) ms)"),
                ("Input latency + safety", String(format: "%.1f ms", ms(inputLatencyFrames))),
                ("Output latency + safety", String(format: "%.1f ms", ms(outputLatencyFrames))),
                ("Est. added delay", String(format: "≈ %.1f ms", estimatedAddedDelayMs)),
            ]
        }
    }

    struct Meters {
        var inputPeak: Float = 0
        var outputPeak: Float = 0
        var callbacks = 0
        var inputChannels = 0
        var outputChannels = 0
        var inputFrames = 0
        var outputFrames = 0
    }

    /// State shared with the real-time IO thread. Aligned scalar reads/writes, no locks;
    /// good enough for the spike, to be replaced by proper atomics later.
    private struct SharedState {
        var targetGain: Float = 1
        var currentGain: Float = 1
        var meters = Meters()
    }

    let name: String
    private(set) var processIDs: [AudioObjectID]
    private(set) var diagnostics = Diagnostics()

    private let shared = UnsafeMutablePointer<SharedState>.allocate(capacity: 1)
    private var route: OutputRoute?
    private var retiringRoutes: [OutputRoute] = []
    private var lastCallbackCount = 0
    private(set) var outputUID: String?
    private(set) var routeGeneration = 0

    init(processIDs: [AudioObjectID], name: String) {
        self.processIDs = processIDs
        self.name = name
        shared.initialize(to: SharedState())
    }

    deinit {
        stop()
        shared.deinitialize(count: 1)
        shared.deallocate()
    }

    var gain: Float {
        get { shared.pointee.targetGain }
        set { shared.pointee.targetGain = max(0, newValue) }
    }

    /// Returns the meters accumulated since the last call and resets the peaks.
    func takeMeters() -> Meters {
        let meters = shared.pointee.meters
        shared.pointee.meters.inputPeak = 0
        shared.pointee.meters.outputPeak = 0
        return meters
    }

    /// Starts the tap, playing into the device with `outputUID` or else the default output.
    func start(outputUID: String? = nil) throws {
        shared.pointee.currentGain = shared.pointee.targetGain
        let uid = try outputUID ?? AudioObjectID.defaultOutputUID()
        route = try makeRoute(outputUID: uid)
        routeGeneration += 1
        self.outputUID = uid
    }

    /// Moves the running tap to another output device, or rebuilds its route on the same one.
    /// On failure the current route is left in place.
    func moveOutput(to uid: String) throws {
        guard route != nil else { return }
        let newRoute = try makeRoute(outputUID: uid)
        if let oldRoute = route {
            retiringRoutes.append(oldRoute)
            retire(oldRoute, onceRunning: newRoute)
        }
        route = newRoute
        routeGeneration += 1
        outputUID = uid
        lastCallbackCount = 0
    }

    /// Keeps the old route reading the tap until the new one has really started, so the app
    /// is never left unread (and so unmuted) in between. Gives up after 5 s: the device may be gone.
    private func retire(_ oldRoute: OutputRoute, onceRunning newRoute: OutputRoute, attempts: Int = 250) {
        guard newRoute.callbacks.pointee == 0, attempts > 0 else {
            retiringRoutes.removeAll { $0 === oldRoute }
            return
        }
        // Weak so that stopping the tap really stops its routes: their IO threads use `shared`,
        // which is freed with the tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self, weak oldRoute, weak newRoute] in
            guard let self, let oldRoute else { return }
            guard let newRoute else {
                self.retiringRoutes.removeAll { $0 === oldRoute }
                return
            }
            self.retire(oldRoute, onceRunning: newRoute, attempts: attempts - 1)
        }
    }

    /// True when the IO thread hasn't run since the last check. A new route gets a few seconds
    /// to start, since Bluetooth devices can be slow to open.
    func checkStalled() -> Bool {
        guard let route else { return false }
        let count = route.callbacks.pointee
        defer { lastCallbackCount = count }
        return count == lastCallbackCount && Date().timeIntervalSince(route.startedAt) > 5
    }

    /// Headless tests only: stops the IO thread without telling anyone, like a dead device would.
    func simulateStall() {
        if let route { AudioDeviceStop(route.aggregateID, route.ioProcID) }
    }

    private func makeRoute(outputUID: String) throws -> OutputRoute {
        guard let outputDevice = AudioObjectID.device(uid: outputUID) else {
            throw SpikeError("Output device \(outputUID) is not available")
        }
        let tap = CATapDescription(stereoMixdownOfProcesses: processIDs)
        tap.uuid = UUID()
        tap.name = "MacVolume tap (\(name))"
        tap.isPrivate = true
        tap.muteBehavior = .mutedWhenTapped
        // Anything thrown below tears down what was built so far, in the route's deinit.
        let route = OutputRoute(tapDescription: tap)
        try check(AudioHardwareCreateProcessTap(tap, &route.tapID), "Creating process tap")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacVolume (\(name))",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tap.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &route.aggregateID),
                  "Creating aggregate device")

        diagnostics = try readDiagnostics(route, outputDevice: outputDevice)
        // The render code treats samples as Float32; anything else would come out as loud noise.
        guard diagnostics.tapFormat.isFloat32, diagnostics.outputFormat.isFloat32 else {
            throw SpikeError("Unsupported format (tap: \(diagnostics.tapFormat.summary), output: \(diagnostics.outputFormat.summary))")
        }

        let state = shared
        let callbacks = route.callbacks
        try check(AudioDeviceCreateIOProcIDWithBlock(&route.ioProcID, route.aggregateID, nil) { _, input, _, output, _ in
            callbacks.pointee &+= 1
            ProcessVolumeTap.render(
                from: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                to: UnsafeMutableAudioBufferListPointer(output),
                state: state
            )
        }, "Creating IO proc")
        try check(AudioDeviceStart(route.aggregateID, route.ioProcID), "Starting aggregate device")
        return route
    }

    /// Changes which processes the running tap covers, e.g. when an app spawns a new helper.
    func setProcesses(_ ids: [AudioObjectID]) throws {
        guard let route else {
            processIDs = ids
            return
        }
        route.tapDescription.processes = ids
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // Core Audio takes a pointer to the object reference, like CF-typed properties.
        var description = route.tapDescription
        try withUnsafeMutablePointer(to: &description) { pointer in
            try check(AudioObjectSetPropertyData(route.tapID, &address, 0, nil,
                                                 UInt32(MemoryLayout<CATapDescription>.size), pointer),
                      "Updating tap processes")
        }
        processIDs = ids
    }

    func stop() {
        route = nil
        retiringRoutes.removeAll()
        outputUID = nil
    }

    private func readDiagnostics(_ route: OutputRoute, outputDevice: AudioObjectID) throws -> Diagnostics {
        let aggregateID = route.aggregateID
        func latency(_ scope: AudioObjectPropertyScope) throws -> UInt32 {
            try aggregateID.read(kAudioDevicePropertyLatency, scope: scope, initial: UInt32(0))
                + aggregateID.read(kAudioDevicePropertySafetyOffset, scope: scope, initial: UInt32(0))
        }
        let outputStreams = try aggregateID.readObjectList(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        guard let firstOutputStream = outputStreams.first else { throw SpikeError("Aggregate device has no output stream") }

        return Diagnostics(
            outputDevice: (try? outputDevice.readString(kAudioObjectPropertyName)) ?? "device \(outputDevice)",
            sampleRate: try aggregateID.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(0)),
            bufferFrames: try aggregateID.read(kAudioDevicePropertyBufferFrameSize, initial: UInt32(0)),
            inputLatencyFrames: try latency(kAudioObjectPropertyScopeInput),
            outputLatencyFrames: try latency(kAudioObjectPropertyScopeOutput),
            tapFormat: try route.tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()),
            outputFormat: try firstOutputStream.read(kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
        )
    }

    // MARK: - Real-time IO (no allocations, no locks)

    private static func render(from input: UnsafeMutableAudioBufferListPointer,
                               to output: UnsafeMutableAudioBufferListPointer,
                               state: UnsafeMutablePointer<SharedState>) {
        let startGain = state.pointee.currentGain
        let endGain = state.pointee.targetGain
        let isBoosting = startGain > 1 || endGain > 1
        var inputPeak: Float = 0
        var outputPeak: Float = 0
        var outputFrames = 0

        // The aggregate lists its output device's own input streams first (a USB headset's mic,
        // say) and the tap last, so only the last buffer is the app's audio.
        let tap = input.last
        let tapData = tap?.mData?.assumingMemoryBound(to: Float.self)
        let tapChannels = Int(tap?.mNumberChannels ?? 0)
        let tapFrames = tapChannels > 0 ? Int(tap?.mDataByteSize ?? 0) / (tapChannels * MemoryLayout<Float>.size) : 0
        // Mono outputs, such as AirPods during a call, get both channels rather than just the left.
        let mixToMono = tapChannels > 1 && output.reduce(0) { $0 + Int($1.mNumberChannels) } == 1

        var outputChannel = 0
        for buffer in output {
            let stride = Int(buffer.mNumberChannels)
            defer { outputChannel += stride }
            guard stride > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / (stride * MemoryLayout<Float>.size)
            outputFrames = frames

            for c in 0..<stride {
                // Output channel N plays tap channel N; extra output channels stay silent.
                let sourceChannel = outputChannel + c
                guard let tapData, mixToMono || sourceChannel < tapChannels else {
                    for f in 0..<frames { data[f * stride + c] = 0 }
                    continue
                }
                let count = min(frames, tapFrames)
                for f in 0..<count {
                    // Linear ramp across the buffer so slider moves don't click.
                    let gain = startGain + (endGain - startGain) * Float(f) / Float(count)
                    let frame = tapData + f * tapChannels
                    let sample = mixToMono ? (frame[0] + frame[1]) * 0.5 : frame[sourceChannel]
                    let out = isBoosting ? softClip(sample * gain) : sample * gain
                    data[f * stride + c] = out
                    inputPeak = max(inputPeak, abs(sample))
                    outputPeak = max(outputPeak, abs(out))
                }
                for f in count..<frames { data[f * stride + c] = 0 }
            }
        }

        state.pointee.currentGain = endGain
        state.pointee.meters.inputPeak = max(state.pointee.meters.inputPeak, inputPeak)
        state.pointee.meters.outputPeak = max(state.pointee.meters.outputPeak, outputPeak)
        state.pointee.meters.callbacks += 1
        state.pointee.meters.inputChannels = tapChannels
        state.pointee.meters.outputChannels = outputChannel
        state.pointee.meters.inputFrames = tapFrames
        state.pointee.meters.outputFrames = outputFrames
    }

    /// Leaves samples below 0.9 untouched and bends louder ones smoothly toward ±1, so boosted
    /// audio saturates gently instead of hard-clipping.
    @inline(__always)
    static func softClip(_ x: Float) -> Float {
        let threshold: Float = 0.9
        let magnitude = abs(x)
        guard magnitude > threshold else { return x }
        let headroom = 1 - threshold
        let shaped = threshold + headroom * tanh((magnitude - threshold) / headroom)
        return x < 0 ? -shaped : shaped
    }
}
