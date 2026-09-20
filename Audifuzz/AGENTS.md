# Audifuzz: Instructions for AI Coding Assistants

Read this before suggesting or editing code. It applies to GitHub Copilot, VS Code AI extensions, and any other AI model working in this repo.

## What this project is
Audifuzz is a lightweight audio distorter app for **macOS (MacBook)** and **iOS (iPhone)**, written in **SwiftUI** with **AVAudioEngine**. Users load an audio file, run it through a reorderable chain of effects, and tweak sliders. It should stay light and be easy to extend with new effects.

## Hard constraints (do not break these)
- **Xcode 14.2 / Swift 5.7 / macOS Monterey (12).** Do not use syntax or APIs that need newer toolchains (no macros, no `@Observable`, no `NavigationStack`, no Swift Charts, no SwiftData, no `if`/`switch` expressions, no `#Preview`).
- **Deployment targets: iOS 16.0, macOS 12.0.** Check availability before using any API.
- **No third-party dependencies** (no Swift packages, no CocoaPods) unless the owner asks.
- **One codebase for both platforms.** Wrap platform-specific code in `#if os(iOS)` / `#if os(macOS)`.
- Builds for iPhone happen on **Codemagic** (config in `codemagic.yaml`). Keep the project buildable from the command line with `xcodebuild`.
- Keep it **light**: no heavy animations, no per-frame UI redraws, no large assets.

## Project layout
```
Audifuzz/
  AudifuzzApp.swift            App entry, creates AudioEngineManager
  Audio/
    AudioEngineManager.swift   Engine, player, effect chain order, presets, randomize
    EffectModule.swift         Base class + EffectParameter
    Effects/                   One file per effect
  Presets/Preset.swift         Codable presets saved as JSON
  Views/
    ContentView.swift          Main screen
    EffectRowView.swift        One effect row (toggle, reorder, sliders)
```

## How effects work
Every effect is a subclass of `EffectModule` that wraps one `AVAudioUnit`.
- Give it a stable `key` (used by presets, never rename existing keys) and a display `name`.
- Declare its knobs as `EffectParameter(id:name:range:value:)`. The UI builds sliders automatically.
- Override `apply()` to copy `isEnabled` and parameter values onto the wrapped unit (`bypass = !isEnabled`).
- Call `apply()` at the end of the subclass `init`.

### To add a new effect
1. Create `Audio/Effects/YourEffect.swift`, subclassing `EffectModule` (copy `DelayEffect.swift` as a template).
2. Add `YourEffect()` to the `effects` array in `AudioEngineManager.init()`.
3. Nothing else. UI and presets pick it up automatically.

## Audio rules
- Never allocate memory, take locks, or call Swift/ObjC runtime-heavy code inside a real-time audio render callback.
- Prefer Apple's built-in `AVAudioUnit*` effects. Only write custom DSP (`AVAudioSinkNode`, `AVAudioSourceNode`, or an `AUAudioUnit` render block) when a built-in can't do the job.
- Reordering effects rebuilds the chain in `AudioEngineManager.rebuildChain`. Keep all node connections in that one place.
- On iOS, set up `AVAudioSession` before starting the engine (already done in `play()`).

## Code style
- Small files, one type per file, clear names.
- SwiftUI views stay simple. Business logic lives in `AudioEngineManager` or effect classes, not in views.
- Comment the "why", not the "what".
- Don't rename or reorganize files without being asked.

## Roadmap (ideas, not requirements)
- Live microphone input (needs mic permission strings and macOS audio-input entitlement)
- Preset picker UI using `PresetStore`
- Custom bitcrusher, ring mod, and wavefolder via render blocks
- Export processed audio to a file (offline rendering)
- Level meter using a single cheap tap on the main mixer
