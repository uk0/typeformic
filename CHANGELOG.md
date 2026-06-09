# Changelog

All notable changes to typeformic are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
