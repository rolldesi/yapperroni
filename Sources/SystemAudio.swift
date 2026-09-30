import CoreAudio
import AudioToolbox
import Foundation

/// Records what the Mac is playing — a Teams call, a lecture in a browser —
/// straight off the output mix, before it reaches the speakers or headphones.
///
/// A Core Audio process tap (macOS 14.2+) on every process, wrapped in a
/// private aggregate device so an IO proc can read it. No virtual driver, no
/// Screen Recording grant; macOS asks once for "System Audio Recording".
///
/// Trap: when that grant is missing or denied, nothing fails. The tap runs and
/// delivers exact zeros, so the caller checks for a perfectly silent capture.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "yapperroni.systemaudio", qos: .userInitiated)
    private(set) var isRunning = false

    enum TapError: Error, CustomStringConvertible {
        case status(String, OSStatus)
        case format(String)
        var description: String {
            switch self {
            case .status(let what, let s): return "\(what) failed (OSStatus \(s))"
            case .format(let m): return "computer audio format unsupported: \(m)"
            }
        }
    }

    /// Creates the tap and returns its sample rate, so the caller can build a
    /// converter before the first buffer arrives. `run` starts the flow.
    func prepare() throws -> Double {
        stop()
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "Yapperroni"
        desc.isPrivate = true
        // Unmuted: the user keeps hearing the lecture while it is recorded.
        desc.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "create process tap")

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd), "read tap format")
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else {
            stop()
            throw TapError.format("id \(asbd.mFormatID) flags \(asbd.mFormatFlags) bits \(asbd.mBitsPerChannel)")
        }

        // The aggregate needs a real device for its clock: the current output.
        // ponytail: switching output mid-recording (AirPods connecting) leaves
        // the aggregate on the old clock device; rebuild on
        // kAudioHardwarePropertyDefaultOutputDevice changes if that bites.
        let outputUID = try SystemAudioTap.defaultOutputUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Yapperroni computer audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
                  "create aggregate device")
        Log.write(String(format: "audio   computer audio tap %gHz x%u via \"%@\"",
                         asbd.mSampleRate, asbd.mChannelsPerFrame, outputUID))
        return asbd.mSampleRate
    }

    /// `onSamples` gets mono float at the tap's rate, on a private queue.
    func run(_ onSamples: @escaping (UnsafePointer<Float>, Int) -> Void) throws {
        var mono: [Float] = []
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = abl.first, let p0 = first.mData else { return }
            // Interleaved arrives as one buffer of N channels; non-interleaved
            // as N buffers of one. Averaged either way — a stereo mix of a
            // call has none of a mic array's phase problems.
            if abl.count == 1 {
                let ch = max(1, Int(first.mNumberChannels))
                let frames = Int(first.mDataByteSize) / (4 * ch)
                let src = p0.assumingMemoryBound(to: Float.self)
                mono = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<ch { sum += src[f * ch + c] }
                    mono[f] = sum / Float(ch)
                }
            } else {
                let frames = Int(first.mDataByteSize) / 4
                mono = [Float](repeating: 0, count: frames)
                for b in abl {
                    guard let d = b.mData else { continue }
                    let src = d.assumingMemoryBound(to: Float.self)
                    for f in 0..<frames { mono[f] += src[f] }
                }
                let n = Float(abl.count)
                for f in 0..<frames { mono[f] /= n }
            }
            mono.withUnsafeBufferPointer { onSamples($0.baseAddress!, $0.count) }
        }, "create IO proc")
        try check(AudioDeviceStart(aggregateID, procID), "start aggregate device")
        isRunning = true
    }

    /// Idempotent. Tears down in reverse order of creation.
    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            stop()
            throw TapError.status(what, status)
        }
    }

    static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        guard s == noErr else { throw TapError.status("read default output", s) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        s = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid)
        guard s == noErr, let uid else { throw TapError.status("read output device UID", s) }
        return uid.takeRetainedValue() as String
    }
}
