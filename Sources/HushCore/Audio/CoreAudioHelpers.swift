import AudioToolbox
import CoreAudio
import Foundation

public enum CoreAudioProcessLookupError: Error, LocalizedError, Equatable, Sendable {
    case invalidPID(pid_t)
    case lookupFailed(pid: pid_t, status: OSStatus)
    case processNotFound(pid_t)

    public var errorDescription: String? {
        switch self {
        case .invalidPID(let pid):
            return "Invalid process ID: \(pid)."
        case .lookupFailed(let pid, let status):
            return "Failed to find Core Audio process for PID \(pid) (error \(status))."
        case .processNotFound(let pid):
            return "PID \(pid) is not connected to Core Audio."
        }
    }
}

extension AudioObjectID {
    public static func readProcessObjectID(for pid: pid_t) throws -> AudioObjectID {
        guard pid > 0 else {
            throw CoreAudioProcessLookupError.invalidPID(pid)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutablePID = pid
        var processObjectID: AudioObjectID = .meetingUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &mutablePID) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID.meetingSystemObject,
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &size,
                &processObjectID
            )
        }

        guard status == noErr else {
            throw CoreAudioProcessLookupError.lookupFailed(pid: pid, status: status)
        }
        guard processObjectID.isMeetingValid else {
            throw CoreAudioProcessLookupError.processNotFound(pid)
        }
        return processObjectID
    }

    public static func readCurrentProcessObjectID() throws -> AudioObjectID {
        try readProcessObjectID(for: ProcessInfo.processInfo.processIdentifier)
    }
}

extension AudioObjectID {
    static let meetingSystemObject = AudioObjectID(kAudioObjectSystemObject)
    static let meetingUnknown = kAudioObjectUnknown

    var isMeetingValid: Bool { self != .meetingUnknown }
}

extension AudioObjectID {
    static func readMeetingDefaultSystemOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = .meetingUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID.meetingSystemObject,
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw MeetingAudioError.aggregateDeviceCreationFailed(status)
        }

        return deviceID
    }

    func readMeetingDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }

        guard status == noErr else {
            throw MeetingAudioError.aggregateDeviceCreationFailed(status)
        }

        return uid as String
    }

    func readMeetingTapStreamDescription() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(
            self,
            &address,
            0,
            nil,
            &size,
            &streamDescription
        )

        guard status == noErr else {
            throw MeetingAudioError.invalidTapFormat
        }

        return streamDescription
    }
}
