import SwiftUI

#if os(macOS)
import AppKit

/// Installs a native NSTouchBar on the window that hosts the SwiftUI content.
struct TouchBarControls: NSViewRepresentable {
    @ObservedObject var manager: AudioEngineManager
    @ObservedObject var lab: SoundLabEngine
    @ObservedObject var spatial: SpatialStage
    @Binding var page: Int
    @Binding var selectedVoiceIndex: Int
    @Binding var scopeMode: Int
    @Binding var selectedSpatialLocationID: UUID?
    @Binding var selectedLibraryURL: URL?
    var addSelectedSample: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TouchBarAnchorView {
        let view = TouchBarAnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: TouchBarAnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: nsView.window)
        context.coordinator.refreshTouchBar()
    }

    final class Coordinator: NSObject, NSTouchBarDelegate {
        var parent: TouchBarControls
        private weak var window: NSWindow?
        private var installedBar: NSTouchBar?
        private var installedSignature = ""

        init(_ parent: TouchBarControls) { self.parent = parent }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            refreshTouchBar()
        }

        func refreshTouchBar() {
            guard let window else { return }
            let selectedLocation = parent.selectedSpatialLocationID?.uuidString ?? "none"
            let signature = "\(parent.page)-\(parent.selectedLibraryURL != nil)-\(parent.selectedVoiceIndex)-\(selectedLocation)"
            if signature != installedSignature || installedBar == nil {
                installedSignature = signature
                let bar = NSTouchBar()
                bar.delegate = self
                bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.audifuzz.controls")
                bar.defaultItemIdentifiers = itemIdentifiers
                installedBar = bar
                window.touchBar = bar
            }
            synchronizeItemValues()
        }

        /// Mirrors values changed in the SwiftUI pages into existing native Touch Bar controls.
        private func synchronizeItemValues() {
            guard let bar = installedBar else { return }

            if let button = customButton(in: bar, identifier: .playPause) {
                let title = isPlaying ? "Pause" : "Play"
                button.title = title
                button.image = NSImage(systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
                                       accessibilityDescription: title)
            }

            if let button = customButton(in: bar, identifier: .spatialToggle) {
                let title = parent.spatial.isEnabled ? "Spatial On" : "Spatial Off"
                button.title = title
                button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                       accessibilityDescription: title)
            }

            if let item = bar.item(forIdentifier: .scopeMode) as? NSCustomTouchBarItem,
               let control = item.view as? NSSegmentedControl {
                control.selectedSegment = min(max(parent.scopeMode, 0), 2)
            }

            setSlider(.waveShape, in: bar, value: selectedWave)
            setSlider(.spatialHeight, in: bar, value: Double(selectedLocation?.elevation ?? 0))
            setSlider(.spatialReverb, in: bar, value: Double(parent.spatial.reverb))
            for (index, value) in selectedVoiceValues.enumerated() {
                setSlider(.synthDial(index), in: bar, value: value.2)
            }
            for index in 0..<min(5, parent.lab.eqGains.count) {
                setSlider(.eqBand(index), in: bar, value: Double(parent.lab.eqGains[index]))
            }

            if parent.page == 0,
               let item = bar.item(forIdentifier: .pageControls) as? NSCustomTouchBarItem,
               let stack = item.view as? NSStackView,
               stack.arrangedSubviews.count > 2,
               let microphoneButton = stack.arrangedSubviews[2] as? NSButton {
                let title = parent.manager.isMicLive ? "Stop Mic" : "Microphone"
                microphoneButton.title = title
                microphoneButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: title)
            }
        }

        private func customButton(in bar: NSTouchBar,
                                  identifier: NSTouchBarItem.Identifier) -> NSButton? {
            guard let item = bar.item(forIdentifier: identifier) as? NSCustomTouchBarItem else { return nil }
            return item.view as? NSButton
        }

        private func setSlider(_ identifier: NSTouchBarItem.Identifier, in bar: NSTouchBar, value: Double) {
            guard let item = bar.item(forIdentifier: identifier) as? NSSliderTouchBarItem else { return }
            item.slider.doubleValue = min(item.slider.maxValue, max(item.slider.minValue, value))
        }

        private var itemIdentifiers: [NSTouchBarItem.Identifier] {
            var items: [NSTouchBarItem.Identifier] = [.playPause, .flexibleSpace, .pageControls]
            switch parent.page {
            case 1: items += [.waveShape] + (0..<5).map { .synthDial($0) }
            case 2: items += [.spatialToggle, .spatialHeight, .spatialReverb]
            case 3: items += (0..<5).map { .eqBand($0) }
            case 4: items.append(.scopeMode)
            case 5 where parent.selectedLibraryURL != nil: items.append(.addSample)
            default: break
            }
            return items
        }

        func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
            switch identifier {
            case .playPause:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.view = button(title: isPlaying ? "Pause" : "Play",
                                   symbol: isPlaying ? "pause.fill" : "play.fill",
                                   action: #selector(togglePlayback))
                return item
            case .pageControls:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.view = pageControlStack()
                return item
            case .scopeMode:
                let item = NSCustomTouchBarItem(identifier: identifier)
                let control = NSSegmentedControl(labels: ["Waveform", "3D", "Lissajous"],
                                                 trackingMode: .selectOne, target: self,
                                                 action: #selector(changeScopeMode(_:)))
                control.selectedSegment = min(max(parent.scopeMode, 0), 2)
                item.view = control
                return item
            case .waveShape:
                return sliderItem(identifier, label: "Shape", range: 0...3,
                                  value: selectedWave, action: #selector(changeWave(_:)))
            case .spatialHeight:
                return sliderItem(identifier, label: "Height", range: -90...90,
                                  value: Double(selectedLocation?.elevation ?? 0), action: #selector(changeHeight(_:)))
            case .spatialReverb:
                return sliderItem(identifier, label: "Reverb", range: 0...100,
                                  value: Double(parent.spatial.reverb), action: #selector(changeReverb(_:)))
            case let identifier where identifier.rawValue.hasPrefix("com.audifuzz.touchbar.synthDial"):
                let index = Int(identifier.rawValue.suffix(1)) ?? 0
                let values: [(String, ClosedRange<Double>, Double)] = selectedVoiceValues
                guard values.indices.contains(index) else { return nil }
                let value = values[index]
                return sliderItem(identifier, label: value.0, range: value.1,
                                  value: value.2, action: #selector(changeSynthDial(_:)), tag: index)
            case let identifier where identifier.rawValue.hasPrefix("com.audifuzz.touchbar.eqBand"):
                let index = Int(identifier.rawValue.suffix(1)) ?? 0
                guard parent.lab.eqGains.indices.contains(index) else { return nil }
                return sliderItem(identifier, label: ["60 Hz", "250 Hz", "1 kHz", "4 kHz", "12 kHz"][index],
                                  range: -18...18, value: Double(parent.lab.eqGains[index]),
                                  action: #selector(changeEQ(_:)), tag: index)
            case .spatialToggle:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.view = button(title: parent.spatial.isEnabled ? "Spatial On" : "Spatial Off",
                                   symbol: "dot.radiowaves.left.and.right",
                                   action: #selector(toggleSpatial))
                return item
            case .addSample:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.view = button(title: "Add to Editor", symbol: "slider.horizontal.3",
                                   action: #selector(addSample))
                return item
            default: return nil
            }
        }

        private var isPlaying: Bool { parent.manager.isPlaying || parent.manager.isMicLive || parent.lab.isPlaying }

        private func button(title: String, symbol: String, action: Selector) -> NSButton {
            let result = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(),
                                  target: self, action: action)
            result.imagePosition = .imageLeading
            return result
        }

        private func sliderItem(_ identifier: NSTouchBarItem.Identifier, label: String,
                                range: ClosedRange<Double>, value: Double,
                                action: Selector, tag: Int = 0) -> NSTouchBarItem {
            let item = NSSliderTouchBarItem(identifier: identifier)
            item.label = label
            item.slider.minValue = range.lowerBound
            item.slider.maxValue = range.upperBound
            item.slider.doubleValue = min(range.upperBound, max(range.lowerBound, value))
            if identifier == .waveShape {
                item.slider.numberOfTickMarks = 4
                item.slider.allowsTickMarkValuesOnly = true
            }
            item.slider.target = self
            item.slider.action = action
            item.slider.tag = tag
            return item
        }

        private var selectedWave: Double {
            guard parent.lab.voices.indices.contains(parent.selectedVoiceIndex) else { return 0 }
            return Double(parent.lab.voices[parent.selectedVoiceIndex].wave.rawValue)
        }

        private var selectedVoiceValues: [(String, ClosedRange<Double>, Double)] {
            guard parent.lab.voices.indices.contains(parent.selectedVoiceIndex) else { return [] }
            let voice = parent.lab.voices[parent.selectedVoiceIndex]
            return [
                ("Pitch", log2(20)...log2(5000), log2(max(20, Double(voice.frequency)))),
                ("Volume", 0...1, Double(voice.volume)),
                ("Pan", -1...1, Double(voice.pan)),
                ("Sweep", 0...1, Double(voice.sweep)),
                ("Speed", 0.1...10, Double(voice.sweepRate))
            ]
        }

        private func pageControlStack() -> NSView {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 6
            switch parent.page {
            case 0:
                stack.addArrangedSubview(button(title: "Randomize", symbol: "shuffle", action: #selector(randomize)))
                stack.addArrangedSubview(button(title: "Reset", symbol: "arrow.counterclockwise", action: #selector(reset)))
                stack.addArrangedSubview(button(title: parent.manager.isMicLive ? "Stop Mic" : "Microphone",
                                                symbol: "mic.fill", action: #selector(toggleMicrophone)))
            case 1:
                stack.addArrangedSubview(button(title: "Instrument −", symbol: "minus", action: #selector(previousInstrument)))
                stack.addArrangedSubview(button(title: "Instrument +", symbol: "plus", action: #selector(nextInstrument)))
            case 2:
                break
            case 3:
                break
            default: break
            }
            return stack
        }

        @objc private func togglePlayback() {
            if parent.page == 1 || (parent.page == 3 && !parent.manager.isPlaying) ||
                (parent.page == 4 && parent.lab.isPlaying) {
                parent.lab.togglePlay()
            } else if parent.manager.source == .mic {
                parent.manager.isMicLive ? parent.manager.stopMic() : parent.manager.setSource(.mic)
            } else {
                parent.manager.togglePlayback()
            }
        }
        @objc private func randomize() { parent.manager.randomize() }
        @objc private func reset() { parent.manager.resetAll() }
        @objc private func toggleMicrophone() { parent.manager.isMicLive ? parent.manager.stopMic() : parent.manager.setSource(.mic) }
        @objc private func changeScopeMode(_ sender: NSSegmentedControl) { parent.scopeMode = sender.selectedSegment }
        @objc private func changeWave(_ sender: NSSlider) {
            guard parent.lab.voices.indices.contains(parent.selectedVoiceIndex) else { return }
            let voice = parent.lab.voices[parent.selectedVoiceIndex]
            parent.lab.binding(for: voice.id).wave.wrappedValue = Wave(rawValue: Int(sender.doubleValue.rounded())) ?? .round
        }
        @objc private func changeHeight(_ sender: NSSlider) {
            guard let location = selectedLocation else { return }
            parent.spatial.updateLocation(location.id) { $0.elevation = Float(sender.doubleValue) }
        }
        @objc private func changeReverb(_ sender: NSSlider) { parent.spatial.reverb = Float(sender.doubleValue) }
        @objc private func changeSynthDial(_ sender: NSSlider) {
            guard parent.lab.voices.indices.contains(parent.selectedVoiceIndex) else { return }
            let voice = parent.lab.voices[parent.selectedVoiceIndex]
            let binding = parent.lab.binding(for: voice.id)
            switch sender.tag {
            case 0: binding.frequency.wrappedValue = Float(pow(2, sender.doubleValue))
            case 1: binding.volume.wrappedValue = Float(sender.doubleValue)
            case 2: binding.pan.wrappedValue = Float(sender.doubleValue)
            case 3: binding.sweep.wrappedValue = Float(sender.doubleValue)
            case 4: binding.sweepRate.wrappedValue = Float(sender.doubleValue)
            default: break
            }
        }
        @objc private func changeEQ(_ sender: NSSlider) {
            guard parent.lab.eqGains.indices.contains(sender.tag) else { return }
            var gains = parent.lab.eqGains
            gains[sender.tag] = Float(sender.doubleValue)
            parent.lab.eqGains = gains
        }
        @objc private func toggleSpatial() { parent.spatial.isEnabled.toggle() }
        @objc private func addSample() { parent.addSelectedSample() }
        @objc private func previousInstrument() { parent.selectedVoiceIndex = max(0, parent.selectedVoiceIndex - 1) }
        @objc private func nextInstrument() {
            guard !parent.lab.voices.isEmpty else { return }
            parent.selectedVoiceIndex = min(parent.lab.voices.count - 1, parent.selectedVoiceIndex + 1)
        }
        private var selectedLocation: SpatialLocation? {
            parent.spatial.locations.first(where: { $0.id == parent.selectedSpatialLocationID }) ?? parent.spatial.locations.first
        }
    }
}

final class TouchBarAnchorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private extension NSTouchBarItem.Identifier {
    static let playPause = NSTouchBarItem.Identifier("com.audifuzz.touchbar.playPause")
    static let pageControls = NSTouchBarItem.Identifier("com.audifuzz.touchbar.pageControls")
    static let scopeMode = NSTouchBarItem.Identifier("com.audifuzz.touchbar.scopeMode")
    static let spatialToggle = NSTouchBarItem.Identifier("com.audifuzz.touchbar.spatialToggle")
    static let addSample = NSTouchBarItem.Identifier("com.audifuzz.touchbar.addSample")
    static let waveShape = NSTouchBarItem.Identifier("com.audifuzz.touchbar.waveShape")
    static let spatialHeight = NSTouchBarItem.Identifier("com.audifuzz.touchbar.spatialHeight")
    static let spatialReverb = NSTouchBarItem.Identifier("com.audifuzz.touchbar.spatialReverb")
    static func synthDial(_ index: Int) -> NSTouchBarItem.Identifier { .init("com.audifuzz.touchbar.synthDial\(index)") }
    static func eqBand(_ index: Int) -> NSTouchBarItem.Identifier { .init("com.audifuzz.touchbar.eqBand\(index)") }
}
#endif
