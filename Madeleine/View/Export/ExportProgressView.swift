//
//  ExportProgressView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI

struct ExportProgressView: View {
    let progress: Double
    let isComplete: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("Export Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Your vlog has been saved to Camera Roll.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                ProgressView(value: progress) {
                    Text("Exporting…")
                        .font(.headline)
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
    }
}
