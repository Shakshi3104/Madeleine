//
//  AutoSelectingView.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import SwiftUI

@Observable
@MainActor
final class AutoSelectingViewModel {
    var stage: AutoCurator.Stage = .fetching
    var percent: Double = 0

    private var currentTask: Task<Void, Never>?

    func start(
        dates: [Date],
        targetCount: Int,
        onCompleted: @escaping @MainActor ([AutoCurator.CuratedClip]) -> Void,
        onCancelled: @escaping @MainActor () -> Void,
        onFailed: @escaping @MainActor (Error) -> Void
    ) {
        currentTask?.cancel()
        let curator = AutoCurator()
        currentTask = Task { @MainActor in
            do {
                let clips = try await curator.curate(
                    dates: dates,
                    targetCount: targetCount,
                    progress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.stage = progress.stage
                            self.percent = progress.percent
                        }
                    }
                )
                if !Task.isCancelled {
                    onCompleted(clips)
                }
            } catch is CancellationError {
                // silent: cancellation is initiated by the Cancel button
                // (which also calls onCancelled itself) or by the view dismissing.
                // We don't fire onCancelled here, otherwise swipe-back from the
                // parent would re-trigger navigation past the parent.
            } catch {
                onFailed(error)
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
    }
}

struct AutoSelectingView: View {
    let dates: [Date]
    let targetCount: Int
    let onCompleted: ([AutoCurator.CuratedClip]) -> Void
    let onCancelled: () -> Void
    let onFailed: (Error) -> Void

    @State private var viewModel = AutoSelectingViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 20) {
                Text("Finding the best moments from your trip")
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)

                ProgressView(value: viewModel.percent)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 40)
                    .animation(.default, value: viewModel.percent)

                Text(stageTitle(for: viewModel.stage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.default, value: viewModel.stage)
            }

            Spacer()

            Button {
                viewModel.cancel()
                onCancelled()
            } label: {
                Text("Cancel")
                    .frame(width: 200, height: 50)
                    .fontWeight(.medium)
            }
            .glassEffect(.regular.interactive())
            .padding(.bottom, 40)
        }
        .padding(.horizontal)
        .navigationBarBackButtonHidden()
        .task {
            viewModel.start(
                dates: dates,
                targetCount: targetCount,
                onCompleted: onCompleted,
                onCancelled: onCancelled,
                onFailed: onFailed
            )
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private func stageTitle(for stage: AutoCurator.Stage) -> String {
        switch stage {
        case .fetching: "Gathering Live Photos…"
        case .clustering: "Grouping by scene…"
        case .scoring: "Scoring clip quality…"
        case .selecting: "Picking the best cuts…"
        }
    }
}

#Preview {
    NavigationStack {
        AutoSelectingView(
            dates: [.now],
            targetCount: 30,
            onCompleted: { _ in },
            onCancelled: {},
            onFailed: { _ in }
        )
    }
}
