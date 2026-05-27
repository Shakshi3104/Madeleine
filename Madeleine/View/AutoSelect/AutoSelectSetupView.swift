//
//  AutoSelectSetupView.swift
//  Madeleine
//
//  Created by Mac mini M2 Pro on 2026/05/26.
//

import SwiftUI
import Photos
import UIKit

@Observable
@MainActor
final class AutoSelectSetupViewModel {
    enum Permission {
        case unknown
        case authorized
        case needsRequest
        case needsSettings
    }

    var selectedDates: Set<DateComponents>
    var targetCount: Int = 30

    var candidateCount: Int?
    var isCounting: Bool = false

    var permission: Permission = .unknown

    private let curator = AutoCurator()
    private var countTask: Task<Void, Never>?

    init() {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        self.selectedDates = [today]
    }

    var dates: [Date] {
        let cal = Calendar.current
        return selectedDates.compactMap { cal.date(from: $0) }.sorted()
    }

    func checkPermission() {
        permission = Self.classify(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        permission = Self.classify(status)
        if permission == .authorized {
            refreshCount()
        }
    }

    private static func classify(_ status: PHAuthorizationStatus) -> Permission {
        switch status {
        case .authorized: .authorized
        case .notDetermined: .needsRequest
        default: .needsSettings
        }
    }

    func refreshCount() {
        guard permission == .authorized else { return }
        countTask?.cancel()
        let dates = self.dates
        guard !dates.isEmpty else {
            candidateCount = 0
            isCounting = false
            return
        }
        isCounting = true
        countTask = Task { [curator] in
            let count = await curator.count(dates: dates)
            if Task.isCancelled { return }
            self.candidateCount = count
            self.isCounting = false
        }
    }
}

struct AutoSelectSetupView: View {
    @State private var viewModel = AutoSelectSetupViewModel()
    let onStart: ([Date], Int) -> Void

    var body: some View {
        Group {
            switch viewModel.permission {
            case .unknown:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .authorized:
                form
            case .needsRequest, .needsSettings:
                permissionPrompt
            }
        }
        .navigationTitle("Auto Select")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.checkPermission()
            if viewModel.permission == .authorized {
                viewModel.refreshCount()
            }
        }
    }

    private var form: some View {
        Form {
            Section("Dates") {
                MultiDatePicker("Dates", selection: $viewModel.selectedDates)
                    .labelsHidden()
                    .tint(.accentColor)
            }

            Section {
                candidateCountLabel
            }

            Section("Duration") {
                Picker("Duration", selection: $viewModel.targetCount) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("45s").tag(45)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Button {
                    onStart(viewModel.dates, viewModel.targetCount)
                } label: {
                    Text("Start Auto Select")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.dates.isEmpty || (viewModel.candidateCount ?? 0) == 0)
                .listRowBackground(Color.clear)
            }
        }
        .onChange(of: viewModel.selectedDates) { _, _ in viewModel.refreshCount() }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Photo Library Access Needed", systemImage: "lock.shield")
        } description: {
            Text("Auto Select needs access to your full photo library so it can find Live Photos taken on the selected dates.")
        } actions: {
            Button {
                handlePermissionAction()
            } label: {
                Text(viewModel.permission == .needsRequest ? "Allow Access" : "Open Settings")
                    .frame(minWidth: 160)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var candidateCountLabel: some View {
        HStack {
            Text("Matching Live Photos")
            Spacer()
            if viewModel.isCounting {
                ProgressView()
            } else if let count = viewModel.candidateCount {
                Text("\(count) photos")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func handlePermissionAction() {
        switch viewModel.permission {
        case .needsRequest:
            Task { await viewModel.requestPermission() }
        case .needsSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
}

#Preview {
    NavigationStack {
        AutoSelectSetupView { _, _ in }
    }
}
