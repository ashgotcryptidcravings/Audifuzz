# Audifuzz File Tree

A map of every file, what it does, and how the pieces fit together.

## The tree

```
Audifuzz-starter/
├── README.md                        Setup steps for Xcode
├── AGENTS.md                        Rules for AI assistants (Copilot, VS Code, etc.)
├── codemagic.yaml                   Codemagic build config for iPhone
├── FILE_TREE.md
├── .github/
│   └── copilot-instructions.md      Copy of AGENTS.md that GitHub Copilot reads
└── Audifuzz/
    ├── AudifuzzApp.swift            App entry point
    ├── Audio/
    │   ├── AudioEngineManager.swift Editor tab audio brain
    │   ├── EffectModule.swift       Base class for all effects
    │   ├── SpatialStage.swift       3D spatializer
    │   ├── SampleStorage.swift      Where saved samples live
    │   └── Effects/
    │       ├── OverdriveEffect.swift
    │       ├── BitCrushEffect.swift
    │       ├── FilterEffect.swift
    │       ├── PitchEffect.swift
    │       ├── DelayEffect.swift
    │       └── ReverbEffect.swift
    ├── Lab/
    │   ├── SynthModels.swift        Wave shapes and the Voice ("instrument") type
    │   ├── SynthRenderer.swift      Real-time wave generator
    │   └── SoundLabEngine.swift     Sound Lab audio brain, EQ, saving
    ├── Presets/
    │   └── Preset.swift             Save/load effect settings as JSON
    └── Views/
        ├── ContentView.swift        Sidebar menu (Editor + Sound Lab)
        ├── EditorView.swift         Editor tab screen
        ├── SoundLabView.swift       Sound Lab tab screen
        ├── EffectCardView.swift     One effect card with dials
        ├── SpatialCardView.swift    Spatializer card + placement pad
        └── Dial.swift               The rotary knob control
```

## What each file does

### App
- **AudifuzzApp.swift**: starts the app and shows `ContentView`. Nothing else.

### Audio/ (Editor tab)
- **AudioEngineManager.swift**: the main audio brain. It runs two audio engines:
  - The **output engine** plays your file (or the mic feed) through the effect chain and out the speakers. The file is queued as soon as it loads, so Play is instant, and the screen shows "Loading file…" while it opens.
  - The **mic engine** only listens to the microphone. It copies each chunk of sound into the output engine, so the two never fight (this avoids the macOS crash).
  - It also handles reordering effects, Randomize, Reset, mic recording, and presets.
- **EffectModule.swift**: the template every effect follows. An effect has a name, an on/off switch, and a list of knobs (`EffectParameter`). Changing a knob calls `apply()`, which pushes the value into the real audio unit.
- **SpatialStage.swift**: places the sound in 3D around your head. It turns the sound mono, then uses Apple's HRTF renderer with direction, height, distance, and reverb.
- **SampleStorage.swift**: creates file names and lists saved sounds in the app's `Documents/Samples` folder. Both mic recordings and Sound Lab saves go there.

### Audio/Effects/
Each file wraps one built-in Apple audio unit and maps its dials onto it.
- **OverdriveEffect**: warm distortion (Drive, Mix).
- **BitCrushEffect**: crunchy lo-fi (Gain, Mix).
- **FilterEffect**: low-pass filter that cuts high sounds (Cutoff, shown in Hz).
- **PitchEffect**: changes pitch and speed (Pitch in cents, Speed).
- **DelayEffect**: echoes (Time, Feedback, Mix).
- **ReverbEffect**: room sound (Mix).

### Lab/ (Sound Lab tab)
- **SynthModels.swift**: defines the four wave shapes (round, square, triangle, saw) and the `Voice` type: one instrument with pitch in Hz, volume, ear position, sweep width, and sweep speed. Also turns a pitch into a note name.
- **SynthRenderer.swift**: makes the actual sound, sample by sample. It adds all instruments together and pans each one between your left and right ear. It avoids locks and memory allocation, so it can run safely on the audio thread.
- **SoundLabEngine.swift**: runs the Lab: instruments -> 5-band equalizer -> speakers. "Save Sample" renders the same sound to a WAV file faster than real time, so the file matches what you heard.

### Presets/
- **Preset.swift**: saves every effect's on/off state and dial values as small JSON files. The Editor can already create and apply them, but there is no picker screen yet.

### Views/
- **ContentView.swift**: the sidebar menu. Each page is one link in the list. It creates both audio brains and sends "Use in Editor" from the Lab to the Editor. Its Mac-only sidebar button is wrapped in `#if os(macOS)` so the iPhone build still works.
- **EditorView.swift**: the main screen. File/Mic switch, Open/Play/Stop/Record buttons, effect cards, and the spatializer card.
- **SoundLabView.swift**: the Lab screen. Instrument cards, the equalizer card, Save Sample, and the saved samples list. It contains `VoiceCardView` and `EqualizerCardView`.
- **EffectCardView.swift**: one effect's card: on/off, move up/down, and a dial for each knob.
- **SpatialCardView.swift**: the spatializer card plus `SpatialPadView`, a top-down circle where you drag a dot to place the sound.
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

**Sound Lab tab**
```
Instrument 1 ─┐
Instrument 2 ─┼─> SynthRenderer -> equalizer -> speakers
Instrument N ─┘                        └─> Save Sample -> WAV in Samples folder
```
"Use in Editor" loads a saved sample into the Editor tab.

## Adding a new effect
1. Copy `DelayEffect.swift` to `Audio/Effects/YourEffect.swift` and change the audio unit, name, and knobs.
2. Add `YourEffect()` to the `effects` list in `AudioEngineManager.init()`.
3. That's it. The card, dials, reordering, Randomize, Reset, and presets pick it up automatically.

## Adding a new page
See "To add a new page" in `AGENTS.md`. In short: make the screen in `Views/`, give it its own engine if it needs audio, then add one more `NavigationLink` with the next unused tag in `ContentView.swift`.

## Rules to remember
- Only `AudioEngineManager.rebuildChain()` connects effect nodes.
- The mic must stay in its own engine (`micEngine`).
- Use `Dial`, not `Slider`, for every adjustable value.
- Stay compatible with Xcode 14.2, iOS 16, and macOS 12.
