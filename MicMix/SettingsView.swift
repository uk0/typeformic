//
//  SettingsView.swift
//  MicMix
//
//  Settings window: configure an OpenAI-compatible model API and the cleanup prompt.
//

import ServiceManagement
import Speech
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(PolishConfig.Keys.dictationLocale) private var dictationLocale = ""
    @AppStorage(PolishConfig.Keys.engine) private var engine = PolishConfig.Engine.onDevice
    @AppStorage(PolishConfig.Keys.provider) private var provider = PolishConfig.Provider.openai
    @AppStorage(PolishConfig.Keys.baseURL) private var baseURL = ""
    @AppStorage(PolishConfig.Keys.model) private var model = ""
    @AppStorage(PolishConfig.Keys.prompt) private var prompt = PolishConfig.defaultPrompt
    @AppStorage(PolishConfig.Keys.style) private var style = PolishConfig.Style.developer
    @AppStorage(PolishConfig.Keys.outputLanguage) private var outputLanguage = PolishConfig.OutputLanguage.chinese
    // Credentials live in the Keychain, not UserDefaults — so no @AppStorage here.
    @State private var apiKey = PolishConfig.storedAPIKey
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(AmbientListener.Keys.enabled) private var ambientEnabled = false
    @AppStorage(AmbientListener.Keys.names) private var ambientNames = ""
    @AppStorage(AmbientListener.Keys.wakePhrase) private var ambientWakePhrase = ""
    @State private var locales: [Locale] = []
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Ambient Listening") {
                Toggle("Listen in the background", isOn: $ambientEnabled)
                    .onChange(of: ambientEnabled) { _, enabled in
                        if enabled {
                            Task {
                                _ = try? await UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound])
                                AppDelegate.shared?.ambient.syncWithConfig()
                            }
                        } else {
                            AppDelegate.shared?.ambient.syncWithConfig()
                        }
                    }
                TextField("My names", text: $ambientNames, prompt: Text(verbatim: "小明, Alex"))
                TextField("Wake phrase (starts dictation)", text: $ambientWakePhrase, prompt: Text(verbatim: "开始听写"))
                Text("Hears the room entirely on-device — audio never leaves your Mac and nothing is stored. While enabled the microphone stays active and uses extra power. When someone says one of your names you get a notification with sound (audible in headphones). Saying the wake phrase starts dictation hands-free. Dictation pauses ambient listening automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("Output") {
                Picker("Type at cursor", selection: $outputLanguage) {
                    ForEach(PolishConfig.OutputLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Style", selection: $style) {
                    ForEach(PolishConfig.Style.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("The wake pill always shows cleaned Chinese on top and the English translation below. This picks which one is typed at the cursor and the tone used for both.")
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
                    .onChange(of: apiKey) { _, newValue in
                        PolishConfig.setAPIKey(newValue)
                    }
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
                Text("Used when “Remote API” is selected. Falls back to on-device if unset or unreachable. The API key is stored in the macOS Keychain.")
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
        .frame(width: 520, height: 680)
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
