import SwiftUI

@MainActor
private final class LampsViewModel: ObservableObject {
    @Published private(set) var groups: [HueGroup] = []
    @Published private(set) var busyGroupIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let client: HueBridgeClient

    init(client: HueBridgeClient) {
        self.client = client
    }

    func isBusy(groupID: String) -> Bool {
        busyGroupIDs.contains(groupID)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let allGroups = try await client.fetchGroups()
            groups = allGroups
                .filter { group in
                    let normalizedType = group.type.lowercased()
                    return normalizedType == "room" || normalizedType == "zone"
                }
                .sorted {
                    if $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedSame {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.id < $1.id
                }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func set(groupID: String, on: Bool) async {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        busyGroupIDs.insert(groupID)
        defer { busyGroupIDs.remove(groupID) }

        let previousState = groups[index].anyOn
        groups[index].anyOn = on

        do {
            try await client.setGroupState(groupID: groupID, on: on)
        } catch {
            groups[index].anyOn = previousState
            errorMessage = error.localizedDescription
        }
    }
}

struct RootView: View {
    @AppStorage("hue.bridgeIP") private var bridgeIP = ""
    @AppStorage("hue.username") private var username = ""

    var body: some View {
        if bridgeIP.isEmpty || username.isEmpty {
            SetupView(bridgeIP: $bridgeIP, username: $username)
        } else {
            LampsView(
                bridgeIP: bridgeIP,
                username: username,
                onResetPairing: {
                    bridgeIP = ""
                    username = ""
                }
            )
        }
    }
}

private struct SetupView: View {
    @Binding var bridgeIP: String
    @Binding var username: String

    @State private var enteredBridgeIP = ""
    @State private var statusMessage = "Enter your bridge IP, press your bridge button, then tap Pair."
    @State private var isPairing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bridge") {
                    TextField("192.168.1.x", text: $enteredBridgeIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)

                    Button(isPairing ? "Pairing..." : "Pair") {
                        pair()
                    }
                    .disabled(isPairing || enteredBridgeIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Huey iOS")
            .alert("Pairing failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func pair() {
        let ip = enteredBridgeIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            statusMessage = "Please enter a bridge IP address."
            return
        }

        isPairing = true
        statusMessage = "Trying to pair… make sure the bridge button was pressed in the last 30 seconds."

        Task {
            do {
                let client = HueBridgeClient(bridgeIP: ip, username: "")
                let pairedUsername = try await client.register(deviceType: "huey-ios#iphone")
                bridgeIP = ip
                username = pairedUsername
                isPairing = false
            } catch {
                isPairing = false
                statusMessage = "Pairing failed. Try again after pressing the bridge button."
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LampsView: View {
    @StateObject private var viewModel: LampsViewModel
    let onResetPairing: () -> Void

    init(bridgeIP: String, username: String, onResetPairing: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: LampsViewModel(client: HueBridgeClient(bridgeIP: bridgeIP, username: username)))
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
            .alert("Hue Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
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

private struct GroupToggleRow: View {
    let group: HueGroup
    let isBusy: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { group.anyOn },
                set: onChange
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text("\(group.type) • id \(group.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isBusy)
    }
}

#Preview {
    RootView()
}
