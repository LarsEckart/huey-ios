import HueCore
import SwiftUI

struct LampsView: View {
    @StateObject private var viewModel: LampsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var didEnterForeground = false
    let onResetPairing: () -> Void

    init(updater: HueGroupUpdater, onResetPairing: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: LampsViewModel(updater: updater))
        self.onResetPairing = onResetPairing
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Rooms / zones") {
                    if viewModel.groups.isEmpty {
                        Text(viewModel.isRefreshing ? "Loading…" : "No rooms or zones found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.groups) { group in
                            GroupToggleRow(
                                group: group,
                                isBusy: viewModel.isBusy(groupID: group.id),
                                onChange: { newValue in
                                    Task {
                                        await viewModel.set(groupID: group.id, on: newValue)
                                    }
                                },
                                onBrightnessChange: { newValue in
                                    Task {
                                        await viewModel.setBrightness(groupID: group.id, brightness: newValue)
                                    }
                                }
                            )
                        }
                    }
                }

                Section {
                    Button("Refresh") {
                        Task {
                            await viewModel.refresh()
                        }
                    }

                    Button("Reset pairing", role: .destructive) {
                        onResetPairing()
                    }
                }
            }
            .navigationTitle("Huey iOS")
            .task {
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                // Skip the first active transition: the initial load already
                // happened via .task when the view first appeared.
                guard didEnterForeground else {
                    didEnterForeground = true
                    return
                }
                Task {
                    await viewModel.refresh()
                }
            }
            .alert(
                "Hue Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .overlay {
                if viewModel.isRefreshing && viewModel.groups.isEmpty {
                    ProgressView("Loading rooms and zones…")
                }
            }
        }
    }
}
