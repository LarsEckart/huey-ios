import SwiftUI

struct SetupView: View {
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
