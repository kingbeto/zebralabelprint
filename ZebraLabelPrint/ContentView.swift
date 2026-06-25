import AppKit
import SwiftUI

private enum AppTitle {
    static let name = "Zebra Label Print"
}

struct ContentView: View {
    @StateObject private var viewModel = PrintViewModel()
    @State private var isChecklistManuallyExpanded = false

    private var isChecklistExpanded: Bool {
        !viewModel.isSetupChecklistComplete || isChecklistManuallyExpanded
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            controlsPanel
                .frame(width: 380) // fixed sidebar, preview takes the rest
                .padding(24)

            Divider()

            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1640, minHeight: 1040)
        .onAppear {
            viewModel.onAppear()
            updateWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshRequirements()
        }
        .onChange(of: viewModel.selectedPrinter) { printer in
            viewModel.persistPrinter(printer)
            viewModel.updatePrintDefinition()
            viewModel.refreshRequirements()
            Task { await viewModel.loadPreview() }
        }
        .onChange(of: viewModel.selectedLabelSizeId) { _ in
            viewModel.persistLabelSize()
            viewModel.updatePrintDefinition()
            Task { await viewModel.loadPreview() }
        }
        .onChange(of: viewModel.horizontalOffsetMM) { _ in
            viewModel.persistHorizontalOffset()
            viewModel.schedulePreviewRefresh()
        }
        .onChange(of: viewModel.isSetupChecklistComplete) { complete in
            if complete {
                isChecklistManuallyExpanded = false
            }
        }
        // seperate alerts — success vs failure messages got messy in one
        .alert("Print job sent", isPresented: $viewModel.showSuccessAlert) {
            Button("Close", role: .cancel) {}
        } message: {
            if let file = viewModel.selectedFileURL {
                let count = viewModel.labelsToPrintCount
                let labelPhrase = count == 1 ? "1 label" : "\(count) labels"
                Text("\"\(file.lastPathComponent)\" (\(labelPhrase)) was sent to \(viewModel.selectedPrinter).")
            }
        }
        .alert("Print failed", isPresented: $viewModel.showErrorAlert) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(AppTitle.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                    Text("ZPL file")
                    .font(.headline)

                HStack {
                    Text(viewModel.selectedFileURL?.lastPathComponent ?? "No file selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(viewModel.selectedFileURL == nil ? .secondary : .primary)

                    Spacer()

                    Button("Choose…") {
                        viewModel.selectFile()
                    }
                }

                if !viewModel.labelsToPrintSummary.isEmpty {
                    Text(viewModel.labelsToPrintSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Printer")
                    .font(.headline)

                if viewModel.printers.isEmpty {
                    Text("No printers available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Printer", selection: $viewModel.selectedPrinter) {
                        ForEach(viewModel.printers, id: \.self) { printer in
                            Text(printer).tag(printer)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if !viewModel.selectedPrinter.isEmpty {
                    PrinterQueueStatusBanner(
                        status: viewModel.printerQueueStatus,
                        onResume: { viewModel.resumeSelectedPrinter() }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Label size")
                    .font(.headline)

                Picker("Label size", selection: $viewModel.selectedLabelSizeId) {
                    ForEach(ZebraLabelSizeOption.standardSizes) { size in
                        Text(size.name).tag(size.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Print definition")
                    .font(.headline)

                Text(viewModel.printDefinitionInfo.isEmpty
                    ? "Select a printer to see DPMM."
                    : viewModel.printDefinitionInfo)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Horizontal offset")
                    .font(.headline)

                HStack(spacing: 12) {
                    Slider(
                        value: $viewModel.horizontalOffsetMM,
                        in: -10...10,
                        step: 0.5
                    )

                    Text(String(format: "%+.1f mm", viewModel.horizontalOffsetMM))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }

                HStack {
                    Text("Positive moves content to the right.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reset") {
                        viewModel.resetHorizontalOffset()
                    }
                    .disabled(viewModel.horizontalOffsetMM == 0)
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
                .font(.title3)
                .frame(minWidth: 120, minHeight: 44)

                Spacer()

                Button("Print") {
                    viewModel.printFile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canPrint)
                .help(viewModel.printBlockedReason ?? "Send the label file to the selected printer.")
                .font(.title3)
                .frame(minWidth: 120, minHeight: 44)
            }
            .padding(.top, 28)
                }
            }

            RequirementsPanel(
                viewModel: viewModel,
                isExpanded: isChecklistExpanded,
                onExpand: { isChecklistManuallyExpanded = true },
                onCollapse: { isChecklistManuallyExpanded = false }
            )
        }
        .padding(24)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Button("Refresh") {
                    Task { await viewModel.loadPreview() }
                }
                .disabled(viewModel.selectedFileURL == nil || viewModel.isLoadingPreview)
            }

            Text("Rendered with Labelary. Output on your Zebra may differ slightly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.previewLabelInfo.isEmpty {
                Text(viewModel.previewLabelInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.previewLimitMessage.isEmpty {
                Text(viewModel.previewLimitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                if viewModel.isLoadingPreview {
                    ProgressView("Rendering preview…")
                } else if !viewModel.previewImages.isEmpty {
                    LabelPreviewContainer(
                        images: viewModel.previewImages,
                        labelSizeInches: viewModel.previewLabelSizeInches
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !viewModel.previewError.isEmpty {
                    Text(viewModel.previewError)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(24)
                } else {
                    Text("Select a ZPL file to see a preview.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }

    private func updateWindowTitle() {
        // SwiftUI doesnt always set the titlebar text on macOS 13
        for window in NSApplication.shared.windows {
            window.title = AppTitle.name
        }
    }
}

#Preview {
    ContentView()
}

private struct RequirementsPanel: View {
    @ObservedObject var viewModel: PrintViewModel
    let isExpanded: Bool
    let onExpand: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isSetupChecklistComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(viewModel.isSetupChecklistComplete ? .green : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup checklist")
                        .font(.headline)

                    if !isExpanded {
                        Text(
                            viewModel.isSetupChecklistComplete
                                ? "All checks passed"
                                : "Action required"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isExpanded {
                    Button("Check again") {
                        viewModel.refreshRequirements()
                    }
                    .disabled(viewModel.isCheckingRequirements)

                    if viewModel.isSetupChecklistComplete {
                        Button {
                            onCollapse()
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Collapse checklist")
                    }
                } else {
                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: "chevron.up.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Expand checklist")
                }
            }

            if isExpanded {
                if viewModel.isCheckingRequirements {
                    ProgressView()
                        .controlSize(.small)
                }

                ForEach(viewModel.requirements) { requirement in
                    HStack(alignment: .top, spacing: 8) {
                        RequirementRow(requirement: requirement)

                        if requirement.id == "cups" {
                            Button {
                                viewModel.refreshCUPSChecklistItem()
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(
                                requirement.status == .passed
                                    ? "Refresh CUPS status"
                                    : "Restart CUPS (local administrator password required)"
                            )
                            .disabled(viewModel.isRestartingCUPS || viewModel.isCheckingRequirements)
                        }

                        if requirement.id == "printer_ready", requirement.status != .passed {
                            Button {
                                viewModel.resumeSelectedPrinter()
                            } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Resume printer queue")
                            .disabled(viewModel.isCheckingRequirements)
                        }
                    }
                }

                if viewModel.needsZebraSetupHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Printer setup is required by Zebra and macOS, not by this app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Zebra driver guide") {
                                viewModel.openZebraDriverGuide()
                            }

                            Button("Printer settings") {
                                viewModel.openPrinterSettings()
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    viewModel.isSetupChecklistComplete
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color.orange.opacity(0.10)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    viewModel.isSetupChecklistComplete
                        ? Color.green.opacity(0.35)
                        : Color.orange.opacity(0.35),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

private struct PrinterQueueStatusBanner: View {
    let status: PrinterQueueStatus
    let onResume: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.shortLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if status == .paused {
                Button("Resume") {
                    onResume()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var iconName: String {
        switch status {
        case .ready:
            return "checkmark.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .offline:
            return "wifi.slash"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .ready:
            return .green
        case .paused:
            return .orange
        case .offline:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .ready:
            return Color.green.opacity(0.10)
        case .paused:
            return Color.orange.opacity(0.12)
        case .offline:
            return Color.red.opacity(0.10)
        case .unknown:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch status {
        case .ready:
            return Color.green.opacity(0.35)
        case .paused:
            return Color.orange.opacity(0.45)
        case .offline:
            return Color.red.opacity(0.40)
        case .unknown:
            return Color.primary.opacity(0.10)
        }
    }
}

private struct RequirementRow: View {
    let requirement: SetupRequirement

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(requirement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconName: String {
        switch requirement.status {
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch requirement.status {
        case .passed:
            return .green
        case .failed:
            return .red
        case .warning:
            return .orange
        }
    }
}
