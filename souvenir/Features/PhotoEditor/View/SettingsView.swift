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

