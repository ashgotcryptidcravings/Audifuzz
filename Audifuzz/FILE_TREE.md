# Audifuzz File Tree

A map of every file, what it does, and how the pieces fit together.

## The tree

```
Audifuzz/                            (repo root)
├── Audifuzz.xcodeproj
└── Audifuzz/
    ├── AGENTS.md                    Rules for AI assistants
    ├── TODO.md                      Self Explanatory
    ├── FILE_TREE.md                 This file
    ├── codemagic.yaml               Codemagic build config for iPhone
    ├── Audifuzz.entitlements        macOS sandbox permissions
    ├── AudifuzzApp.swift            App entry point
    ├── Persistence.swift            Xcode's stock Core Data controller
    ├── Audifuzz.xcdatamodeld/       Core Data model
    ├── Assets.xcassets/             App icon and accent color
    ├── PreBundledAudio/
    │   ├── DanganronpaIntro.mp3     Audio shipped inside the app
    │   ├── Synths.sf2               Bundled MIDI SoundFont with synth-waveform presets
    │   └── BrightPiano.sf2          Bundled MIDI SoundFont with a Rhodes preset
    ├── Engines/
    │   ├── AudioEngineManager.swift Editor tab audio brain
    │   ├── MIDIInputManager.swift    Shared CoreMIDI input and settings
    │   ├── SoundLabEngine.swift     Sound Lab, MIDI sampler, EQ, saving
    │   ├── BuiltInSoundLibrary.swift Starter WAVs and the Sound Library entries
    │   ├── SampleStorage.swift      Where saved samples live
    │   └── Preset.swift             Save/load effect settings as JSON
    ├── Effects/
    │   ├── CompressorEffect.swift
    │   ├── ToneEQEffect.swift
    │   ├── EffectModule.swift       Base class for all effects
    │   ├── SpatialStage.swift       Native multi-source spatial audio
    │   ├── OverdriveEffect.swift
    │   ├── BitCrushEffect.swift
    │   ├── FilterEffect.swift
    │   ├── PitchEffect.swift
    │   ├── DelayEffect.swift
    │   └── ReverbEffect.swift
    ├── Instruments/
    │   ├── SynthModels.swift        Wave shapes and the Voice ("instrument") type
    │   └── SynthRenderer.swift      Real-time wave generator
    └── Views/
        ├── ContentView.swift        Top navigation, playback bar, and release sheet
        ├── EditorView.swift         Editor tab screen
        ├── SoundLabView.swift       Sound Lab and Equalizer tab screens
        ├── SoundLibraryView.swift   Included sound list and detail screen
        ├── OscilloscopeView.swift  Live Editor and SynthSpace output display
        ├── Oscilloscope3DView.swift Interactive stereo phase display in 3D
        ├── WhatsNewView.swift     Release highlights sheet
        ├── TouchBarControls.swift  Page-aware macOS Touch Bar controls
        ├── MIDIStatusView.swift    MIDI status, controller capabilities, and chord-color orb
        ├── MIDITrainerView.swift   Guided controller input and app handoff timing trainer
        ├── BenchmarkWizardView.swift Guided audio benchmark and detailed Markdown export
        ├── SpatialCardView.swift    Spatializer page, Editor summary, and placement field
        ├── EffectCardView.swift     One effect card with dials
        ├── PreferencesView.swift    Audio, performance, device, and cache settings
        └── Dial.swift               The rotary knob control and the .card() style
```

> `SampleStorage.swift`, `Preset.swift`, `AudifuzzApp.swift` and `Dial.swift` are
> referenced by the Xcode project. Their folder above is where they are expected
> to live; confirm against the project file.

## What each file does

### App
- **AudifuzzApp.swift**: starts the app and shows `ContentView`.
- **Persistence.swift** and **Audifuzz.xcdatamodeld**: Xcode's stock Core Data setup.

### Engines/ (audio brains)
- **AudioEngineManager.swift**: the main audio brain. It runs two audio engines:
  - The **output engine** plays your file (or the mic feed) through the effect chain and out the speakers. The file is queued as soon as it loads, so Play is instant, and the screen shows "Loading file…" while it opens.
  - The **mic engine** only listens to the microphone. It copies each chunk of sound into the output engine, so the two never fight (this avoids the macOS crash).
  - It also handles reordering effects, Randomize, Reset, mic recording, and presets.
- **MIDIInputManager.swift**: app-wide CoreMIDI source selection, channel filtering, sustain handling, pitch-bend settings, unique trainer-learned knob/button CC and Program Change mappings, and normalized modulation-wheel travel.
- **SoundLabEngine.swift**: plays MIDI through selectable presets from bundled `Synths.sf2` and `BrightPiano.sf2`, falls back to Apple's General MIDI DLS bank on macOS, and then to the built-in oscillator.
- **PreBundledAudio/Synths.sf2**: PureSynth Basic SoundFont by Nero; contains nine electronic waveform presets (Triangle, Square, Sawtooth, and variations), not an acoustic piano bank. Credit requested in the embedded SoundFont metadata.
- **PreBundledAudio/BrightPiano.sf2**: contains the `Piano Rhodes` preset at bank 0, program 38.
- **EffectModule.swift**: the template every effect follows. An effect has a name, an on/off switch, and a list of knobs (`EffectParameter`). Changing a knob calls `apply()`, which pushes the value into the real audio unit.
- **SpatialStage.swift**: places one signal at up to four virtual locations through `AVAudioEnvironmentNode`'s device-aware spatial renderer, with direction, height, distance, and reverb.
- **SampleStorage.swift**: creates file names and lists saved sounds in the app's `Documents/Samples` folder. Both mic recordings and Sound Lab saves go there.

### Effects/
Each file wraps one built-in Apple audio unit and maps its dials onto it.
- **OverdriveEffect**: distortion with selectable Apple characters, Drive and Mix.
- **BitCrushEffect**: Apple decimation and lo-fi presets, Gain and Mix.
- **FilterEffect**: selectable low-pass, high-pass, and band-pass with cutoff and resonance.
- **PitchEffect**: changes pitch and speed with overlap control.
- **DelayEffect**: echoes with Time, Feedback, Mix, and Tone.
- **ReverbEffect**: room sound with Mix and twelve Apple room presets.
- **CompressorEffect**: wraps Apple's Dynamics Processor audio unit.
- **ToneEQEffect**: three-band low shelf, parametric mid, and high shelf.

### Instruments/ (Sound Lab)
- **SynthModels.swift**: defines the four wave shapes (round, square, triangle, saw) and the `Voice` type: one instrument with pitch in Hz, volume, ear position, sweep width, and sweep speed. Also turns a pitch into a note name.
- **SynthRenderer.swift**: makes the actual sound, sample by sample. It adds all instruments together, renders MIDI note voices, and pans each one between your left and right ear. It avoids locks and memory allocation, so it can run safely on the audio thread.

- **BuiltInSoundLibrary.swift** (in `Engines/`): creates three original starter WAV sounds on first launch, and lists them together with bundled audio files and reserved "Starter Slot" placeholders for the Sound Library.

### Presets
- **Preset.swift** (in `Engines/`): saves every effect's on/off state and dial values as small JSON files. The Editor can already create and apply them, but there is no picker screen yet.

### Views/
- **ContentView.swift**: top SF Symbol navigation buttons, a compact now-playing bar, and a "What's new" sheet. On macOS it also attaches the page-aware Touch Bar controls. It creates both audio brains and sends "Use in Editor" from SynthSpace to the Editor.
- **EditorView.swift**: the main screen. File/Mic switch, Open/Play/Stop/Record buttons, and effect cards. Spatializer controls have their own page.
- **SoundLibraryView.swift**: the Sound Library page. Installed items open their details (length, channels, bitrate, key, date added); reserved placeholders stay hidden. A separate preview control plays a short sample.
- **PreferencesView.swift**: responsive settings tabs for sample rate, buffer size, audio devices (macOS), cache, performance, and MIDI input, with controller learning in the MIDI Trainer.
- **OscilloscopeView.swift**: plots the Editor or SynthSpace's stereo output as waveform, interactive 3D stereo phase, or 2D Lissajous.
- **Oscilloscope3DView.swift**: renders left amplitude, right amplitude, and time on separate 3D axes with a rotatable SceneKit camera.
- **WhatsNewView.swift**: presents current release highlights in a separate launch sheet.
- **TouchBarControls.swift**: provides playback controls throughout the Mac app and page-specific controls for Editor, SynthSpace, Spatializer, Equalizer, Oscilloscope, and a selected Sound Library file.
- **MIDIStatusView.swift**: reports connection and device capabilities, and colors a central orb from active MIDI notes and chord tension.
- **MIDITrainerView.swift**: guides key, velocity, hold, pitch bend, modulation range, pads, octave up/down verification, unique named knob/button assignment, sustain, and app handoff timing checks.
- **BenchmarkWizardView.swift**: runs six sample-rate and buffer-size profiles while monitoring process CPU/RAM and held-note waveform gaps, then exports detailed Markdown telemetry. Per-app wattage is unavailable through macOS public APIs.
- **SoundLabView.swift**: the Lab and Equalizer screens. The Lab contains instrument cards, selected-instrument controls, Save Sample, and the saved samples list. The Equalizer page reuses `EqualizerCardView` and the live graph.
- **EffectCardView.swift**: one effect's card: on/off, move up/down, and a dial for each knob.
- **SpatialCardView.swift**: the full Spatializer page, compact Editor summary, and `SpatialPadView`, a top-down field where you drag a dot to place the sound.
- **Dial.swift**: the rotary knob. Drag up/right to turn up, down/left to turn down. It supports a log scale for pitch. It also holds the `.card()` style used for every panel.

## How it all flows

**Editor tab**
```
File player ─┐
             ├─> mixer -> effect 1 -> effect 2 -> ... -> [spatializer] -> speakers
Mic feed ────┘
```
1. `EditorView` shows one `EffectCardView` per effect from `AudioEngineManager`.
2. Turning a dial changes a value in `EffectParameter`, which calls the effect's `apply()`, which updates the real audio unit.
3. Moving an effect up or down reconnects the chain in `rebuildChain()`.

**SynthSpace tab**
```
Instrument 1 ─┐
Instrument 2 ─┼─> SynthRenderer -> equalizer -> speakers
Instrument N ─┘                        └─> Save Sample -> WAV in Samples folder
MIDI keys ───────> selected bundled SF2 sampler -> equalizer
                       └─> Apple DLS on macOS -> oscillator fallback
```
"Use in Editor" loads a saved sample into the Editor tab.

On macOS, `ContentView` installs a native `NSTouchBar` through `TouchBarControls` on the hosting window. Playback and page-specific controls edit the same shared engine state as the page. The MIDI page and trainer use the shared `MIDIInputManager` owned by the app and Preferences scene.

## Adding a new effect
1. Copy `DelayEffect.swift` to `Effects/YourEffect.swift` and change the audio unit, name, and knobs.
2. Add `YourEffect()` to the `effects` list in `AudioEngineManager.init()`.
3. That's it. The card, dials, reordering, Randomize, Reset, and presets pick it up automatically.

## Adding a new page
See "To add a new page" in `AGENTS.md`. In short: make the screen in `Views/`, give it its own engine if it needs audio, then add one more `NavigationLink` with the next unused tag in `ContentView.swift`.

## Rules to remember
- Only `AudioEngineManager.rebuildChain()` connects effect nodes.
- The mic must stay in its own engine (`micEngine`).
- Use `Dial`, not `Slider`, for every adjustable value.
- Stay compatible with Xcode 14.2, iOS 16, and macOS 12.
