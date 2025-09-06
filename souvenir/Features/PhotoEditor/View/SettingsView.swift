import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Importação de RAW")) {
                    Picker("Ação padrão", selection: $appSettings.rawHandlingDefault) {
                        ForEach(RawHandlingChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                }
                Section(header: Text("Limites de Downsample (lado mais longo)"), footer: Text("Ajuste para equilibrar memória x qualidade. RAW costuma ser mais pesado.")) {
                    Stepper(value: $appSettings.maxRawLongestSide, in: 1024...12000, step: 256) {
                        HStack {
                            Text("RAW")
                            Spacer()
                            Text("\(appSettings.maxRawLongestSide) px")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $appSettings.maxNonRawLongestSide, in: 1024...12000, step: 256) {
                        HStack {
                            Text("Não-RAW")
                            Spacer()
                            Text("\(appSettings.maxNonRawLongestSide) px")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text("Edição e Exportação")) {
                    Toggle("Preservar metadados (EXIF/GPS)", isOn: $appSettings.preserveMetadata)
                    Picker("Perfil de cor", selection: $appSettings.exportColorSpace) {
                        ForEach(AppSettings.ExportColorSpacePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                }
                Section(header: Text("Histórico"), footer: Text("Limita o número de passos de desfazer persistidos por foto.")) {
                    Stepper(value: $appSettings.historyLimit, in: 10...300, step: 10) {
                        HStack {
                            Text("Passos de undo")
                            Spacer()
                            Text("\(appSettings.historyLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(header: Text("Feedback")) {
                    Toggle("Haptics", isOn: $appSettings.hapticsEnabled)
                }
                Section(header: Text("Câmera"), footer: Text("Quando desabilitado, as fotos da câmera frontal ficam como aparentam no preview (espelhadas). Quando habilitado, são corrigidas como outras pessoas te veem.")) {
                    Toggle("Espelhar câmera frontal", isOn: $appSettings.mirrorFrontCamera)
                }
            }
            .navigationTitle("Configurações")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
