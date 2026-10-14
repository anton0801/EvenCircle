import SwiftUI

/// Screen 17: export / import a full JSON backup (schema v1). Import always replaces – no merge.
struct BackupScreen: View {
    @StateObject private var vm: BackupViewModel
    @State private var confirmExport = false
    @State private var showImporter = false
    @State private var confirmReplace = false
    @State private var confirmRestore = false
    @State private var confirmDeleteCopy = false

    init(deps: AppDependencies) {
        _vm = StateObject(wrappedValue: BackupViewModel(deps: deps))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                currentData
                exportSection
                importSection
                if let copy = vm.safetyCopy {
                    safetyCopySection(copy)
                }
            }
            .padding(Spacing.screen)
        }
        .disabled(vm.isBusy)
        .overlay {
            if vm.isBusy {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    ProgressView(progressText)
                        .padding(Spacing.l)
                        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.ecSurface))
                        .foregroundColor(.ecTextPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .ecScreenBackground()
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.refresh() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await vm.validate(url) }
            case .failure: break
            }
        }
        .alert("Export backup?", isPresented: $confirmExport) {
            Button("Export Backup") { Task { await vm.export() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This backup includes names, notes and amounts. The file is not encrypted by Even Circle.")
        }
        .alert("Replace all data?", isPresented: $confirmReplace) {
            Button("Replace All Data", role: .destructive) { Task { await vm.replaceAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text((vm.counts?.isEmpty ?? true)
                 ? "The backup becomes your data. There is no merge."
                 : "Every current event is replaced by the backup. There is no merge. A safety copy of your current data is saved on this device first.")
        }
        .alert("Restore previous data?", isPresented: $confirmRestore) {
            Button("Restore Previous Data", role: .destructive) { Task { await vm.restorePrevious() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current data is replaced by the copy saved before the last import.")
        }
        .alert("Delete the previous copy?", isPresented: $confirmDeleteCopy) {
            Button("Delete Previous Copy", role: .destructive) { Task { await vm.deletePrevious() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the safety copy is deleted. Your current data stays as it is.")
        }
        .messageAlert($vm.alert)
        .toast($vm.toast)
    }

    private var progressText: String {
        switch vm.activity {
        case .exporting: return "Preparing backup…"
        case .validating: return "Checking the file…"
        case .replacing: return "Replacing data…"
        case .restoring: return "Restoring…"
        case .idle: return ""
        }
    }

    private var currentData: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "On this device")
            if let counts = vm.counts {
                LabeledValueRow(label: "Events", value: "\(counts.events)")
                LabeledValueRow(label: "People", value: "\(counts.people)")
                LabeledValueRow(label: "Expenses", value: "\(counts.expenses)")
                LabeledValueRow(label: "Payments", value: "\(counts.payments)")
            } else {
                ProgressView()
            }
            LabeledValueRow(label: "Last Export", value: vm.lastExportAt.map(DateText.timestamp) ?? "Never")
        }
        .ecCard()
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Export", subtitle: "Creates evencircle-backup-v1.json and opens the system export options.")
            InfoNote(text: "This backup includes names, notes and amounts.", icon: "exclamationmark.shield", color: .ecLilac)
            Button { confirmExport = true } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("exportBackupButton")
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Import", subtitle: "Choose a JSON backup. It is fully checked before anything changes.")
            Button { showImporter = true } label: { Label("Import Backup", systemImage: "square.and.arrow.down") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("importBackupButton")

            if let error = vm.importError {
                VStack(alignment: .leading, spacing: 4) {
                    Label("This file can't be imported", systemImage: "xmark.octagon.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.ecCoral)
                    Text(error)
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your current data has not changed.")
                        .ecCaptionFont()
                        .foregroundColor(.ecTextSecondary)
                }
                .ecCard()
            }

            if let backup = vm.pending {
                preview(backup.preview)
            }
        }
    }

    private func preview(_ preview: BackupPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Backup preview")
            LabeledValueRow(label: "Schema version", value: "\(preview.schemaVersion)")
            if let exportedAt = preview.exportedAt {
                LabeledValueRow(label: "Exported", value: DateText.timestamp(exportedAt))
            }
            LabeledValueRow(label: "Events", value: "\(preview.counts.events)")
            LabeledValueRow(label: "People", value: "\(preview.counts.people)")
            LabeledValueRow(label: "Expenses", value: "\(preview.counts.expenses)")
            LabeledValueRow(label: "Payments", value: "\(preview.counts.payments)")
            LabeledValueRow(label: "Contains sample event", value: preview.containsDemo ? "Yes" : "No")
            if !preview.events.isEmpty {
                Divider().background(Color.ecDivider)
                ForEach(preview.events) { event in
                    HStack {
                        Text(event.name)
                            .foregroundColor(.ecTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if event.isDemo { StatusChip(text: "Sample", color: .ecLilac) }
                        CurrencyChip(currency: event.currency)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            InfoNote(text: "Amounts are restored exactly. Balances are recalculated; currencies are never converted.")
                .padding(.top, Spacing.xs)
            Button("Replace All Data", role: .destructive) { confirmReplace = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Spacing.xs)
                .accessibilityIdentifier("replaceAllDataButton")
            Button("Cancel") { vm.cancelImport() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .ecCard()
    }

    private func safetyCopySection(_ copy: SafetyCopyInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: "Previous Data", subtitle: "Saved automatically before the last import on \(DateText.timestamp(copy.createdAt)). Kept until the next import, deletion or reset.")
            Button { confirmRestore = true } label: { Label("Restore Previous Data", systemImage: "clock.arrow.circlepath") }
                .buttonStyle(SecondaryButtonStyle())
            Button(role: .destructive) { confirmDeleteCopy = true } label: { Label("Delete Previous Copy", systemImage: "trash") }
                .buttonStyle(SecondaryButtonStyle(tint: .ecCoral))
        }
    }
}
