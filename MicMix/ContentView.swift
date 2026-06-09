//
//  ContentView.swift
//  MicMix
//
//  Compact "wake" pill shown at the bottom-center of the screen while dictating.
//  Two text lines: cleaned Chinese on top, English translation below.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 12) {
            indicator

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                Text(chineseText)
                    .font(.system(.callout))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                // English subline — kept rendered (with a space fallback) so the
                // pill height doesn't bounce between phases.
                Text(englishText.isEmpty ? " " : englishText)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Text("⌃⌥M")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 460, height: 78, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(16)
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: controller.phase == .recording)
        }
    }

    private var tint: Color {
        switch controller.phase {
        case .preparing: return .orange
        case .recording: return .red
        case .polishing: return .orange
        case .typing: return .blue
        case .error: return .yellow
        case .idle: return .gray
        }
    }

    private var iconName: String {
        switch controller.phase {
        case .preparing: return "arrow.down.circle"
        case .recording: return "mic.fill"
        case .polishing: return "wand.and.stars"
        case .typing: return "keyboard"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "mic"
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .idle: return "READY"
        case .preparing: return "PREPARING"
        case .recording: return "LISTENING"
        case .polishing: return "POLISHING"
        case .typing: return "INSERTING"
        case .error: return "ERROR"
        }
    }

    /// Line 1 — the Chinese text the speaker actually said (raw → cleaned).
    private var chineseText: String {
        switch controller.phase {
        case .preparing:
            return "Preparing language model…"
        case .recording:
            return controller.liveText.isEmpty ? "Speak now…" : controller.liveText
        case .polishing:
            return controller.liveText.isEmpty ? "Polishing…" : controller.liveText
        case .typing, .idle:
            return controller.liveText.isEmpty ? "Press ⌃⌥M to dictate." : controller.liveText
        case .error(let message):
            return message
        }
    }

    /// Line 2 — the English translation (when available).
    private var englishText: String {
        switch controller.phase {
        case .polishing:
            return controller.liveEnglish.isEmpty ? "Translating…" : controller.liveEnglish
        case .typing, .idle:
            return controller.liveEnglish
        case .preparing, .recording, .error:
            return ""
        }
    }
}

#Preview {
    ContentView(controller: DictationController())
        .frame(width: 492, height: 110)
}
