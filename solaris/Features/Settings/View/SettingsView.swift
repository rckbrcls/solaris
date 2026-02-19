import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Editing & Export")) {
                    Toggle("Preserve metadata (EXIF/GPS)", isOn: $appSettings.preserveMetadata)
                    Picker("Color profile", selection: $appSettings.exportColorSpace) {
                        ForEach(AppSettings.ExportColorSpacePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                }
                Section(header: Text("History"), footer: Text("Limits the number of undo steps persisted per photo.")) {
                    Stepper(value: $appSettings.historyLimit, in: 10...300, step: 10) {
                        HStack {
                            Text("Undo steps")
                            Spacer()
                            Text("\(appSettings.historyLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text("Camera"), footer: Text("When disabled, front camera photos remain mirrored as in the preview. When enabled, they are corrected to how others see you.")) {
                    Toggle("Mirror front camera", isOn: $appSettings.mirrorFrontCamera)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
