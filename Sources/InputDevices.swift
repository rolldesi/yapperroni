import CoreAudio
import Foundation

/// The system's default microphone, by name, for the log's `audio input` line.
///
/// This used to choose a mic per mode and raise its gain. Every recording now
/// uses the system default: pinning a device is what broke lecture recordings
/// (see `Recorder.arm`). To record from another mic, pick it in macOS Sound
/// settings.
enum InputDevice {
    static func defaultInput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func name(of id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else {
            return "unknown"
        }
        return value.takeRetainedValue() as String
    }
}
