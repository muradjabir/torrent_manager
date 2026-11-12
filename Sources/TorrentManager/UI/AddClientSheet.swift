import SwiftUI
import TorrentManagerCore

public struct AddClientSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: ClientType = .deluge
    @State private var host: String = "192.168.1."
    @State private var portString: String = "8112"
    @State private var useHTTPS: Bool = false
    @State private var username: String = ""
    @State private var password: String = ""

    @State private var isTesting: Bool = false
    @State private var testResult: ConnectionTestResult?
    @State private var showResultAlert: Bool = false

    public var onSave: (ClientProfile) -> Void

    public init(onSave: @escaping (ClientProfile) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Remote Torrent Client")
                        .font(.headline)
                    Text("Connect to Deluge, Transmission, or qBittorrent on any local IP or NAS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Scrollable Form Container
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Info Box
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CLIENT CONFIGURATION")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Client Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $type) {
                                Text("Deluge (Web JSON-RPC)").tag(ClientType.deluge)
                                Text("Transmission (RPC)").tag(ClientType.transmission)
                                Text("qBittorrent (Web API)").tag(ClientType.qbittorrent)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .onChange(of: type) { _, newType in
                                portString = "\(ClientProfile.defaultPort(for: newType))"
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connection Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g. Home Server NAS, Living Room Mac", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Network Address Box
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NETWORK ADDRESS")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Host / Local IP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("192.168.1.50 or nas.local", text: $host)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Port", text: $portString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }

                        Toggle("Use Secure HTTPS / SSL", isOn: $useHTTPS)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Credentials Box
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AUTHENTICATION")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        if type != .deluge {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Username")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(type == .qbittorrent ? "admin" : "Username", text: $username)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(type == .deluge ? "Web UI Password" : "Password")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField(type == .deluge ? "Deluge Web password (default: deluge)" : "Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Prominent Status Banner
                    if let result = testResult {
                        HStack(spacing: 10) {
                            Image(systemName: result.isSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(result.isSuccessful ? .green : .red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.isSuccessful ? "Connection Succeeded!" : "Connection Failed")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(result.isSuccessful ? .green : .red)

                                Text(result.isSuccessful
                                     ? "Successfully reached \(type.displayName) (\(result.serverVersion ?? "Online"))"
                                     : (result.errorMessage ?? "Could not reach host on \(host):\(portString)"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(result.isSuccessful ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(result.isSuccessful ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Button(action: {
                    Task { await runConnectionTest() }
                }) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting...")
                        } else {
                            Image(systemName: "network")
                            Text("Test Connection")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isTesting || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Save Client") {
                    saveAndClose()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 560)
        // Success / Failure Window Alert
        .alert(
            testResult?.isSuccessful == true ? "Connection Succeeded! 🎉" : "Connection Failed ⚠️",
            isPresented: $showResultAlert,
            presenting: testResult
        ) { _ in
            Button("OK") {}
        } message: { result in
            if result.isSuccessful {
                Text("Successfully established communication with \(type.displayName)!\n\nTarget Endpoint: \(host):\(portString)\nServer Version: \(result.serverVersion ?? "Connected")")
            } else {
                Text("Unable to reach \(type.displayName) at \(host):\(portString).\n\nDetails: \(result.errorMessage ?? "Host unreachable or connection timed out.")\n\nPlease ensure the client Web UI is running, port \(portString) is open, and credentials are correct.")
            }
        }
    }

    private func buildProfile() -> ClientProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(type.displayName.components(separatedBy: " ").first ?? "Client") (\(host))"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let port = Int(portString) ?? ClientProfile.defaultPort(for: type)

        return ClientProfile(
            name: cleanName,
            type: type,
            host: host,
            port: port,
            useHTTPS: useHTTPS,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }

    @MainActor
    private func runConnectionTest() async {
        isTesting = true
        testResult = nil

        let profile = buildProfile()
        let manager = ClientManager()
        let result = await manager.testProfileConnection(profile)

        self.testResult = result
        self.isTesting = false
        // Trigger explicit success/failure window alert
        self.showResultAlert = true
    }

    private func saveAndClose() {
        let profile = buildProfile()
        onSave(profile)
        dismiss()
    }
}
