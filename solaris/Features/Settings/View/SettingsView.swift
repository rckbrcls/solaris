import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) var appSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appSettings = appSettings
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "Editing & Export"))) {
                    Toggle(String(localized: "Preserve metadata (EXIF/GPS)"), isOn: $appSettings.preserveMetadata)
                    Picker(String(localized: "Color profile"), selection: $appSettings.exportColorSpace) {
                        ForEach(AppSettings.ExportColorSpacePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                }
                Section(header: Text(String(localized: "History")), footer: Text(String(localized: "Limits the number of undo steps persisted per photo."))) {
                    Stepper(value: $appSettings.historyLimit, in: 10...300, step: 10) {
                        HStack {
                            Text(String(localized: "Undo steps"))
                            Spacer()
                            Text("\(appSettings.historyLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text(String(localized: "Camera")), footer: Text(String(localized: "When disabled, front camera photos remain mirrored as in the preview. When enabled, they are corrected to how others see you."))) {
                    Toggle(String(localized: "Mirror front camera"), isOn: $appSettings.mirrorFrontCamera)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
    }
}
