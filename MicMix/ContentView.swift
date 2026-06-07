//
//  ContentView.swift
//  MicMix
//
//  Compact "wake" pill shown at the bottom-center of the screen while dictating.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 12) {
            indicator

            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                Text(displayText)
                    .font(.system(.callout))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            Text("⌃⌥M")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 460, height: 58, alignment: .leading)
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

    private var displayText: String {
        switch controller.phase {
        case .preparing:
            return "Preparing language model…"
        case .recording, .polishing:
            return controller.liveText.isEmpty ? "Speak now…" : controller.liveText
        case .typing, .idle:
            return controller.lastOutput.isEmpty ? "Press ⌃⌥M to dictate." : controller.lastOutput
        case .error(let message):
            return message
        }
    }
}

#Preview {
    ContentView(controller: DictationController())
        .frame(width: 492, height: 90)
}
