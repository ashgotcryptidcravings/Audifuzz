import SwiftUI

struct PreferencesView: View {
    // Standard AppStorage properties persist directly to UserDefaults
    @AppStorage("defaultSampleRate") private var defaultSampleRate: Double = 44100.0
    @AppStorage("bufferSize") private var bufferSize: Int = 512
    @AppStorage("autoPlayOnLoad") private var autoPlayOnLoad: Bool = true
    
    // Dedicated state for Caching & Speed settings
    @AppStorage("memoryAllocationGB") private var memoryAllocationGB: Int = 6
    @AppStorage("cacheLocation") private var cacheLocation: String = "ram"
    
    // Local state for UI feedback
    @State private var cacheCleared = false

    var body: some View {
        TabView {
            // General Settings Tab
            Form {
                Toggle("Auto-play audio when loaded", isOn: Binding(
                    get: { autoPlayOnLoad },
                    set: { newValue in
                        autoPlayOnLoad = newValue
                        print("[Preferences] SET Auto-Play on Load -> \(newValue)")
                    }
                ))
                
                Picker("Buffer Size", selection: Binding(
                    get: { bufferSize },
                    set: { newValue in
                        bufferSize = newValue
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
                    Picker("Memory Allocation", selection: Binding(
                        get: { memoryAllocationGB },
                        set: { newValue in
                            memoryAllocationGB = newValue
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
                            Text("Warning: Allocating 10GB may cause high resource usage and system slowdowns.")
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
                        print("[Preferences] SET Cache Location -> '\(newValue)'")
                    }
                )) {
                    Text("Disk (Slower)").tag("disk")
                    Text("RAM (Faster)").tag("ram")
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Button(cacheCleared ? "Cache Cleared!" : "Clear Temporary Cache") {
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

    /// Flushes all temporary audio files generated in the app's temp directory
    private func clearTemporaryCache() {
        print("[Preferences] Initiating temporary cache clear...")
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            var deletedCount = 0
            for file in files {
                if (try? FileManager.default.removeItem(at: file)) != nil {
                    deletedCount += 1
                }
            }
            print("[Preferences] SUCCESS: Cleared \(deletedCount) file(s) from temporary cache.")
            
            withAnimation {
                cacheCleared = true
            }
            // Reset button label after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    cacheCleared = false
                }
            }
        } catch {
            print("[Preferences] FAILURE: Could not clear cache: \(error.localizedDescription)")
        }
    }

    /// Resets all user preferences back to their factory settings
    private func resetToDefaults() {
        print("[Preferences] Resetting all settings to defaults...")
        defaultSampleRate = 44100.0
        bufferSize = 512
        autoPlayOnLoad = true
        memoryAllocationGB = 6
        cacheLocation = "ram"
        print("[Preferences] SUCCESS: All preferences restored to default state.")
    }
}

// Xcode Canvas Preview setup
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
