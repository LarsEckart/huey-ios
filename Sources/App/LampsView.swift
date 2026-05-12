import SwiftUI

struct LampsView: View {
    @StateObject private var viewModel: LampsViewModel
    let onResetPairing: () -> Void

    init(bridgeIP: String, username: String, onResetPairing: @escaping () -> Void) {
        _viewModel = StateObject(
            wrappedValue: LampsViewModel(client: HueBridgeClient(bridgeIP: bridgeIP, username: username)))
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
