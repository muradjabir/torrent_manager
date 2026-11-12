import SwiftUI
import TorrentManagerCore

public struct AddIndexerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "Custom REST Indexer"
    @State private var type: IndexerType = .customAPI
    @State private var urlString: String = ""
    @State private var apiKey: String = ""

    @State private var isTesting: Bool = false
    @State private var testMessage: String?
    @State private var testSucceeded: Bool = false

    public var onSave: (IndexerProfile) -> Void

    public init(onSave: @escaping (IndexerProfile) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Custom Torrent Indexer")
                        .font(.headline)
                    Text("Connect to a custom REST API provider or Torznab feed (Jackett / Prowlarr)")
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

            Form {
                Section("Provider Specification") {
                    Picker("Provider Type", selection: $type) {
                        Text("Custom REST / JSON API Provider").tag(IndexerType.customAPI)
                        Text("Torznab Feed (Jackett / Prowlarr)").tag(IndexerType.torznab)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: type) { _, newType in
                        if newType == .customAPI {
                            name = "Custom REST Indexer"
                            urlString = ""
                        } else {
                            name = "Torznab Feed"
                            urlString = "http://localhost:9696/"
                        }
                    }

                    TextField("Display Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Endpoint Address") {
                    TextField(type == .customAPI ? "e.g. https://api.indexer.net or http://localhost:5000" : "e.g. http://localhost:9696", text: $urlString)
                        .textFieldStyle(.roundedBorder)

                    if type == .torznab {
                        SecureField("Torznab API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let msg = testMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSucceeded ? .green : .red)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(testSucceeded ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            HStack {
                Button(action: {
                    Task { await testIndexer() }
                }) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing...")
                        } else {
                            Image(systemName: "network")
                            Text("Test Feed")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Save Indexer") {
                    let profile = IndexerProfile(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Indexer" : name,
                        type: type,
                        endpointURLString: urlString,
                        apiKey: apiKey,
                        isEnabled: true,
                        isBuiltIn: false
                    )
                    onSave(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500, height: 420)
    }

    private func testIndexer() async {
        isTesting = true
        testMessage = nil

        let profile = IndexerProfile(
            name: name,
            type: type,
            endpointURLString: urlString,
            apiKey: apiKey
        )

        let manager = IndexerManager()
        guard let indexer = await manager.makeIndexer(for: profile) else {
            testMessage = "Invalid endpoint URL"
            testSucceeded = false
            isTesting = false
            return
        }

        do {
            let res = try await indexer.search(query: "test", category: .all, limit: 3)
            testMessage = "Success! Retrieved \(res.count) test items from \(name)."
            testSucceeded = true
        } catch {
            testMessage = "Failed: \(error.localizedDescription)"
            testSucceeded = false
        }
        isTesting = false
    }
}

