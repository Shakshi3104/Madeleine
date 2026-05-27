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

    var fromDate: Date
    var toDate: Date
    var targetCount: Int = 30

    var candidateCount: Int?
    var isCounting: Bool = false

    var permission: Permission = .unknown

    private let curator = AutoCurator()
    private var countTask: Task<Void, Never>?

    init() {
        let now = Date.now
        let cal = Calendar.current
        self.toDate = now
        self.fromDate = cal.date(byAdding: .day, value: -7, to: now) ?? now
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
            Section("Date Range") {
                DatePicker(
                    "From",
                    selection: $viewModel.fromDate,
                    in: ...viewModel.toDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "To",
                    selection: $viewModel.toDate,
                    in: viewModel.fromDate...,
                    displayedComponents: .date
                )
                candidateCountLabel
            }

            Section("Count") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text("\(viewModel.targetCount) photos")
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
                    Text("Start Auto Select")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled((viewModel.candidateCount ?? 0) == 0)
                .listRowBackground(Color.clear)
            }
        }
        .onChange(of: viewModel.fromDate) { _, _ in viewModel.refreshCount() }
        .onChange(of: viewModel.toDate) { _, _ in viewModel.refreshCount() }
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Photo Library Access Needed", systemImage: "lock.shield")
        } description: {
            Text("Auto Select needs access to your full photo library so it can find Live Photos taken in the selected date range.")
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
        AutoSelectSetupView { _, _, _ in }
    }
}
