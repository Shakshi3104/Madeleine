//
//  AboutView.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/05/02.
//

import SwiftUI

struct AboutView: View {
    private static let websiteURL = URL(string: "https://shakshi3104.github.io/Madeleine/")!
    private static let privacyURL = URL(string: "https://shakshi3104.github.io/Madeleine/privacy.html")!
    private static let githubURL = URL(string: "https://github.com/Shakshi3104/Madeleine")!
    private static let supportURL = URL(string: "https://github.com/Shakshi3104/Madeleine/issues")!

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link(destination: Self.privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: Self.websiteURL) {
                        Label("Website", systemImage: "globe")
                    }
                    Link(destination: Self.githubURL) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: Self.supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                }

                Section {
                    VStack(spacing: 4) {
                        Text("Madeleine")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(versionText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    AboutView()
}
