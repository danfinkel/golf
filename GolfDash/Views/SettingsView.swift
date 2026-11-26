import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: SyncService

    var body: some View {
        NavigationStack {
            Form {
                Section("TrackMan account") {
                    Text(session.displayName ?? "Signed in")
                }
                Section {
                    if let last = sync.lastSynced {
                        LabeledContent("Last synced") {
                            Text(last, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    Button {
                        Task { await sync.sync(session: session, context: context, fullResync: true) }
                    } label: {
                        HStack {
                            Text("Full resync")
                            if sync.isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(sync.isSyncing)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Refresh fetches only new rounds and sessions. Full resync downloads your whole history again.")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        sync.clearCache(context: context)
                        Task {
                            await session.signOut()
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Signing out removes your TrackMan tokens from the Keychain and deletes the cached data on this phone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
