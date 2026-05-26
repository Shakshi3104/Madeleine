//
//  AutoSelectSetupView.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import SwiftUI

@Observable
@MainActor
final class AutoSelectSetupViewModel {
    var fromDate: Date
    var toDate: Date
    var targetCount: Int = 30

    var candidateCount: Int?
    var isCounting: Bool = false

    private let curator = AutoCurator()
    private var countTask: Task<Void, Never>?

    init() {
        let now = Date.now
        let cal = Calendar.current
        self.toDate = now
        self.fromDate = cal.date(byAdding: .day, value: -7, to: now) ?? now
    }

    func refreshCount() {
        countTask?.cancel()
        isCounting = true
        let from = fromDate
        let to = toDate
        countTask = Task { [curator] in
            let count = await curator.count(from: from, to: to)
            if Task.isCancelled { return }
            self.candidateCount = count
            self.isCounting = false
        }
    }
}

struct AutoSelectSetupView: View {
    @State private var viewModel = AutoSelectSetupViewModel()
    let onStart: (Date, Date, Int) -> Void

    var body: some View {
        Form {
            Section("期間") {
                DatePicker(
                    "開始",
                    selection: $viewModel.fromDate,
                    in: ...viewModel.toDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "終了",
                    selection: $viewModel.toDate,
                    in: viewModel.fromDate...,
                    displayedComponents: .date
                )
                candidateCountLabel
            }

            Section("枚数") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目標枚数")
                        Spacer()
                        Text("\(viewModel.targetCount) 枚")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.targetCount) },
                            set: { viewModel.targetCount = Int($0) }
                        ),
                        in: 10...50,
                        step: 1
                    )
                }
            }

            Section {
                Button {
                    onStart(viewModel.fromDate, viewModel.toDate, viewModel.targetCount)
                } label: {
                    Text("セレクト開始")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled((viewModel.candidateCount ?? 0) == 0)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("自動セレクト")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.fromDate) { _, _ in viewModel.refreshCount() }
        .onChange(of: viewModel.toDate) { _, _ in viewModel.refreshCount() }
        .task { viewModel.refreshCount() }
    }

    @ViewBuilder
    private var candidateCountLabel: some View {
        HStack {
            Text("対象の Live Photo")
            Spacer()
            if viewModel.isCounting {
                ProgressView()
            } else if let count = viewModel.candidateCount {
                Text("\(count) 枚")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AutoSelectSetupView { _, _, _ in }
    }
}
