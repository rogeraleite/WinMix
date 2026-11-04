import CoreAudio
import Foundation

/// Routes a set of processes' audio (usually one app and its helpers) through a Core Audio
/// process tap and a private aggregate device, applying a gain on its way to the default
/// output device.
///
/// The tap mutes the processes' normal output while we read it (`.mutedWhenTapped`),
/// so what you hear is only our gained copy.
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
    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

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

    func start() throws {
        do {
            shared.pointee.currentGain = shared.pointee.targetGain

            let tap = CATapDescription(stereoMixdownOfProcesses: processIDs)
            tap.uuid = UUID()
            tap.name = "MacVolume tap (\(name))"
            tap.isPrivate = true
            tap.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(tap, &tapID), "Creating process tap")
            tapDescription = tap

            let outputDevice = try AudioObjectID.defaultOutputDevice()
            let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
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
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                      "Creating aggregate device")

            diagnostics = try readDiagnostics(outputDevice: outputDevice)
            // The render code treats samples as Float32; anything else would come out as loud noise.
            guard diagnostics.tapFormat.isFloat32, diagnostics.outputFormat.isFloat32 else {
                throw SpikeError("Unsupported format (tap: \(diagnostics.tapFormat.summary), output: \(diagnostics.outputFormat.summary))")
            }

            let state = shared
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                ProcessVolumeTap.render(
                    from: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                    to: UnsafeMutableAudioBufferListPointer(output),
                    state: state
                )
            }, "Creating IO proc")
            try check(AudioDeviceStart(aggregateID, ioProcID), "Starting aggregate device")
        } catch {
            stop()
            throw error
        }
    }

    /// Changes which processes the running tap covers, e.g. when an app spawns a new helper.
    func setProcesses(_ ids: [AudioObjectID]) throws {
        guard let tapDescription, tapID != .unknown else {
            processIDs = ids
            return
        }
        tapDescription.processes = ids
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        // Core Audio takes a pointer to the object reference, like CF-typed properties.
        var description = tapDescription
        try withUnsafeMutablePointer(to: &description) { pointer in
            try check(AudioObjectSetPropertyData(tapID, &address, 0, nil,
                                                 UInt32(MemoryLayout<CATapDescription>.size), pointer),
                      "Updating tap processes")
        }
        processIDs = ids
    }

    func stop() {
        if aggregateID != .unknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
        tapDescription = nil
    }

    private func readDiagnostics(outputDevice: AudioObjectID) throws -> Diagnostics {
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
            tapFormat: try tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()),
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
        var inputChannels = 0
        var inputFrames = 0
        var outputFrames = 0
        for buffer in input where buffer.mNumberChannels > 0 {
            inputChannels += Int(buffer.mNumberChannels)
            inputFrames = Int(buffer.mDataByteSize) / (Int(buffer.mNumberChannels) * MemoryLayout<Float>.size)
        }

        var outputChannel = 0
        for buffer in output {
            let stride = Int(buffer.mNumberChannels)
            defer { outputChannel += stride }
            guard stride > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / (stride * MemoryLayout<Float>.size)
            outputFrames = frames

            for c in 0..<stride {
                // Output channel N plays tap channel N; extra output channels stay silent.
                guard let source = channel(outputChannel + c, in: input) else {
                    for f in 0..<frames { data[f * stride + c] = 0 }
                    continue
                }
                let count = min(frames, source.frames)
                for f in 0..<count {
                    // Linear ramp across the buffer so slider moves don't click.
                    let gain = startGain + (endGain - startGain) * Float(f) / Float(count)
                    let sample = source.data[f * source.stride]
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
        state.pointee.meters.inputChannels = inputChannels
        state.pointee.meters.outputChannels = outputChannel
        state.pointee.meters.inputFrames = inputFrames
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

    private static func channel(_ index: Int, in list: UnsafeMutableAudioBufferListPointer)
        -> (data: UnsafeMutablePointer<Float>, stride: Int, frames: Int)? {
        var first = 0
        for buffer in list {
            let count = Int(buffer.mNumberChannels)
            if index < first + count {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return nil }
                return (data + (index - first), count, Int(buffer.mDataByteSize) / (count * MemoryLayout<Float>.size))
            }
            first += count
        }
        return nil
    }
}
