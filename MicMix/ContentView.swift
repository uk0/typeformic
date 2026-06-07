//
//  ContentView.swift
//  MicMix
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot
                Text(statusText)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Spacer()
                Text("⌃⌥M")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }

            ScrollView {
                Text(displayText)
                    .font(.system(.body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 60, maxHeight: 120)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .frame(width: 360)
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .opacity(controller.phase == .recording ? 1 : 0.6)
    }

    private var dotColor: Color {
        switch controller.phase {
        case .preparing: return .orange
        case .recording: return .red
        case .polishing: return .orange
        case .typing: return .blue
        case .error: return .yellow
        case .idle: return .gray
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .idle: return "Ready"
        case .preparing: return "Preparing…"
        case .recording: return "Listening…"
        case .polishing: return "Polishing…"
        case .typing: return "Inserting…"
        case .error(let message): return message
        }
    }

    private var displayText: String {
        switch controller.phase {
        case .preparing:
            return "Preparing language model…"
        case .recording, .polishing:
            return controller.liveText.isEmpty ? "Start speaking…" : controller.liveText
        case .typing, .idle:
            return controller.lastOutput.isEmpty ? "Press ⌃⌥M to dictate." : controller.lastOutput
        case .error:
            return "Try again with ⌃⌥M."
        }
    }
}

#Preview {
    ContentView(controller: DictationController())
}
