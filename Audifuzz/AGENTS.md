## How navigation works
`ContentView` owns the top SF Symbol navigation bar and active-page selection. It owns every engine as a `@StateObject` and passes it into the selected page. Pages never create their own engines.

### To add a new page
1. **Create the screen:** `Views/YourPageView.swift`, a SwiftUI `View`. Wrap sections in `.card()` and use `Dial` for adjustable values.
2. **If it needs audio or logic,** create its own engine class in a new folder (for example `Engines/YourEngine.swift`), an `ObservableObject` like `SoundLabEngine`. Give each page its own `AVAudioEngine`. Do not add nodes to the Editor's engine.
3. **Wire it into `ContentView.swift`:** add `@StateObject private var yourEngine = YourEngine()` if needed, then add an SF Symbol button and destination case using the next selection index.
4. **Talking between pages:** pass a closure into the destination view, like Sound Lab's "Use in Editor" (`manager.load(url:)` then `selection = 0`). Pages should not reference each other directly.
5. **Stop work when leaving:** add `.onDisappear { yourEngine.stop() }` so an idle page doesn't keep audio running.
6. **Permissions:** if the page needs a new permission (camera, files, etc.), add its Info key to both targets and list it under Permissions below.
7. **Docs:** add the new files to the layout above and to `FILE_TREE.md`.

## How effects work
Every effect is a subclass of `EffectModule` that wraps one `AVAudioUnit`.
- Give it a stable `key` (used by presets, never rename existing keys) and a display `name`.
- Declare its knobs as `EffectParameter(id:name:range:value:unit:display:)`. The UI builds a dial for each automatically.
- Override `apply()` to copy `isEnabled` and parameter values onto the wrapped unit (`bypass = !isEnabled`).
- Call `apply()` at the end of the subclass `init`.

### To add a new effect
1. Create `Effects/YourEffect.swift`, subclassing `EffectModule` (copy `DelayEffect.swift` as a template).
2. Add `YourEffect()` to the `effects` array in `AudioEngineManager.init()`.
3. Nothing else. The card, dials, reordering, randomize, reset, and presets pick it up automatically.

## Audio rules
- **Never allocate memory, take locks, or call Swift/ObjC-heavy code inside a real-time render block.** `SynthRenderer` reads plain settings from a fixed-size pointer for this reason. Keep it that way.
- Prefer Apple's built-in `AVAudioUnit*` effects. Write custom DSP only when a built-in can't do the job.
- **All effect connections live in `AudioEngineManager.rebuildChain()`.** Don't connect nodes anywhere else.
- **The microphone runs in its own `AVAudioEngine` (`micEngine`) and is fed to the output engine through `micPlayer`.** Never touch `inputNode` on the output engine: on macOS, mixing live input and output in one engine crashes with `isInputConnToConverter`.
- `MIDIInputManager` is shared by the app window and the macOS Settings scene. CoreMIDI callbacks dispatch parsed messages to the main queue before changing observable settings, instruments, or effect parameters.
- The Editor's output engine stays running after a file loads and the file is pre-scheduled (`armFile()`), so Play is instant. Keep it that way. File opening happens off the main thread and sets `isLoading`, which the UI shows as "Loading file…".
- The spatializer needs a mono input, so `SpatialStage.mixer` downmixes before `AVAudioEnvironmentNode`.
- On iOS, set up `AVAudioSession` before starting an engine (`configureSession()`). The mic needs `.playAndRecord`.
- Saving a Lab sound uses offline manual rendering so the file matches what you hear.

## UI & Performance rules
- Use `Dial` for most adjustable values, not `Slider` (with the exception of `EQFader` for graphic EQ layouts). 
- Sections use the `.card()` modifier.
- **Rendering Performance:** Always append `.drawingGroup()` to custom vector graphics (like `Dial` tracks or fader grooves) to offload rendering to the Metal GPU layer. 
- **View Updates:** Never mutate state inside `.onChange` or during a render pass to prevent SwiftUI infinite redraw loops that tank framerates. 
- **Lists:** Avoid macOS/iOS `List` for rapidly updating dynamic content; use `VStack` or `LazyVStack` to avoid bridging overhead.
- Avoid `ForEach($array)` bindings on arrays that can shrink; use id-based bindings like `SoundLabEngine.binding(for:)`.
- Views stay simple. Logic lives in engines, managers, and effect classes.

## Permissions (set in Xcode, not in code)
- Both targets: `NSMicrophoneUsageDescription` (Privacy - Microphone Usage Description).
- macOS: App Sandbox > Audio Input, and User Selected File (Read Only).
- iOS: `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` so saved samples show in the Files app.

## Code style
- Small files, one main type per file, clear names.
- Comment the "why", not the "what".
- Don't rename or reorganize files without being asked.
- When you add, remove, or rename a file, update the layout in this file and `FILE_TREE.md`.

## Emerging sound-library style
- Every bundled sound entry has a stable display `name`, an SF Symbol `symbol`, an optional musical `key`, and an optional resource `url`.
- Use `isPlaceholder` for reserved library slots without an audio file. Placeholders may show details, but must not offer playback or "Use in Editor".
- Resolve packaged audio with `Bundle.main.url(forResource:withExtension:)`; do not assume bundled files live in `SampleStorage`.
- Derive file length, channels, bitrate, and date added from the resolved `AVAudioFile` and URL resource values rather than hard-coding technical metadata.
- Keep bundled audio names stable once published. Adding a file should fill an existing placeholder or add a new entry without renaming existing entries.

## Toolchain and agent consistency
- The local verified toolchain is Xcode 14.2 (build 14C18), Swift 5.0 mode, macOS SDK 13.1, and iOS SDK 16.2. Codemagic is allowed to use its latest available Xcode and deployment image for release builds.
- macOS 12.0 (Monterey) is a hard deployment floor and must always remain supported. iOS 16.2 is the current iOS deployment floor. Check API availability before using newer SwiftUI, AVFoundation, or platform APIs; gate newer APIs explicitly when needed.
- There is no upper OS compatibility cap for Codemagic builds. Keep the minimum deployment targets stable while allowing the CI image to advance to newer Apple OS and SDK versions.
- Validate macOS changes with `xcodebuild -project Audifuzz.xcodeproj -scheme Audifuzz -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO`.
- Treat a successful build as compile validation only. Do not claim that microphone, file loading, or audio behavior was runtime-tested unless it was actually exercised.
- Read this file before editing and preserve the existing architecture, effect keys, public parameter IDs, and user changes.
- Start from the nearest owning implementation and make the smallest focused change. Avoid speculative refactors and unrelated formatting changes.
- Some source files are referenced by the Xcode project from outside this workspace. Do not relocate or recreate those files unless explicitly requested; verify the project file before changing source layout.
- After an edit, run the narrowest available validation first, then run the full macOS build when the change affects shared audio or UI code.

## Roadmap (ideas, not requirements)
- Preset picker page using `PresetStore`
- Custom bitcrusher, ring mod, and wavefolder via render blocks
- Save the processed Editor output to a file (offline rendering)
- Level meter using a single cheap tap on the main mixer
- Note keyboard for SynthSpace

## Added page files
- `Views/OscilloscopeView.swift`: live display of processed Editor output.
- `Views/Oscilloscope3DView.swift`: interactive stereo-phase scope, with left/right amplitude and time on separate axes.
- `Views/WhatsNewView.swift`: release highlights shown on app launch.
- `Views/TouchBarControls.swift`: macOS page-aware playback and editing controls, hosted by `ContentView`.

## Added effect files
- `Effects/CompressorEffect.swift`: Apple Dynamics Processor wrapper.
- `Effects/ToneEQEffect.swift`: three-band tone equalizer.

## Added MIDI input file
- `Engines/MIDIInputManager.swift`: shared CoreMIDI input device and channel routing.
