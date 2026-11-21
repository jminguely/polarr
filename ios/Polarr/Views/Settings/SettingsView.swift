import SwiftUI
import SwiftData

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var serverURL: String = ""
    @State private var apiKey: String = ""
    @State private var connectionStatus: String?
    @State private var isTesting: Bool = false
    @Bindable var syncManager = SyncManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.bgPrimary.ignoresSafeArea()

                Form {
                    Section("Polarr Cloud Backend") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server URL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BrandTheme.textMuted)
                            TextField("http://192.168.1.100:8080", text: $serverURL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .foregroundStyle(BrandTheme.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BrandTheme.textMuted)
                            SecureField("Enter API Key", text: $apiKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(BrandTheme.textPrimary)
                        }

                        HStack {
                            Button("Test Connection") {
                                testConnection()
                            }
                            .foregroundStyle(BrandTheme.cyan)
                            .disabled(isTesting)

                            Spacer()

                            if isTesting {
                                ProgressView().scaleEffect(0.8)
                            } else if let status = connectionStatus {
                                Text(status)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(status.contains("Success") ? BrandTheme.emerald : BrandTheme.rose)
                            }
                        }
                    }
                    .listRowBackground(BrandTheme.bgCard)

                    Section("Device & Sync") {
                        HStack {
                            Text("Device ID")
                            Spacer()
                            Text(APIClient.shared.deviceId)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(BrandTheme.textMuted)
                        }

                        if let lastSync = syncManager.lastSyncTime {
                            HStack {
                                Text("Last Synced")
                                Spacer()
                                Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12))
                                    .foregroundStyle(BrandTheme.textMuted)
                            }
                        }

                        Button {
                            saveSettings()
                            Task {
                                await syncManager.sync(modelContext: modelContext)
                            }
                        } label: {
                            HStack {
                                Text("Sync Now")
                                Spacer()
                                if syncManager.isSyncing {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                            .foregroundStyle(BrandTheme.cyan)
                        }
                    }
                    .listRowBackground(BrandTheme.bgCard)

                    Section("About") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("2.0 (Native iOS)")
                                .foregroundStyle(BrandTheme.textMuted)
                        }
                        HStack {
                            Text("Architecture")
                            Spacer()
                            Text("SwiftUI + SwiftData + AVPlayer")
                                .foregroundStyle(BrandTheme.textMuted)
                        }
                    }
                    .listRowBackground(BrandTheme.bgCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .foregroundStyle(BrandTheme.cyan)
                }
            }
            .onAppear {
                serverURL = APIClient.shared.serverURL
                apiKey = APIClient.shared.apiKey
            }
        }
    }

    private func saveSettings() {
        APIClient.shared.serverURL = serverURL
        APIClient.shared.apiKey = apiKey
    }

    private func testConnection() {
        saveSettings()
        isTesting = true
        connectionStatus = nil

        Task {
            do {
                _ = try await APIClient.shared.fetchStatsOverview()
                isTesting = false
                connectionStatus = "Connected Successfully!"
            } catch {
                isTesting = false
                connectionStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
