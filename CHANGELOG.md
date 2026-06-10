# Changelog

All notable changes to typeformic are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-06-11

Platform-conventions pass: privacy, security, and system-integration
behaviors brought in line with macOS standards.

### Security & privacy
- Dictation transcripts are no longer written to `/tmp`. Diagnostics go
  through the unified logging system (`os.Logger`); transcript content is
  marked `privacy: .private`, so release builds never persist what you said.
  A plain-file mirror exists only in DEBUG builds behind `MICMIX_FILELOG=1`.
- The model API key moved from UserDefaults (plaintext plist) into the
  **macOS Keychain**, with a one-time migration that scrubs the legacy value
  from disk.

### Added
- **Launch at login** toggle in Settings (`SMAppService`).
- **About MicMix** panel in the menu-bar menu, with version and copyright.
- `LSApplicationCategoryType` (Productivity) and a copyright string in the
  app bundle.

### Changed
- The app declares `LSUIElement` in Info.plist instead of switching activation
  policy at runtime, so no Dock icon flashes at launch.
- The dictation pill and the translate overlay now share one visual grammar:
  regular material, 16 pt corners, hairline stroke, the window's native
  shadow, and the same circular tinted icon badge. The overlay placeholder is
  English, matching the rest of the UI.

### Fixed
- All Swift concurrency warnings (non-Sendable buffer capture, two no-op
  `await`s).

## [1.1.0] — 2026-06-10

### Added
- **Bilingual cleanup.** Every dictation now produces a cleaned Chinese line
  *and* a faithful English translation in a single model call. The wake pill
  shows both — cleaned Chinese on top, English underneath.
- **Output language.** Pick whether Chinese (default) or English is typed at
  the cursor. Settings → *Output* → *Type at cursor*.
- **Style picker.** Developer (default), Casual, Formal, Concise. The tone is
  applied to both the cleaned Chinese and the English translation. The
  user-editable cleanup prompt stays free of style placeholders — the style
  directive is appended at request time.
- **Translate Input overlay.** Press **⌃⌥T** anywhere to summon a translucent
  compose bar at the mouse cursor. Type Chinese, press **⏎**, and the English
  (in your current style) is typed into the previously-frontmost app. **⎋**
  cancels. Works inside any app — no IME hook required.

### Changed
- The wake pill grew from one text line to two to host the translation
  underneath the Chinese transcript. Panel height: 90 → 110.
- Translation requests now use an instruction-only prompt with four few-shot
  examples that anchor the expected output shape. An output sanitizer strips
  common LLM artifacts post-hoc — `Translation:` / `Here is …` prefixes,
  wrapping quotes (straight, smart, French, CJK), code fences, leading bullet
  / heading markers, and markdown bold/italic wrappers — so the text injected
  at the cursor is plain. No model swap required.
- Global hotkey machinery now supports multiple instances; the dictation
  (⌃⌥M) and translate (⌃⌥T) hotkeys coexist without one handler firing the
  other.

### Fixed
- Translate overlay no longer paints a white halo around its rounded capsule.
  The hosting view's backing layer is now explicitly transparent, and the
  rounded material fills the panel exactly.
- Translate overlay anchors to the actual mouse position instead of relying
  on the Accessibility caret rect, which returned wrong coordinates in
  browsers and Electron apps.
- The text-injection step now waits ~120 ms after refocusing the originally
  frontmost app, so the first keystrokes no longer land in the overlay.

## [1.0.0] — 2026-06-08

Initial release.

- Press **⌃⌥M** anywhere to start dictating; pause and the cleaned text is
  typed at your cursor in any app (no clipboard).
- On-device speech recognition via `SpeechAnalyzer` / `SpeechTranscriber`
  (macOS 26). Audio never leaves the Mac.
- Voice-activity detection ends the utterance automatically after trailing
  silence.
- Cleanup engine pickable between Apple's on-device Foundation Models and a
  remote API (OpenAI-compatible or Anthropic). Bring-your-own base URL, API
  key, and model.
- Editable cleanup prompt with a one-click connection test.
- Editable dictation language; the model for that language downloads on
  first use.
- Menu-bar accessory app; no Dock icon. A small wake pill fades in at the
  bottom of the screen during dictation and disappears when you're done.
- Persistent statistics: dictations, characters, AI corrections.
