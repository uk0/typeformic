//
//  SettingsView.swift
//  MicMix
//
//  Settings window: configure an OpenAI-compatible model API and the cleanup prompt.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(PolishConfig.Keys.engine) private var engine = PolishConfig.Engine.onDevice
    @AppStorage(PolishConfig.Keys.baseURL) private var baseURL = ""
    @AppStorage(PolishConfig.Keys.apiKey) private var apiKey = ""
    @AppStorage(PolishConfig.Keys.model) private var model = ""
    @AppStorage(PolishConfig.Keys.prompt) private var prompt = PolishConfig.defaultPrompt

    var body: some View {
        Form {
            Section("Cleanup Engine") {
                Picker("Engine", selection: $engine) {
                    ForEach(PolishConfig.Engine.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Model API (OpenAI-compatible)") {
                TextField("Base URL", text: $baseURL, prompt: Text(verbatim: "https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text(verbatim: "sk-…"))
                TextField("Model", text: $model, prompt: Text(verbatim: "gpt-4o-mini"))
                Text("Used when “Remote API” is selected. Falls back to on-device if unset or unreachable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(engine == .onDevice)

            Section("Cleanup Prompt") {
                TextEditor(text: $prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                HStack {
                    Spacer()
                    Button("Reset to Default") { prompt = PolishConfig.defaultPrompt }
                        .disabled(prompt == PolishConfig.defaultPrompt)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
    }
}

#Preview {
    SettingsView()
}
