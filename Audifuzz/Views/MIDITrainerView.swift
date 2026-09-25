import SwiftUI
import UniformTypeIdentifiers

struct MIDITrainerView: View {
    @ObservedObject var midi: MIDIInputManager
    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("defaultSampleRate") private var audioSampleRate: Double = 44100
    @AppStorage("bufferSize") private var audioBufferSize: Int = 512
    @AppStorage("safeMode") private var audioSafeMode = false

    @State private var stepIndex = 0
    @State private var velocities: [Int] = []
    @State private var noteStarts: [Int: TimeInterval] = [:]
    @State private var holdDurations: [Double] = []
    @State private var bendValues: [Int] = []
    @State private var modulationValues = Set<Int>()
    @State private var bendCurrentValue = 8192
    @State private var modulationCurrentValue = 0
    @State private var wheelCaptureStarted = false
    @State private var padNotes = Set<UInt8>()
    @State private var octaveDownBaseline: Int?
    @State private var octaveUpBaseline: Int?
    @State private var octaveDownShift: Int?
    @State private var octaveUpShift: Int?
    @State private var controllers = Set<UInt8>()
    @State private var calibratedKnobs = Set<Int>()
    @State private var knobMinimums = Array(repeating: 127, count: 4)
    @State private var knobMaximums = Array(repeating: 0, count: 4)
    @State private var knobValues = Array(repeating: 64, count: 4)
    @State private var knobLeftFlash = Array(repeating: false, count: 4)
    @State private var knobRightFlash = Array(repeating: false, count: 4)
    @State private var activeKnobIndex: Int?
    @State private var selectedKnobIndex = 0
    @State private var learnedButtons = Set<Int>()
    @State private var activeButtonIndex: Int?
    @State private var selectedButtonIndex = 0
    @State private var sustainValues: [Int] = []
    @State private var latencyValues: [Double] = []
    @State private var latencyActiveNotes = Set<Int>()
    @State private var skippedSteps = Set<Int>()
    @State private var trainingComplete = false
    @State private var isExportingMarkdown = false

    private let steps = [
        ("Keys · velocity & hold", "Play a few keys at soft and strong velocities. Hold at least one note for a couple of seconds, then release it."),
        ("Pitch-bend wheel", "Sweep the wheel to both physical stops a few times, then return it to center."),
        ("Modulation wheel", "Sweep the wheel to both physical stops a few times to measure its full travel."),
        ("Velocity pads", "Tap each of the eight pads. The trainer counts distinct note numbers it receives."),
        ("Octave Down button", "Play a middle key, release it, press Octave Down, then play the same physical key again. We check that the note moved down 12 semitones."),
        ("Octave Up button", "Play a middle key, release it, press Octave Up, then play the same physical key again. We check that the note moved up 12 semitones."),
        ("Knob assignments", "Choose a knob name, move its hardware control to both physical stops, then repeat for the remaining knobs."),
        ("Assignable button assignments", "Choose a button name, press the hardware button to assign it, then repeat for the remaining buttons."),
        ("Sustain pedal", "If a pedal is attached to the V25, press and release it. Otherwise skip this optional step."),
        ("MIDI response timing", "Tap keys or pads repeatedly. We measure CoreMIDI-to-main-thread delivery time, not acoustic speaker latency.")
    ]

    private var canContinue: Bool {
        guard midi.isEnabled else { return false }
        switch stepIndex {
        case 0: return velocities.count >= 3 && holdDurations.count >= 1
        case 1: return wheelCaptureStarted && (bendValues.min() ?? 8192) <= 512 && (bendValues.max() ?? 8192) >= 15871 && abs(bendCurrentValue - 8192) <= 512
        case 2: return wheelCaptureStarted && (modulationValues.min() ?? 64) <= 2 && (modulationValues.max() ?? 64) >= 125
        case 3: return padNotes.count >= 8
        case 4: return octaveDownShift == -12
        case 5: return octaveUpShift == 12
        case 6: return calibratedKnobs.count == 4
        case 7: return learnedButtons.count == 4
        case 8: return (sustainValues.min() ?? 64) < 64 && (sustainValues.max() ?? 0) >= 64
        default: return latencyValues.count >= 10
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trainingComplete ? "Training Summary" : "MIDI Controller Trainer").font(.title2.bold())
                    Text(midi.currentDeviceName).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { presentationMode.wrappedValue.dismiss() }
            }
            .padding()
            Divider()

            ScrollView {
                if trainingComplete {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Training complete", systemImage: "checkmark.seal.fill")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("Review the results or export a Markdown report.")
                            .foregroundColor(.secondary)
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack {
                                Text(step.0)
                                Spacer()
                                Text(trainingStepStatus(index))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(skippedSteps.contains(index) ? .secondary : (trainingStepPassed(index) ? .green : .orange))
                            }
                        }
                    }
                    .padding()
                    .card()
                    .frame(maxWidth: 760)
                    .padding()
                } else {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("STEP \(stepIndex + 1) OF \(steps.count)", systemImage: stepSymbol)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.accentColor)
                            Spacer()
                            Text("\(Int(Double(stepIndex + 1) / Double(steps.count) * 100))%")
                                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(stepIndex + 1), total: Double(steps.count))
                        Text(steps[stepIndex].0).font(.largeTitle.bold())
                        Text(stepInstruction)
                            .font(.body).foregroundColor(.secondary)
                    }
                    .padding(20)
                    .card()
                    .animation(.easeInOut(duration: 0.25), value: stepIndex)

                    if !midi.isEnabled {
                        Label("MIDI input is disabled. Enable it to begin this trainer.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Button("Enable MIDI Input") { midi.isEnabled = true }
                            .buttonStyle(.borderedProminent)
                    }

                    metrics
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .card()

                    if stepIndex == 1 || stepIndex == 2 {
                        wheelCalibration
                    }

                    if stepIndex == 4 || stepIndex == 5 {
                        octaveCalibration
                    }

                    if stepIndex == 6 {
                        knobCalibration
                    }

                    if stepIndex == 7 {
                        buttonCalibration
                    }

                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding()
                }
            }

            Divider()
            HStack {
                if trainingComplete {
                    Button("Export as Markdown") { isExportingMarkdown = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                } else {
                    Button("Back") { stepIndex = max(0, stepIndex - 1) }
                        .disabled(stepIndex == 0)
                    Spacer()
                    Text(stepProgress).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Skip Step") { advanceStep(skipping: true) }
                        .buttonStyle(.bordered)
                    Button(stepIndex == steps.count - 1 ? "Review Results" : "Next") {
                        advanceStep(skipping: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                }
            }
            .padding()
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 480)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        .onReceive(midi.activity) { event in
            // MIDIInputManager emits activity after applying any learned mapping.
            record(event)
        }
        .fileExporter(isPresented: $isExportingMarkdown,
                      document: MIDITrainerMarkdownDocument(text: markdownReport),
                      contentType: .plainText,
                      defaultFilename: "Audifuzz-MIDI-Training.md") { _ in }
    }

    @ViewBuilder
    private var metrics: some View {
        switch stepIndex {
        case 0:
            metric("Velocity samples", value: "\(velocities.count)")
            metric("Reported range", value: velocities.isEmpty ? "—" : "\(velocities.min()!)–\(velocities.max()!) / 127")
            metric("Average held", value: holdDurations.isEmpty ? "—" : String(format: "%.2f s", holdDurations.reduce(0, +) / Double(holdDurations.count)))
            Text("This measures MIDI velocity response, not physical force accuracy.")
                .font(.caption).foregroundColor(.secondary)
        case 1:
            metric("Pitch bend now", value: "\(bendCurrentValue) / 16383")
            metric("Captured stops", value: bendValues.isEmpty ? "—" : "\(bendValues.min()!)–\(bendValues.max()!)")
            Text(abs(bendCurrentValue - 8192) <= 512 ? "Wheel is centered. Ready to continue." : "Return the wheel to its center detent to continue.")
                .font(.caption).foregroundColor(abs(bendCurrentValue - 8192) <= 512 ? .green : .secondary)
        case 2:
            metric("Mod wheel now", value: "\(modulationCurrentValue) / 127")
            metric("Measured travel", value: modulationValues.isEmpty ? "—" : "\(modulationValues.min()!)–\(modulationValues.max()!) / 127")
            Text("The captured endpoints will scale the modulation wheel across its full control range.")
                .font(.caption).foregroundColor(.secondary)
        case 3:
            metric("Distinct pad/key notes", value: "\(padNotes.count) / 8")
            Text("The V25 sends these pads as MIDI notes by default; the V Editor can reassign them.")
                .font(.caption).foregroundColor(.secondary)
        case 4:
            metric("Baseline note", value: octaveDownBaseline.map(String.init) ?? "Play a key")
            metric("Note change", value: octaveDownShift.map { "\($0) semitones" } ?? "Press Octave Down, then replay that key")
        case 5:
            metric("Baseline note", value: octaveUpBaseline.map(String.init) ?? "Play a key")
            metric("Note change", value: octaveUpShift.map { "\($0) semitones" } ?? "Press Octave Up, then replay that key")
        case 6:
            metric("Knobs assigned", value: "\(calibratedKnobs.count) / 4")
            Text("Observed controller IDs: \(controllers.sorted().map(String.init).joined(separator: ", "))")
                .font(.caption.monospacedDigit()).foregroundColor(.secondary)
        case 7:
            metric("Buttons assigned", value: "\(learnedButtons.count) / 4")
            Text("Each CC identifier can be assigned to only one knob or button.")
                .font(.caption).foregroundColor(.secondary)
        case 8:
            metric("CC 64 readings", value: "\(sustainValues.count)")
            metric("Observed range", value: sustainValues.isEmpty ? "—" : "\(sustainValues.min()!)–\(sustainValues.max()!) / 127")
        default:
            let sorted = latencyValues.sorted()
            metric("Timing samples", value: "\(sorted.count) / 10")
            metric("Average app delivery", value: sorted.isEmpty ? "—" : String(format: "%.2f ms", sorted.reduce(0, +) / Double(sorted.count)))
            metric("Median · worst", value: sorted.isEmpty ? "—" : String(format: "%.2f · %.2f ms", sorted[sorted.count / 2], sorted.last!))
            metric("Editor audio settings", value: "\(effectiveAudioBufferFrames) frames · \(Int(audioSampleRate)) Hz")
            metric("One-buffer estimate", value: String(format: "%.2f ms", Double(effectiveAudioBufferFrames) / max(1, audioSampleRate) * 1_000))
            Text("The samples measure CoreMIDI-to-app delivery only. The buffer estimate reflects your configured sample rate, buffer size, and Safe Mode; it is not a speaker-latency measurement.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var stepProgress: String {
        switch stepIndex {
        case 0: return "\(velocities.count) strikes · \(holdDurations.count) release timings"
        case 1: return bendValues.isEmpty ? "Sweep to both stops, then center" : "\(bendValues.min()!)–\(bendValues.max()!) · return to center"
        case 2: return modulationValues.isEmpty ? "Sweep to both stops" : "\(modulationValues.min()!)–\(modulationValues.max()!) / 127"
        case 3: return "\(padNotes.count) distinct notes"
        case 4: return octaveDownShift == -12 ? "Octave shift confirmed" : "Check note IDs for a 12-semitone shift"
        case 5: return octaveUpShift == 12 ? "Octave shift confirmed" : "Check note IDs for a 12-semitone shift"
        case 6: return "\(calibratedKnobs.count) / 4 knobs calibrated"
        case 7: return "\(learnedButtons.count) / 4 buttons assigned"
        case 8: return "\(sustainValues.count) pedal readings"
        default: return "\(latencyValues.count) timing samples"
        }
    }

    private var stepInstruction: String {
        if stepIndex == 1 {
            return "A MIDI wheel reports its absolute position, so there is no locker-style clearing spin. Sweep it fully up and down to find both stops, then return pitch bend to center."
        }
        if stepIndex == 2 {
            return "A MIDI wheel reports its absolute position, so there is no locker-style clearing spin. Sweep it fully up and down to find both stops; the measured endpoints will scale its full range."
        }
        return steps[stepIndex].1
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private var wheelCalibration: some View {
        let isPitchBend = stepIndex == 1
        let current = isPitchBend ? bendCurrentValue : modulationCurrentValue
        let maximum = isPitchBend ? 16383 : 127
        let fraction = Double(current) / Double(maximum)
        let lowReached = isPitchBend ? (bendValues.min() ?? maximum) <= 512 : (modulationValues.min() ?? maximum) <= 2
        let highReached = isPitchBend ? (bendValues.max() ?? 0) >= 15871 : (modulationValues.max() ?? 0) >= 125

        return HStack(spacing: 28) {
            MIDIWheelPositionBar(value: fraction, centerDetent: isPitchBend)
                .frame(width: 88, height: 220)
            VStack(alignment: .leading, spacing: 12) {
                Label(isPitchBend ? "Pitch bend" : "Modulation wheel", systemImage: "arrow.up.and.down")
                    .font(.headline)
                HStack {
                    Label("Low stop", systemImage: lowReached ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(lowReached ? .green : .secondary)
                    Spacer()
                    Label("High stop", systemImage: highReached ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(highReached ? .green : .secondary)
                }
                .font(.caption.weight(.medium))
                Text("Current value: \(current) / \(maximum)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Button(wheelCaptureStarted ? "Restart full-range sweep" : "Begin full-range sweep") {
                    wheelCaptureStarted = true
                    if isPitchBend {
                        bendValues.removeAll()
                        bendCurrentValue = 8192
                    } else {
                        modulationValues.removeAll()
                        modulationCurrentValue = 0
                    }
                }
                .buttonStyle(.borderedProminent)
                if !wheelCaptureStarted {
                    Text("Start the test, sweep all the way to both stops, and let the indicator capture the extremes.")
                        .font(.caption).foregroundColor(.secondary)
                } else if isPitchBend && lowReached && highReached {
                    Text("Both ends captured. Return the wheel to its center detent.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .card()
    }

    private func advanceStep(skipping: Bool) {
        if skipping {
            skippedSteps.insert(stepIndex)
        } else {
            skippedSteps.remove(stepIndex)
            if stepIndex == 1, let low = bendValues.min(), let high = bendValues.max() {
                midi.savePitchWheelRange(minimum: low, maximum: high)
            }
            if stepIndex == 2, let low = modulationValues.min(), let high = modulationValues.max() {
                midi.saveModulationRange(minimum: low, maximum: high)
            }
            if stepIndex == 7 { midi.effectsCCEnabled = true }
        }

        if stepIndex == steps.count - 1 {
            trainingComplete = true
        } else {
            stepIndex += 1
            if stepIndex == 1 || stepIndex == 2 { wheelCaptureStarted = false }
        }
    }

    private func trainingStepPassed(_ index: Int) -> Bool {
        switch index {
        case 0: return velocities.count >= 3 && !holdDurations.isEmpty
        case 1: return (bendValues.min() ?? 8192) <= 512 && (bendValues.max() ?? 8192) >= 15871
        case 2: return (modulationValues.min() ?? 64) <= 2 && (modulationValues.max() ?? 64) >= 125
        case 3: return padNotes.count >= 8
        case 4: return octaveDownShift == -12
        case 5: return octaveUpShift == 12
        case 6: return calibratedKnobs.count == 4
        case 7: return learnedButtons.count == 4
        case 8: return (sustainValues.min() ?? 64) < 64 && (sustainValues.max() ?? 0) >= 64
        default: return latencyValues.count >= 10
        }
    }

    private func trainingStepStatus(_ index: Int) -> String {
        if skippedSteps.contains(index) { return "Skipped" }
        return trainingStepPassed(index) ? "Complete" : "Incomplete"
    }

    private var markdownReport: String {
        let date = ISO8601DateFormatter().string(from: Date())
        let bendRange = bendValues.isEmpty ? "Not captured" : "\(bendValues.min()!)–\(bendValues.max()!) / 16383"
        let modRange = modulationValues.isEmpty ? "Not captured" : "\(modulationValues.min()!)–\(modulationValues.max()!) / 127"
        let latencySorted = latencyValues.sorted()
        let latency = latencySorted.isEmpty ? "No samples" : String(format: "avg %.2f ms, median %.2f ms, max %.2f ms", latencySorted.reduce(0, +) / Double(latencySorted.count), latencySorted[latencySorted.count / 2], latencySorted.last!)
        let rows = steps.indices.map { index in
            "| \(steps[index].0) | \(trainingStepStatus(index)) | \(trainingStepDetail(index)) |"
        }.joined(separator: "\n")
        return """
        # Audifuzz MIDI Controller Training

        - **Device:** \(midi.currentDeviceName)
        - **Exported:** \(date)

        | Training step | Status | Results |
        |:--|:--|:--|
        \(rows)

        ## Calibration

        - **Pitch bend range:** \(bendRange)
        - **Modulation wheel range:** \(modRange)
        - **Editor audio buffer:** \(effectiveAudioBufferFrames) frames at \(Int(audioSampleRate)) Hz
        - **MIDI delivery timing:** \(latency)

        _Timing measures CoreMIDI-to-app delivery; it does not include speaker or acoustic latency._
        """
    }

    private func trainingStepDetail(_ index: Int) -> String {
        switch index {
        case 0: return "\(velocities.count) velocity readings; \(holdDurations.count) note holds"
        case 1: return bendValues.isEmpty ? "No range captured" : "\(bendValues.min()!)–\(bendValues.max()!) / 16383"
        case 2: return modulationValues.isEmpty ? "No range captured" : "\(modulationValues.min()!)–\(modulationValues.max()!) / 127"
        case 3: return "\(padNotes.count) distinct note numbers"
        case 4: return octaveDownShift.map { "\($0) semitones" } ?? "Not verified"
        case 5: return octaveUpShift.map { "\($0) semitones" } ?? "Not verified"
        case 6: return "\(calibratedKnobs.count) of 4 knobs calibrated"
        case 7: return "\(learnedButtons.count) of 4 buttons assigned"
        case 8: return sustainValues.isEmpty ? "Not measured" : "\(sustainValues.min()!)–\(sustainValues.max()!) / 127"
        default: return "\(latencyValues.count) samples"
        }
    }

    private var octaveCalibration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(stepIndex == 4 ? "Octave Down verification" : "Octave Up verification",
                  systemImage: "pianokeys")
                .font(.headline)
            Text("This checks the MIDI note number before and after the hardware button. Choose a middle key so neither end of the keyboard range limits the shift.")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 18) {
                Image(systemName: "arrow.down.to.line")
                    .foregroundColor(stepIndex == 4 && octaveDownShift == -12 ? .green : .secondary)
                Image(systemName: "arrow.up.to.line")
                    .foregroundColor(stepIndex == 5 && octaveUpShift == 12 ? .green : .secondary)
                Text("Uses distinct note identifiers; repeated CC reports cannot satisfy this check.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .card()
    }

    private var knobCalibration: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Knob travel calibration", systemImage: "dial.low.fill")
                    .font(.headline)
                Text("Select the control name, move that hardware knob to both physical stops, then capture its full travel range.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Picker("Assign this knob as", selection: $selectedKnobIndex) {
                ForEach(0..<4, id: \.self) { index in
                    Text("Knob \(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .disabled(activeKnobIndex != nil)

            let index = selectedKnobIndex
            HStack(spacing: 24) {
                KnobTravelDial(value: knobValues[index],
                               isCapturing: activeKnobIndex == index,
                               leftFlash: knobLeftFlash[index],
                               rightFlash: knobRightFlash[index])
                    .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Knob \(index + 1)").font(.title3.weight(.semibold))
                    Text(midi.effectKnobCCs[index] >= 0
                         ? "Assigned from MIDI CC \(midi.effectKnobCCs[index])"
                         : "No hardware control assigned yet")
                        .font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        Label("Min \(knobMinimums[index] <= knobMaximums[index] ? knobMinimums[index] : 0)",
                              systemImage: "arrow.left")
                            .foregroundColor(knobLeftFlash[index] ? .green : .secondary)
                        Spacer()
                        Label("Max \(knobMinimums[index] <= knobMaximums[index] ? knobMaximums[index] : 127)",
                              systemImage: "arrow.right")
                            .foregroundColor(knobRightFlash[index] ? .green : .secondary)
                    }
                    .font(.caption.monospacedDigit())
                    Button(knobButtonTitle(index)) { toggleKnobCapture(index) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!midi.isEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { knob in
                    Label("\(knob + 1)", systemImage: calibratedKnobs.contains(knob) ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.medium))
                        .foregroundColor(calibratedKnobs.contains(knob) ? .green : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            if let warning = midi.mappingWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
            }
        }
        .padding(18)
        .card()
    }

    private var buttonCalibration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Assignable button mapping", systemImage: "switch.2")
                .font(.headline)
            Text("Choose the app label, then press a physical assignable button. The trainer records its unique CC or Program Change identifier.")
                .font(.caption).foregroundColor(.secondary)
            Picker("Assign this button as", selection: $selectedButtonIndex) {
                ForEach(0..<4, id: \.self) { index in
                    Text("Button \(index + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .disabled(activeButtonIndex != nil)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Button \(selectedButtonIndex + 1)")
                        .font(.title3.weight(.semibold))
                    Text(buttonAssignmentDescription(selectedButtonIndex))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button(activeButtonIndex == selectedButtonIndex ? "Press a button…" :
                       (learnedButtons.contains(selectedButtonIndex) ? "Learn again" : "Learn button")) {
                    activeButtonIndex = selectedButtonIndex
                    midi.learnEffectControl(index: selectedButtonIndex, isButton: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!midi.isEnabled)
            }
            ForEach(0..<4, id: \.self) { index in
                HStack {
                    Image(systemName: learnedButtons.contains(index) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(learnedButtons.contains(index) ? .green : .secondary)
                    Text("Button \(index + 1)")
                    Spacer()
                    Text(buttonAssignmentDescription(index))
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
            }
            if let warning = midi.mappingWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
            }
        }
        .padding(18)
        .card()
    }

    private func knobButtonTitle(_ index: Int) -> String {
        if activeKnobIndex == index { return "Finish capture" }
        return calibratedKnobs.contains(index) ? "Recapture" : "Capture range"
    }

    private func buttonAssignmentDescription(_ index: Int) -> String {
        if midi.effectButtonCCs[index] >= 0 {
            return "Assigned from MIDI CC \(midi.effectButtonCCs[index])"
        }
        if midi.effectButtonProgramNumbers[index] >= 0 {
            return "Assigned from Program Change \(midi.effectButtonProgramNumbers[index])"
        }
        return "No hardware button assigned yet"
    }

    private func toggleKnobCapture(_ index: Int) {
        if activeKnobIndex == index {
            activeKnobIndex = nil
            guard knobMinimums[index] < knobMaximums[index] else { return }
            midi.saveKnobRange(index: index, minimum: knobMinimums[index], maximum: knobMaximums[index])
            calibratedKnobs.insert(index)
            return
        }
        activeKnobIndex = index
        knobMinimums[index] = 127
        knobMaximums[index] = 0
        controllers.removeAll()
        midi.learnEffectControl(index: index, isButton: false)
    }

    private func record(_ event: MIDIActivityEvent) {
        switch stepIndex {
        case 0:
            if event.kind == .noteOn {
                velocities.append(Int(event.data2))
                noteStarts[event.channel * 128 + Int(event.data1)] = ProcessInfo.processInfo.systemUptime
            } else if event.kind == .noteOff,
                      let started = noteStarts.removeValue(forKey: event.channel * 128 + Int(event.data1)) {
                holdDurations.append(ProcessInfo.processInfo.systemUptime - started)
            }
        case 1 where wheelCaptureStarted && event.kind == .pitchBend:
            bendCurrentValue = Int(event.data1) | (Int(event.data2) << 7)
            bendValues.append(bendCurrentValue)
        case 2 where wheelCaptureStarted && event.kind == .controlChange && event.data1 == 1:
            modulationCurrentValue = Int(event.data2)
            modulationValues.insert(modulationCurrentValue)
        case 3 where event.kind == .noteOn:
            padNotes.insert(event.data1)
        case 4 where event.kind == .noteOn:
            guard octaveDownShift != -12 else { return }
            let note = Int(event.data1)
            if let baseline = octaveDownBaseline {
                let change = note - baseline
                octaveDownShift = change
                if change != 0 { octaveDownBaseline = note }
            } else {
                octaveDownBaseline = note
            }
        case 5 where event.kind == .noteOn:
            guard octaveUpShift != 12 else { return }
            let note = Int(event.data1)
            if let baseline = octaveUpBaseline {
                let change = note - baseline
                octaveUpShift = change
                if change != 0 { octaveUpBaseline = note }
            } else {
                octaveUpBaseline = note
            }
        case 6:
            if event.kind == .controlChange {
                controllers.insert(event.data1)
                for index in 0..<4 where midi.effectKnobCCs[index] == Int(event.data1) {
                    let previous = knobValues[index]
                    let current = Int(event.data2)
                    knobValues[index] = current
                    if activeKnobIndex == index {
                        knobMinimums[index] = min(knobMinimums[index], current)
                        knobMaximums[index] = max(knobMaximums[index], current)
                        if previous > 2 && current <= 2 { flashKnobEndpoint(index, left: true) }
                        if previous < 125 && current >= 125 { flashKnobEndpoint(index, left: false) }
                    }
                }
                if let index = activeKnobIndex {
                    // The first CC may teach a new assignment; subsequent
                    // travel values are collected only from that knob's CC.
                    if midi.effectKnobCCs[index] == Int(event.data1) {
                        knobMinimums[index] = min(knobMinimums[index], Int(event.data2))
                        knobMaximums[index] = max(knobMaximums[index], Int(event.data2))
                    }
                }
            }
        case 7 where event.kind == .controlChange || event.kind == .programChange:
            if event.kind == .controlChange { controllers.insert(event.data1) }
            if let index = activeButtonIndex, midi.mappingWarning == nil,
               midi.effectButtonCCs[index] >= 0 || midi.effectButtonProgramNumbers[index] >= 0 {
                learnedButtons.insert(index)
                activeButtonIndex = nil
            }
        case 8 where event.kind == .controlChange && event.data1 == 64:
            sustainValues.append(Int(event.data2))
        case 9:
            let noteID = event.channel * 128 + Int(event.data1)
            if event.kind == .noteOn, latencyActiveNotes.insert(noteID).inserted {
                latencyValues.append(event.mainQueueLatencyMilliseconds)
                if latencyValues.count > 100 { latencyValues.removeFirst(latencyValues.count - 100) }
            } else if event.kind == .noteOff {
                latencyActiveNotes.remove(noteID)
            }
        default:
            break
        }
    }

    private var stepSymbol: String {
        ["pianokeys", "arrow.up.and.down.and.arrow.left.and.right", "waveform.path", "square.grid.3x3.fill",
         "arrow.down.to.line", "arrow.up.to.line", "dial.low.fill", "switch.2", "pedal.accelerator", "timer"].indices.contains(stepIndex)
            ? ["pianokeys", "arrow.up.and.down.and.arrow.left.and.right", "waveform.path", "square.grid.3x3.fill",
               "arrow.down.to.line", "arrow.up.to.line", "dial.low.fill", "switch.2", "pedal.accelerator", "timer"][stepIndex]
            : "pianokeys"
    }

    private var effectiveAudioBufferFrames: Int {
        audioSafeMode ? max(audioBufferSize * 2, 1024) : audioBufferSize
    }

    private func flashKnobEndpoint(_ index: Int, left: Bool) {
        var flashes = left ? knobLeftFlash : knobRightFlash
        flashes[index] = true
        if left { knobLeftFlash = flashes } else { knobRightFlash = flashes }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            var current = left ? knobLeftFlash : knobRightFlash
            current[index] = false
            if left { knobLeftFlash = current } else { knobRightFlash = current }
        }
    }
}

private struct MIDITrainerMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct MIDIWheelPositionBar: View {
    let value: Double
    let centerDetent: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("MAX").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            GeometryReader { geometry in
                let height = geometry.size.height
                let position = height * (1 - min(1, max(0, value)))
                let center = height / 2
                ZStack {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if centerDetent {
                        Rectangle().fill(Color.secondary.opacity(0.5))
                            .frame(width: 24, height: 1)
                            .position(x: geometry.size.width / 2, y: center)
                        Rectangle().fill(Color.accentColor.opacity(0.8))
                            .frame(width: 8, height: max(2, abs(position - center)))
                            .position(x: geometry.size.width / 2, y: (position + center) / 2)
                    } else {
                        Capsule().fill(Color.accentColor.opacity(0.8))
                            .frame(width: 8, height: max(2, height - position))
                            .position(x: geometry.size.width / 2, y: (position + height) / 2)
                    }
                    Capsule().fill(Color.white)
                        .frame(width: 36, height: 5)
                        .position(x: geometry.size.width / 2, y: position)
                }
                .animation(.linear(duration: 0.05), value: value)
            }
            .frame(width: 48)
            Text("MIN")
                .font(.caption2.weight(.semibold)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KnobTravelDial: View {
    let value: Int
    let isCapturing: Bool
    let leftFlash: Bool
    let rightFlash: Bool

    private var tint: Color {
        leftFlash || rightFlash ? .green : (isCapturing ? .accentColor : .secondary)
    }

    var body: some View {
        let progress = CGFloat(min(127, max(0, value))) / 127
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().fill(tint).frame(width: 8, height: 8)
                .offset(y: -51)
                .rotationEffect(.degrees(-135 + 270 * Double(progress)))
            Text("\(value)")
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .frame(width: 112, height: 112)
        .padding(8)
        .drawingGroup()
        .animation(.easeInOut(duration: 0.18), value: leftFlash)
        .animation(.easeInOut(duration: 0.18), value: rightFlash)
    }
}
