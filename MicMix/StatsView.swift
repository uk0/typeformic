//
//  StatsView.swift
//  MicMix
//
//  Standalone panel summarising usage: dictations, characters, AI corrections.
//

import SwiftUI

struct StatsView: View {
    @ObservedObject private var stats = Stats.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MicMix Statistics")
                .font(.title2.weight(.semibold))

            HStack(spacing: 14) {
                card(value: stats.sessions,
                     label: "Dictations",
                     systemImage: "mic.fill",
                     tint: .blue)
                card(value: stats.characters,
                     label: "Characters",
                     systemImage: "textformat",
                     tint: .green)
                card(value: stats.corrections,
                     label: "AI Corrections",
                     systemImage: "wand.and.stars",
                     tint: .orange)
            }

            HStack {
                Spacer()
                Button("Reset", role: .destructive) { stats.reset() }
            }
        }
        .padding(24)
        .frame(width: 460, height: 230)
    }

    private func card(value: Int, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    StatsView()
}
