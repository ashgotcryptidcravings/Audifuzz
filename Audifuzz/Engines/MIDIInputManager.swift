import Combine
import CoreMIDI
import Foundation

struct MIDIDeviceChoice: Identifiable, Hashable {
    let id: Int
    let name: String
}

enum MIDIInputMessage {
    case noteOn(channel: Int, note: UInt8, velocity: UInt8)
    case noteOff(channel: Int, note: UInt8)
    case pitchBend(channel: Int, value: Int)
    case channelPressure(channel: Int, value: UInt8)
    case polyPressure(channel: Int, note: UInt8, value: UInt8)
    case controlChange(channel: Int, controller: UInt8, value: UInt8)
    case effectButton(index: Int, enabled: Bool)
    case allNotesOff
}

/// Owns the app's CoreMIDI input port and routes channel voice messages to the UI/audio layer.
final class MIDIInputManager: ObservableObject {
    static let shared = MIDIInputManager()

    @Published private(set) var devices: [MIDIDeviceChoice] = []
    @Published private(set) var connectionStatus = "MIDI input is off"
    @Published var isEnabled = UserDefaults.standard.bool(forKey: "midiInputEnabled") {
        didSet {
            save("midiInputEnabled", isEnabled)
            if !isEnabled {
                messages.send(.allNotesOff)
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
    @Published var effectKnobCCs = UserDefaults.standard.array(forKey: "midiEffectKnobCCs") as? [Int] ?? [20, 21, 22, 23] {
        didSet { save("midiEffectKnobCCs", effectKnobCCs) }
    }
    @Published var effectButtonCCs = UserDefaults.standard.array(forKey: "midiEffectButtonCCs") as? [Int] ?? [80, 81, 82, 83] {
        didSet { save("midiEffectButtonCCs", effectButtonCCs) }
    }
    @Published private(set) var learningEffectControl: (isButton: Bool, index: Int)?

    let messages = PassthroughSubject<MIDIInputMessage, Never>()

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
        learningEffectControl = (isButton, index)
    }

    func knobIndex(for controller: UInt8) -> Int? {
        effectKnobCCs.firstIndex(of: Int(controller))
    }

    private func updateConnections() {
        guard client != 0, inputPort != 0 else { return }
        if !connectedSources.isEmpty {
            messages.send(.allNotesOff)
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
            DispatchQueue.main.async { [weak self] in
                self?.handle(kind: kind, channel: channelNumber, first: first, second: second)
            }
            index += messageLength
        }
    }

    private func handle(kind: UInt8, channel: Int, first: UInt8, second: UInt8) {
        guard self.channel == 0 || self.channel == channel else { return }
        switch kind {
        case 0x80:
            emitNoteOff(channel: channel, note: first)
        case 0x90:
            if second == 0 { emitNoteOff(channel: channel, note: first) }
            else { messages.send(.noteOn(channel: channel, note: first, velocity: second)) }
        case 0xB0:
            if first == 120 || first == 123 {
                messages.send(.allNotesOff)
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
            if let learning = learningEffectControl {
                if learning.isButton {
                    var updated = effectButtonCCs
                    updated[learning.index] = Int(first)
                    effectButtonCCs = updated
                } else {
                    var updated = effectKnobCCs
                    updated[learning.index] = Int(first)
                    effectKnobCCs = updated
                }
                learningEffectControl = nil
                return
            }
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
        default:
            break
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
