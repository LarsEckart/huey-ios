import SwiftUI

struct SetupView: View {
    @Binding var bridgeIP: String
    @Binding var username: String

    @State private var enteredBridgeIP = ""
    @State private var discoveredBridges: [HueBridge] = []
    @State private var selectedBridgeID = ""
    @State private var statusMessage = "Looking for your Hue bridge…"
    @State private var isDiscovering = false
    @State private var isPairing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bridge") {
                    if isDiscovering {
                        ProgressView("Searching for Hue bridges…")
                    }

                    if discoveredBridges.count > 1 {
                        Picker("Detected bridge", selection: $selectedBridgeID) {
                            ForEach(discoveredBridges) { bridge in
                                Text(bridge.displayName).tag(bridge.id)
                            }
                        }
                        .onChange(of: selectedBridgeID) { _, newID in
                            selectBridge(withID: newID)
                        }
                    }

                    TextField("192.168.1.x", text: $enteredBridgeIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)

                    Button(pairButtonTitle) {
                        pair()
                    }
                    .disabled(isBusy || enteredBridgeIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Huey iOS")
            .task {
                await discoverBridgesIfNeeded()
            }
            .alert(
                "Pairing failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isBusy: Bool {
        isDiscovering || isPairing
    }

    private var pairButtonTitle: String {
        if isPairing {
            return username.isEmpty ? "Pairing…" : "Saving…"
        }
        return username.isEmpty ? "Pair" : "Use Saved Pairing"
    }

    @MainActor
    private func discoverBridgesIfNeeded() async {
        guard !isDiscovering, discoveredBridges.isEmpty, enteredBridgeIP.isEmpty else {
            return
        }

        isDiscovering = true
        statusMessage = "Looking for your Hue bridge…"
        defer { isDiscovering = false }

        do {
            let bridges = try await HueBridgeDiscoveryClient().discover()
            applyDiscoveredBridges(bridges)
        } catch {
            statusMessage = "Automatic discovery failed. Enter your bridge IP manually."
        }
    }

    @MainActor
    private func applyDiscoveredBridges(_ bridges: [HueBridge]) {
        discoveredBridges = bridges

        switch bridges.count {
        case 0:
            statusMessage = "No bridge found automatically. Enter your bridge IP manually."
        case 1:
            enteredBridgeIP = bridges[0].internalIPAddress
            if username.isEmpty {
                statusMessage =
                    "Found bridge at \(bridges[0].internalIPAddress). Press the bridge button, then tap Pair."
            } else {
                bridgeIP = bridges[0].internalIPAddress
            }
        default:
            selectedBridgeID = bridges[0].id
            enteredBridgeIP = bridges[0].internalIPAddress
            statusMessage =
                username.isEmpty
                ? "Choose your bridge, press its button, then tap Pair."
                : "Choose your bridge, then tap Use Saved Pairing."
        }
    }

    private func selectBridge(withID id: String) {
        guard let bridge = discoveredBridges.first(where: { $0.id == id }) else {
            return
        }
        enteredBridgeIP = bridge.internalIPAddress
    }

    private func pair() {
        let ip = enteredBridgeIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            statusMessage = "Please enter a bridge IP address."
            return
        }

        if !username.isEmpty {
            bridgeIP = ip
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
