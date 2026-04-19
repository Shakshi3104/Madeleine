//
//  PreviewView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import AVKit

struct PreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    @Namespace private var glassNS

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottom) {
                playbackControls
                    .padding(.bottom, 40)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        GlassEffectContainer {
            HStack(spacing: 20) {
                Button {
                    player?.seek(to: .zero)
                    player?.play()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 44, height: 44)
                }
                .glassEffect()
                .glassEffectID("restart", in: glassNS)

                Button {
                    player?.play()
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 44, height: 44)
                }
                .glassEffect()
                .glassEffectID("play", in: glassNS)

                Button {
                    player?.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .frame(width: 44, height: 44)
                }
                .glassEffect()
                .glassEffectID("pause", in: glassNS)
            }
        }
    }
}
