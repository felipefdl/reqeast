//
//  HttpTimingPopover.swift
//  Reqeast
//

import SwiftUI

struct HttpTimingPopover: View {
    let timing: StoredTimingBreakdown

    private let phaseColors: [Color] = [.blue, .orange, .green]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timing")
                .font(.headline)

            let phases = timing.phases
            let maxMs = phases.map(\.1).max() ?? 1.0

            ForEach(phases.indices, id: \.self) { index in
                let phase = phases[index]
                HStack(spacing: 8) {
                    Text(phase.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)

                    GeometryReader { geometry in
                        let fraction = CGFloat(phase.1 / maxMs)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(phaseColors[index % phaseColors.count].opacity(0.7))
                            .frame(width: max(2, geometry.size.width * fraction))
                    }
                    .frame(height: 14)

                    Text(formatMs(phase.1))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.subheadline.bold())
                Spacer()
                Text(formatMs(timing.totalMs))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func formatMs(_ ms: Double) -> String {
        DurationFormat.abbreviated(fromMilliseconds: ms)
    }
}
