import SwiftUI

private enum LampTarget: String, CaseIterable, Identifiable {
    case office
    case bedside

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .office:
            "Office"
        case .bedside:
            "Bedside"
        }
    }

    var lookupKeywords: [String] {
        switch self {
        case .office:
            ["office"]
        case .bedside:
            ["bedside", "bed side"]
        }
    }
}

@MainActor
private final class LampsViewModel: ObservableObject {
    @Published private(set) var groupsByTarget: [LampTarget: HueGroup] = [:]
    @Published private(set) var otherGroups: [HueGroup] = []
    @Published private(set) var busyTargets: Set<LampTarget> = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let client: HueBridgeClient

    init(client: HueBridgeClient) {
        self.client = client
    }

    func group(for target: LampTarget) -> HueGroup? {
        groupsByTarget[target]
    }

    func isBusy(_ target: LampTarget) -> Bool {
        busyTargets.contains(target)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let groups = try await client.fetchGroups()
            let roomOrZoneGroups = groups.filter { group in
                let normalizedType = group.type.lowercased()
                return normalizedType == "room" || normalizedType == "zone"
            }

            var newGroupsByTarget: [LampTarget: HueGroup] = [:]
            var usedGroupIDs = Set<String>()

            for target in LampTarget.allCases {
                if let match = roomOrZoneGroups.first(where: { group in
                    target.lookupKeywords.contains(where: { keyword in
                        group.name.localizedCaseInsensitiveContains(keyword)
                    }) && !usedGroupIDs.contains(group.id)
                }) {
                    newGroupsByTarget[target] = match
                    usedGroupIDs.insert(match.id)
                }
            }

            groupsByTarget = newGroupsByTarget
            otherGroups = roomOrZoneGroups
                .filter { !usedGroupIDs.contains($0.id) }
                .sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func set(_ target: LampTarget, on: Bool) async {
        guard var group = groupsByTarget[target] else {
            return
        }

        busyTargets.insert(target)
        defer { busyTargets.remove(target) }

        let previousState = group.anyOn
        group.anyOn = on
        groupsByTarget[target] = group

        do {
            try await client.setGroupState(groupID: group.id, on: on)
        } catch {
            group.anyOn = previousState
            groupsByTarget[target] = group
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
                Section("Quick toggles") {
                    ForEach(LampTarget.allCases) { target in
                        LampToggleRow(
                            target: target,
                            group: viewModel.group(for: target),
                            isBusy: viewModel.isBusy(target),
                            onChange: { newValue in
                                Task {
                                    await viewModel.set(target, on: newValue)
                                }
                            }
                        )
                    }
                }

                if !viewModel.otherGroups.isEmpty {
                    Section("Other rooms / zones") {
                        ForEach(viewModel.otherGroups) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                Text("\(group.type) • id \(group.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                if viewModel.isRefreshing,
                   LampTarget.allCases.allSatisfy({ viewModel.group(for: $0) == nil }) {
                    ProgressView("Loading rooms and zones…")
                }
            }
        }
    }
}

private struct LampToggleRow: View {
    let target: LampTarget
    let group: HueGroup?
    let isBusy: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        if let group {
            Toggle(
                isOn: Binding(
                    get: { group.anyOn },
                    set: onChange
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                    Text("\(group.name) • \(group.type)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isBusy)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                    Text("No matching Room/Zone found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootView()
}
