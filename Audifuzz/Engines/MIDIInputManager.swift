import Combine
import CoreMIDI
import Foundation

struct MIDIDeviceChoice: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct MIDIPressedNote: Identifiable, Equatable {
    var id: Int { channel * 128 + Int(note) }
    let channel: Int
    let note: UInt8
    let velocity: UInt8
}

struct MIDIActivityEvent: Identifiable {
    enum Kind: String {
        case noteOn, noteOff, pitchBend, controlChange, programChange, channelPressure, polyPressure
    }

    let id = UUID()
    let kind: Kind
    let channel: Int
    let data1: UInt8
    let data2: UInt8
    /// Time spent delivering CoreMIDI's callback onto the app's main queue.
    let mainQueueLatencyMilliseconds: Double
}

enum MIDIInputMessage {
    case noteOn(channel: Int, note: UInt8, velocity: UInt8)
    case noteOff(channel: Int, note: UInt8)
    case pitchBend(channel: Int, value: Int)
    case channelPressure(channel: Int, value: UInt8)
    case polyPressure(channel: Int, note: UInt8, value: UInt8)
    case controlChange(channel: Int, controller: UInt8, value: UInt8)
    case programChange(channel: Int, program: UInt8)
    case effectButton(index: Int, enabled: Bool)
    case allNotesOff
}

/// Owns the app's CoreMIDI input port and routes channel voice messages to the UI/audio layer.
final class MIDIInputManager: ObservableObject {
    static let shared = MIDIInputManager()

    @Published private(set) var devices: [MIDIDeviceChoice] = []
    @Published private(set) var connectionStatus = "MIDI input is off"
    @Published private(set) var activeNotes: [MIDIPressedNote] = []
    @Published private(set) var lastActivityDescription = "Waiting for MIDI input"
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "midiInputEnabled") {
        didSet {
            save("midiInputEnabled", isEnabled)
            if !isEnabled {
                messages.send(.allNotesOff)
                activeNotes.removeAll()
                sustainChannels.removeAll()
                deferredNoteOffs.removeAll()
            }
            updateConnections()
        }
    }
    @Published var selectedDeviceID = UserDefaults.standard.integer(forKey: "midiInputDeviceID") {
        didSet { save("midiInputDeviceID", selectedDeviceID); updateConnections() }
    }
    /// Zero means Omni; values 1 through 16 select a MIDI channel.
    @Published var channel = UserDefaults.standard.integer(forKey: "midiInputChannel") {
        didSet {
            save("midiInputChannel", channel)
            messages.send(.allNotesOff)
            sustainChannels.removeAll()
            deferredNoteOffs.removeAll()
        }
    }
    @Published var mode = UserDefaults.standard.integer(forKey: "midiInputMode") {
        didSet { save("midiInputMode", mode) }
    }
    @Published var selectedInstrument = UserDefaults.standard.integer(forKey: "midiSelectedInstrument") {
        didSet { save("midiSelectedInstrument", selectedInstrument) }
    }
    @Published var velocityControlsVolume = UserDefaults.standard.object(forKey: "midiVelocityControlsVolume") as? Bool ?? true {
        didSet { save("midiVelocityControlsVolume", velocityControlsVolume) }
    }
    @Published var pitchBendRange = UserDefaults.standard.integer(forKey: "midiPitchBendRange") == 0
        ? 2 : UserDefaults.standard.integer(forKey: "midiPitchBendRange") {
        didSet { save("midiPitchBendRange", pitchBendRange) }
    }
    @Published var sustainPedalEnabled = UserDefaults.standard.object(forKey: "midiSustainEnabled") as? Bool ?? true {
        didSet {
            save("midiSustainEnabled", sustainPedalEnabled)
            if !sustainPedalEnabled {
                for (channel, notes) in deferredNoteOffs {
                    for note in notes { messages.send(.noteOff(channel: channel, note: note)) }
                }
                deferredNoteOffs.removeAll()
                sustainChannels.removeAll()
            }
        }
    }
    @Published var effectsCCEnabled = UserDefaults.standard.bool(forKey: "midiEffectsCCEnabled") {
        didSet { save("midiEffectsCCEnabled", effectsCCEnabled) }
    }
    @Published var effectKnobCCs = UserDefaults.standard.array(forKey: "midiEffectKnobCCs") as? [Int] ?? [-1, -1, -1, -1] {
        didSet { save("midiEffectKnobCCs", effectKnobCCs) }
    }
    @Published private(set) var effectKnobMinimums = UserDefaults.standard.array(forKey: "midiEffectKnobMinimums") as? [Int] ?? [0, 0, 0, 0] {
        didSet { save("midiEffectKnobMinimums", effectKnobMinimums) }
    }
    @Published private(set) var effectKnobMaximums = UserDefaults.standard.array(forKey: "midiEffectKnobMaximums") as? [Int] ?? [127, 127, 127, 127] {
        didSet { save("midiEffectKnobMaximums", effectKnobMaximums) }
    }
    @Published var effectButtonCCs = UserDefaults.standard.array(forKey: "midiEffectButtonCCs") as? [Int] ?? [-1, -1, -1, -1] {
        didSet { save("midiEffectButtonCCs", effectButtonCCs) }
    }
    @Published var effectButtonProgramNumbers = UserDefaults.standard.array(forKey: "midiEffectButtonPrograms") as? [Int] ?? [-1, -1, -1, -1] {
        didSet { save("midiEffectButtonPrograms", effectButtonProgramNumbers) }
    }
    @Published private var toggledProgramButtons = [false, false, false, false]
    @Published private(set) var modulationWheelMinimum = UserDefaults.standard.object(forKey: "midiModWheelMinimum") as? Int ?? 0 {
        didSet { save("midiModWheelMinimum", modulationWheelMinimum) }
    }
    @Published private(set) var modulationWheelMaximum = UserDefaults.standard.object(forKey: "midiModWheelMaximum") as? Int ?? 127 {
        didSet { save("midiModWheelMaximum", modulationWheelMaximum) }
    }
    @Published private(set) var pitchWheelMinimum = UserDefaults.standard.object(forKey: "midiPitchWheelMinimum") as? Int ?? 0 {
        didSet { save("midiPitchWheelMinimum", pitchWheelMinimum) }
    }
    @Published private(set) var pitchWheelMaximum = UserDefaults.standard.object(forKey: "midiPitchWheelMaximum") as? Int ?? 16383 {
        didSet { save("midiPitchWheelMaximum", pitchWheelMaximum) }
    }
    @Published private(set) var mappingWarning: String?
    @Published private(set) var learningEffectControl: (isButton: Bool, index: Int)?

    let messages = PassthroughSubject<MIDIInputMessage, Never>()
    let activity = PassthroughSubject<MIDIActivityEvent, Never>()

    var currentDeviceName: String {
        if selectedDeviceID != 0 {
            return devices.first(where: { $0.id == selectedDeviceID })?.name ?? "Device unavailable"
        }
        let names = devices.filter { connectedSources.contains(MIDIEndpointRef($0.id)) }.map(\.name)
        if names.count == 1 { return names[0] }
        if names.count > 1 { return names.joined(separator: ", ") }
        return "No MIDI device connected"
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var sustainChannels = Set<Int>()
    private var deferredNoteOffs: [Int: Set<UInt8>] = [:]

    init() {
        let clientStatus = MIDIClientCreate("Audifuzz MIDI" as CFString, nil, nil, &client)
        guard clientStatus == noErr else {
            connectionStatus = "Could not create MIDI client (\(clientStatus))"
            return
        }
        let portStatus = MIDIInputPortCreateWithBlock(client, "Audifuzz MIDI Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.consume(packetList)
        }
        guard portStatus == noErr else {
            connectionStatus = "Could not create MIDI input port (\(portStatus))"
            return
        }
        refreshDevices()
        updateConnections()
    }

    func refreshDevices() {
        var found: [MIDIDeviceChoice] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            var unmanagedName: Unmanaged<CFString>?
            let result = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
            let name = result == noErr ? (unmanagedName?.takeRetainedValue() as String? ?? "MIDI Controller") : "MIDI Controller"
            found.append(MIDIDeviceChoice(id: Int(endpoint), name: name))
        }
        DispatchQueue.main.async {
            self.devices = found
            if self.selectedDeviceID != 0 && !found.contains(where: { $0.id == self.selectedDeviceID }) {
                self.selectedDeviceID = 0
            }
            self.updateConnections()
        }
    }

    func learnEffectControl(index: Int, isButton: Bool) {
        mappingWarning = nil
        learningEffectControl = (isButton, index)
    }

    func saveModulationRange(minimum: Int, maximum: Int) {
        guard maximum > minimum else { return }
        modulationWheelMinimum = min(127, max(0, minimum))
        modulationWheelMaximum = min(127, max(0, maximum))
    }

    func savePitchWheelRange(minimum: Int, maximum: Int) {
        guard maximum > minimum else { return }
        pitchWheelMinimum = min(16383, max(0, minimum))
        pitchWheelMaximum = min(16383, max(0, maximum))
    }

    func normalizedPitchWheelValue(_ value: Int) -> Int {
        let midpoint = 8192
        if value < midpoint {
            let range = midpoint - pitchWheelMinimum
            guard range > 0 else { return value }
            return midpoint - (midpoint - value) * midpoint / range
        }
        let range = pitchWheelMaximum - midpoint
        guard range > 0 else { return value }
        return midpoint + (value - midpoint) * (16383 - midpoint) / range
    }

    func resetTrainingCalibration() {
        effectKnobCCs = Array(repeating: -1, count: 4)
        effectKnobMinimums = Array(repeating: 0, count: 4)
        effectKnobMaximums = Array(repeating: 127, count: 4)
        effectButtonCCs = Array(repeating: -1, count: 4)
        effectButtonProgramNumbers = Array(repeating: -1, count: 4)
        modulationWheelMinimum = 0
        modulationWheelMaximum = 127
        pitchWheelMinimum = 0
        pitchWheelMaximum = 16383
        learningEffectControl = nil
        mappingWarning = nil
        effectsCCEnabled = false
        toggledProgramButtons = Array(repeating: false, count: 4)
    }

    func normalizedModulationValue(_ value: UInt8) -> UInt8 {
        let range = modulationWheelMaximum - modulationWheelMinimum
        guard range > 0 else { return value }
        let scaled = (Int(value) - modulationWheelMinimum) * 127 / range
        return UInt8(min(127, max(0, scaled)))
    }

    func knobIndex(for controller: UInt8) -> Int? {
        effectKnobCCs.firstIndex(of: Int(controller))
    }

    func normalizedKnobValue(index: Int, value: UInt8) -> UInt8 {
        guard effectKnobMinimums.indices.contains(index), effectKnobMaximums.indices.contains(index) else { return value }
        let lower = effectKnobMinimums[index]
        let upper = effectKnobMaximums[index]
        guard upper > lower else { return value }
        let normalized = (Int(value) - lower) * 127 / (upper - lower)
        return UInt8(min(127, max(0, normalized)))
    }

    func saveKnobRange(index: Int, minimum: Int, maximum: Int) {
        guard (0..<4).contains(index), maximum > minimum else { return }
        var minimums = effectKnobMinimums
        var maximums = effectKnobMaximums
        minimums[index] = min(127, max(0, minimum))
        maximums[index] = min(127, max(0, maximum))
        guard maximums[index] > minimums[index] else { return }
        effectKnobMinimums = minimums
        effectKnobMaximums = maximums
    }

    func resetEffectMappings() {
        effectKnobCCs = [-1, -1, -1, -1]
        effectKnobMinimums = [0, 0, 0, 0]
        effectKnobMaximums = [127, 127, 127, 127]
        effectButtonCCs = [-1, -1, -1, -1]
        effectButtonProgramNumbers = [-1, -1, -1, -1]
        toggledProgramButtons = [false, false, false, false]
        learningEffectControl = nil
    }

    private func updateConnections() {
        guard client != 0, inputPort != 0 else { return }
        if !connectedSources.isEmpty {
            messages.send(.allNotesOff)
            activeNotes.removeAll()
            sustainChannels.removeAll()
            deferredNoteOffs.removeAll()
        }
        for endpoint in connectedSources { MIDIPortDisconnectSource(inputPort, endpoint) }
        connectedSources.removeAll()
        guard isEnabled else {
            connectionStatus = "MIDI input is off"
            return
        }
        let sources = selectedDeviceID == 0
            ? devices.map { MIDIEndpointRef($0.id) }
            : devices.filter { $0.id == selectedDeviceID }.map { MIDIEndpointRef($0.id) }
        for source in sources where MIDIPortConnectSource(inputPort, source, nil) == noErr {
            connectedSources.append(source)
        }
        connectionStatus = connectedSources.isEmpty ? "No MIDI input connected" : "Listening to \(connectedSources.count == 1 ? "1 source" : "\(connectedSources.count) sources")"
    }

    private func consume(_ list: UnsafePointer<MIDIPacketList>) {
        let packetCount = Int(list.pointee.numPackets)
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else { return }
        var packet = UnsafeRawPointer(list).advanced(by: packetOffset).assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetCount {
            let value = packet.pointee
            let bytes = withUnsafeBytes(of: value.data) { Array($0.prefix(Int(value.length))) }
            parse(bytes)
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }

    private func parse(_ bytes: [UInt8]) {
        var index = 0
        while index + 1 < bytes.count {
            let status = bytes[index]
            let kind = status & 0xF0
            let channelNumber = Int(status & 0x0F) + 1
            if status >= 0xF0 { index += 1; continue }
            let messageLength = kind == 0xC0 || kind == 0xD0 ? 2 : 3
            guard index + messageLength <= bytes.count else { break }
            let first = bytes[index + 1]
            let second = messageLength == 3 ? bytes[index + 2] : 0
            let queuedAt = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                let queueDelay = max(0, (ProcessInfo.processInfo.systemUptime - queuedAt) * 1_000)
                self?.handle(kind: kind, channel: channelNumber, first: first, second: second,
                             mainQueueLatencyMilliseconds: queueDelay)
            }
            index += messageLength
        }
    }

    private func handle(kind: UInt8, channel: Int, first: UInt8, second: UInt8,
                        mainQueueLatencyMilliseconds: Double) {
        guard self.channel == 0 || self.channel == channel else { return }
        let activityKind: MIDIActivityEvent.Kind
        switch kind {
        case 0x80: activityKind = .noteOff
        case 0x90: activityKind = second == 0 ? .noteOff : .noteOn
        case 0xA0: activityKind = .polyPressure
        case 0xB0: activityKind = .controlChange
        case 0xC0: activityKind = .programChange
        case 0xD0: activityKind = .channelPressure
        case 0xE0: activityKind = .pitchBend
        default: return
        }

        var learnedControl = false
        if kind == 0xC0, let learning = learningEffectControl, learning.isButton {
            if let existing = effectButtonProgramNumbers.firstIndex(of: Int(first)), existing != learning.index {
                mappingWarning = "That program is already assigned to Button \(existing + 1). Choose a different button control."
            } else {
                var programs = effectButtonProgramNumbers
                var controllers = effectButtonCCs
                programs[learning.index] = Int(first)
                controllers[learning.index] = -1
                effectButtonProgramNumbers = programs
                effectButtonCCs = controllers
                learningEffectControl = nil
                mappingWarning = nil
                learnedControl = true
            }
        }
        if kind == 0xB0, let learning = learningEffectControl {
            let existingKnob = effectKnobCCs.firstIndex(of: Int(first))
            let existingButton = effectButtonCCs.firstIndex(of: Int(first))
            let conflictsWithKnob = existingKnob.map { !learning.isButton || $0 != learning.index } ?? false
            let conflictsWithButton = existingButton.map { !learning.isButton || $0 != learning.index } ?? false
            let alreadyAssignedElsewhere = conflictsWithKnob || conflictsWithButton
            if alreadyAssignedElsewhere {
                let role: String
                if let index = existingKnob { role = "Knob \(index + 1)" }
                else if let index = existingButton { role = "Button \(index + 1)" }
                else { role = "another control" }
                mappingWarning = "That control is already assigned to \(role). Move a different control."
            } else if learning.isButton {
                var updated = effectButtonCCs
                var programs = effectButtonProgramNumbers
                updated[learning.index] = Int(first)
                programs[learning.index] = -1
                effectButtonCCs = updated
                effectButtonProgramNumbers = programs
                learningEffectControl = nil
                mappingWarning = nil
                learnedControl = true
            } else {
                var updated = effectKnobCCs
                if updated[learning.index] != Int(first) {
                    var minimums = effectKnobMinimums
                    var maximums = effectKnobMaximums
                    minimums[learning.index] = 0
                    maximums[learning.index] = 127
                    effectKnobMinimums = minimums
                    effectKnobMaximums = maximums
                }
                updated[learning.index] = Int(first)
                effectKnobCCs = updated
                learningEffectControl = nil
                mappingWarning = nil
                learnedControl = true
            }
        }

        activity.send(MIDIActivityEvent(kind: activityKind, channel: channel, data1: first,
                                        data2: second,
                                        mainQueueLatencyMilliseconds: mainQueueLatencyMilliseconds))
        lastActivityDescription = activityDescription(kind: activityKind, first: first, second: second)
        switch kind {
        case 0x80:
            removeActiveNote(channel: channel, note: first)
            emitNoteOff(channel: channel, note: first)
        case 0x90:
            if second == 0 {
                removeActiveNote(channel: channel, note: first)
                emitNoteOff(channel: channel, note: first)
            } else {
                updateActiveNote(channel: channel, note: first, velocity: second)
                messages.send(.noteOn(channel: channel, note: first, velocity: second))
            }
        case 0xB0:
            if first == 120 || first == 123 {
                messages.send(.allNotesOff)
                activeNotes.removeAll()
                deferredNoteOffs[channel] = nil
                sustainChannels.remove(channel)
                return
            }
            if first == 64 && sustainPedalEnabled {
                if second >= 64 {
                    sustainChannels.insert(channel)
                } else if sustainChannels.remove(channel) != nil {
                    for note in deferredNoteOffs.removeValue(forKey: channel) ?? [] {
                        messages.send(.noteOff(channel: channel, note: note))
                    }
                }
            }
            if learnedControl { return }
            if let buttonIndex = effectButtonCCs.firstIndex(of: Int(first)) {
                messages.send(.effectButton(index: buttonIndex, enabled: second >= 64))
            }
            messages.send(.controlChange(channel: channel, controller: first, value: second))
        case 0xE0:
            messages.send(.pitchBend(channel: channel, value: Int(first) | (Int(second) << 7)))
        case 0xA0:
            messages.send(.polyPressure(channel: channel, note: first, value: second))
        case 0xD0:
            messages.send(.channelPressure(channel: channel, value: first))
        case 0xC0:
            if learnedControl { return }
            if let buttonIndex = effectButtonProgramNumbers.firstIndex(of: Int(first)) {
                toggledProgramButtons[buttonIndex].toggle()
                messages.send(.effectButton(index: buttonIndex, enabled: toggledProgramButtons[buttonIndex]))
            }
            messages.send(.programChange(channel: channel, program: first))
        default:
            break
        }
    }

    private func updateActiveNote(channel: Int, note: UInt8, velocity: UInt8) {
        let pressed = MIDIPressedNote(channel: channel, note: note, velocity: velocity)
        if let index = activeNotes.firstIndex(where: { $0.id == pressed.id }) {
            activeNotes[index] = pressed
        } else {
            activeNotes.append(pressed)
        }
    }

    private func removeActiveNote(channel: Int, note: UInt8) {
        activeNotes.removeAll { $0.channel == channel && $0.note == note }
    }

    private func activityDescription(kind: MIDIActivityEvent.Kind, first: UInt8, second: UInt8) -> String {
        switch kind {
        case .noteOn: return "Key \(first) · velocity \(second)"
        case .noteOff: return "Key \(first) released"
        case .pitchBend: return "Pitch bend · \(Int(first) | (Int(second) << 7))"
        case .controlChange:
            if let index = effectKnobCCs.firstIndex(of: Int(first)) {
                return "Knob \(index + 1) - Value \(second)"
            }
            if let index = effectButtonCCs.firstIndex(of: Int(first)) {
                return "Button \(index + 1) - Value \(second)"
            }
            if first == 1 { return "Mod Wheel - Value \(second)" }
            if first == 64 { return "Sustain Pedal - Value \(second)" }
            return "CC \(first) - Value \(second)"
        case .programChange:
            if let index = effectButtonProgramNumbers.firstIndex(of: Int(first)) {
                return "Button \(index + 1) - Program \(first)"
            }
            return "Program \(first)"
        case .channelPressure: return "Aftertouch · \(first)"
        case .polyPressure: return "Key pressure · \(second)"
        }
    }

    private func emitNoteOff(channel: Int, note: UInt8) {
        if sustainPedalEnabled && sustainChannels.contains(channel) {
            deferredNoteOffs[channel, default: []].insert(note)
        } else {
            messages.send(.noteOff(channel: channel, note: note))
        }
    }

    private func save<T>(_ key: String, _ value: T) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
