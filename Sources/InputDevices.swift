import CoreAudio
import Foundation

/// The Mac's microphones, as Core Audio sees them, and the two knobs a
/// recording mode needs: which one to record from, and its input gain.
///
/// Exists because the system default is often the wrong mic for a lecture.
/// AirPods aim their mics at the wearer's mouth and suppress everything else,
/// so a professor across the room is removed as background noise before any
/// of this app's processing runs — turning voice processing off cannot undo
/// it. A lecture mode records from the built-in mic instead, whatever the
/// default is.
struct InputDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let builtIn: Bool

    /// A mode's `micDevice`: "" for the system default, "builtin" for this
    /// Mac's own mic, otherwise a device UID.
    static let systemDefault = ""
    static let builtInMic = "builtin"

    /// Pure, for `--selftest-modes`. A preference that matches nothing — the
    /// iPhone wandered off, the USB mic is unplugged — falls back to the
    /// default rather than refusing to record.
    static func resolve(_ preference: String, in devices: [InputDevice],
                        default fallback: AudioObjectID) -> AudioObjectID {
        switch preference {
        case systemDefault: return fallback
        case builtInMic:    return devices.first(where: \.builtIn)?.id ?? fallback
        default:            return devices.first { $0.uid == preference }?.id ?? fallback
        }
    }

    static func all() -> [InputDevice] {
        var size: UInt32 = 0
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &n) == noErr, n > 0 else { return nil }
            var transport: UInt32 = 0
            var tsize = UInt32(MemoryLayout<UInt32>.size)
            var taddr = address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &taddr, 0, nil, &tsize, &transport)
            return InputDevice(id: id,
                               uid: string(id, kAudioDevicePropertyDeviceUID) ?? "\(id)",
                               name: string(id, kAudioObjectPropertyName) ?? "Microphone \(id)",
                               builtIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
    }

    static func defaultInput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func name(of id: AudioObjectID) -> String {
        string(id, kAudioObjectPropertyName) ?? "unknown"
    }

    // MARK: - Input gain

    /// Nil when the device has no software gain — AirPods and most Bluetooth
    /// headsets do not, and silently ignore a set.
    static func inputVolume(_ id: AudioObjectID) -> Float32? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(kAudioDevicePropertyVolumeScalar,
                               scope: kAudioDevicePropertyScopeInput, element: element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    @discardableResult
    static func setInputVolume(_ id: AudioObjectID, _ value: Float32) -> Bool {
        var ok = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = address(kAudioDevicePropertyVolumeScalar,
                               scope: kAudioDevicePropertyScopeInput, element: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(id, &addr),
                  AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { continue }
            var v = value
            if AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
                ok = true
            }
        }
        return ok
    }

    // MARK: - Plumbing

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
