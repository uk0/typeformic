//
//  SettingsView.swift
//  MicMix
//
//  Settings window: configure an OpenAI-compatible model API and the cleanup prompt.
//

import Speech
import SwiftUI

struct SettingsView: View {
    @AppStorage(PolishConfig.Keys.dictationLocale) private var dictationLocale = ""
    @AppStorage(PolishConfig.Keys.engine) private var engine = PolishConfig.Engine.onDevice
    @AppStorage(PolishConfig.Keys.provider) private var provider = PolishConfig.Provider.openai
    @AppStorage(PolishConfig.Keys.baseURL) private var baseURL = ""
    @AppStorage(PolishConfig.Keys.apiKey) private var apiKey = ""
    @AppStorage(PolishConfig.Keys.model) private var model = ""
    @AppStorage(PolishConfig.Keys.prompt) private var prompt = PolishConfig.defaultPrompt
    @State private var locales: [Locale] = []
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: $dictationLocale) {
                    Text("Auto (follow system)").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Self.displayName(for: locale)).tag(locale.identifier)
                    }
                }
                Text("Speech-recognition language. First use of a language downloads its model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cleanup Engine") {
                Picker("Engine", selection: $engine) {
                    ForEach(PolishConfig.Engine.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Model API") {
                Picker("Provider", selection: $provider) {
                    ForEach(PolishConfig.Provider.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Base URL", text: $baseURL, prompt: Text(verbatim: provider.defaultBaseURL))
                SecureField("API Key", text: $apiKey, prompt: Text(verbatim: provider == .anthropic ? "sk-ant-…" : "sk-…"))
                TextField("Model", text: $model, prompt: Text(verbatim: provider.modelPlaceholder))
                HStack(spacing: 8) {
                    Button(testing ? "Testing…" : "Test Connection") { runTest() }
                        .disabled(testing)
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                }
                Text("Used when “Remote API” is selected. Falls back to on-device if unset or unreachable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .frame(width: 520, height: 640)
        .task {
            locales = (await SpeechTranscriber.supportedLocales)
                .sorted { $0.identifier < $1.identifier }
        }
    }

    private static func displayName(for locale: Locale) -> String {
        let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return "\(name) (\(locale.identifier))"
    }

    private func runTest() {
        testing = true
        testResult = ""
        Task {
            let result = await TextPolisher.testConnection(config: PolishConfig.current)
            testResult = result
            testing = false
        }
    }
}

#Preview {
    SettingsView()
}
