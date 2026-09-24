import SwiftUI

struct PreferencesView: View {
    // Standard AppStorage properties persist directly to UserDefaults
    @AppStorage("defaultSampleRate") private var defaultSampleRate: Double = 44100.0
    @AppStorage("bufferSize") private var bufferSize: Int = 512
    @AppStorage("autoPlayOnLoad") private var autoPlayOnLoad: Bool = true
    
    // Dedicated state for Caching & Speed settings
    @AppStorage("memoryAllocationGB") private var memoryAllocationGB: Int = 6
    @AppStorage("cacheLocation") private var cacheLocation: String = "disk"
    
    // Local state for UI feedback
    @State private var cacheCleared = false

    private func setPreference(_ key: String) {
        NotificationCenter.default.post(
            name: .audifuzzPreferenceChanged,
            object: nil,
            userInfo: ["key": key]
        )
    }

    var body: some View {
        TabView {
            // General Settings Tab
            Form {
                Toggle("Auto-play audio when loaded", isOn: Binding(
                    get: { autoPlayOnLoad },
                    set: { newValue in
                        autoPlayOnLoad = newValue
                        setPreference("autoPlayOnLoad")
                        print("[Preferences] SET Auto-Play on Load -> \(newValue)")
                    }
                ))
                
                Picker("Buffer Size", selection: Binding(
                    get: { bufferSize },
                    set: { newValue in
                        bufferSize = newValue
                        setPreference("bufferSize")
                        print("[Preferences] SET Buffer Size -> \(newValue) samples")
                    }
                )) {
                    Text("256 samples").tag(256)
                    Text("512 samples").tag(512)
                    Text("1024 samples").tag(1024)
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // Audio Hardware Tab
            Form {
                Picker("Sample Rate", selection: Binding(
                    get: { defaultSampleRate },
                    set: { newValue in
                        defaultSampleRate = newValue
                        setPreference("defaultSampleRate")
                        print("[Preferences] SET Sample Rate -> \(newValue) Hz")
                    }
                )) {
                    Text("44.1 kHz").tag(44100.0)
                    Text("48.0 kHz").tag(48000.0)
                    Text("96.0 kHz").tag(96000.0)
                }
            }
            .padding(20)
            .tabItem {
                Label("Audio", systemImage: "waveform")
            }
            
            // Caching & Speed Tab
            Form {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Sample Cache Limit", selection: Binding(
                        get: { memoryAllocationGB },
                        set: { newValue in
                            memoryAllocationGB = newValue
                            setPreference("memoryAllocationGB")
                            print("[Preferences] SET Memory Allocation -> \(newValue) GB")
                        }
                    )) {
                        Text("Low (3GB)").tag(3)
                        Text("Medium (6GB)").tag(6)
                        Label("High (10GB)", systemImage: "exclamationmark.triangle.fill").tag(10)
                    }
                    
                    if memoryAllocationGB == 10 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Warning: A 10 GB cache limit may use substantial disk or temporary storage.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.default, value: memoryAllocationGB)

                Picker("Sample Cache Location", selection: Binding(
                    get: { cacheLocation },
                    set: { newValue in
                        cacheLocation = newValue
                        setPreference("cacheLocation")
                        print("[Preferences] SET Cache Location -> '\(newValue)'")
                    }
                )) {
                    Text("Disk (Slower)").tag("disk")
                    Text("RAM (Faster)").tag("ram")
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Button(cacheCleared ? "Cache Cleared!" : "Clear Sample Cache") {
                        clearTemporaryCache()
                    }
                    .disabled(cacheCleared)
                    
                    Spacer()
                    
                    Button("Reset to Defaults", role: .destructive) {
                        resetToDefaults()
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Caching & Speed", systemImage: "clock.badge.checkmark")
            }
        }
        .frame(width: 480, height: 280)
    }

    /// Removes saved samples from the currently selected Audifuzz cache.
    private func clearTemporaryCache() {
        print("[Preferences] Initiating temporary cache clear...")
        let deletedCount = SampleStorage.clearCache()
        print("[Preferences] SUCCESS: Cleared \(deletedCount) sample file(s) from Audifuzz cache.")

        withAnimation {
            cacheCleared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                cacheCleared = false
            }
        }
    }

    /// Resets all user preferences back to their factory settings
    private func resetToDefaults() {
        print("[Preferences] Resetting all settings to defaults...")
        defaultSampleRate = 44100.0
        bufferSize = 512
        autoPlayOnLoad = true
        memoryAllocationGB = 6
        cacheLocation = "disk"
        setPreference("all")
        print("[Preferences] SUCCESS: All preferences restored to default state.")
    }
}

// Xcode Canvas Preview setup
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
