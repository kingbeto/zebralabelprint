import AppKit
import SwiftUI

private enum AppTitle {
    static let name = "Zebra Label Print"
}

private enum AppLayout {
    static let controlsWidth: CGFloat = 460
    static let panelPadding: CGFloat = 24
    static let minWindowWidth: CGFloat = 1280
    static let minWindowHeight: CGFloat = 1040
    static let printScopeOptionsHeight: CGFloat = 28
    static let printScopeHintHeight: CGFloat = 32
}

struct ContentView: View {
    @StateObject private var viewModel = PrintViewModel()
    @State private var isChecklistManuallyExpanded = false
    @State private var isAdvancedExpanded = false

    private var isChecklistExpanded: Bool {
        !viewModel.isSetupChecklistComplete || isChecklistManuallyExpanded
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            controlsPanel
                .frame(width: AppLayout.controlsWidth)
                .padding(AppLayout.panelPadding)

            Divider()

            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: AppLayout.minWindowWidth, minHeight: AppLayout.minWindowHeight)
        .onAppear {
            viewModel.onAppear()
            updateWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshRequirements()
        }
        .onChange(of: viewModel.selectedPrinter) { printer in
            viewModel.persistPrinter(printer)
            viewModel.refreshRequirements()
            Task { await viewModel.loadPreview() }
        }
        .onChange(of: viewModel.selectedLabelSizeId) { _ in
            viewModel.persistLabelSize()
            Task { await viewModel.loadPreview() }
        }
        .onChange(of: viewModel.selectedResolutionId) { _ in
            viewModel.persistResolution()
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
                let count = viewModel.lastPrintedLabelCount
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppTitle.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    sourceSection
                    outputSection
                    advancedSection
                }
                .padding(.bottom, 8)
            }

            actionFooter
        }
    }

    // MARK: - Settings sections

    private var sourceSection: some View {
        GroupBox(label: sectionLabel("Source", systemImage: "doc.text")) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("ZPL file")

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

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Print labels")

                    Picker("Print labels", selection: $viewModel.printScope) {
                        ForEach(PrintLabelScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    PrintScopeOptionsRow(
                        printScope: viewModel.printScope,
                        printRangeFrom: $viewModel.printRangeFrom,
                        printRangeTo: $viewModel.printRangeTo,
                        printPagesText: $viewModel.printPagesText
                    )

                    Text(viewModel.printSelectionHint.isEmpty ? " " : viewModel.printSelectionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: AppLayout.printScopeHintHeight,
                            alignment: .topLeading
                        )
                        .opacity(viewModel.printSelectionHint.isEmpty ? 0 : 1)
                }
                .disabled(!viewModel.isPrintLabelSelectionEnabled)
                .onChange(of: viewModel.printRangeFrom) { _ in
                    viewModel.clampPrintRange()
                }
                .onChange(of: viewModel.printRangeTo) { _ in
                    viewModel.clampPrintRange()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var outputSection: some View {
        GroupBox(label: sectionLabel("Output", systemImage: "printer")) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Printer")

                    if viewModel.printers.isEmpty {
                        Text("No printers available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Printer", selection: $viewModel.selectedPrinter) {
                            ForEach(viewModel.printersForPicker, id: \.self) { printer in
                                Text(viewModel.printerDisplayName(printer)).tag(printer)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Label size")

                    Picker("Label size", selection: $viewModel.selectedLabelSizeId) {
                        ForEach(ZebraLabelSizeOption.standardSizes) { size in
                            Text(size.name).tag(size.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Print resolution")

                    Picker("Print resolution", selection: $viewModel.selectedResolutionId) {
                        ForEach(ZebraPrintResolutionOption.allOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text(viewModel.resolutionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Preview and horizontal offset use this setting. The printer uses its own native resolution for output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Horizontal offset")

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        } label: {
            sectionLabel("Advanced", systemImage: "slider.horizontal.3")
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Footer (status + primary actions)

    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            statusSection

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Spacer()

                Button("Print") {
                    Task { await viewModel.printFile() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canPrint)
                .help(viewModel.printBlockedReason ?? "Send the label file to the selected printer.")
            }
        }
        .padding(.top, 12)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.selectedPrinter.isEmpty {
                PrinterQueueStatusBanner(
                    status: viewModel.printerQueueStatus,
                    pendingJobCount: viewModel.pendingJobCount,
                    isRefreshing: viewModel.isCheckingRequirements,
                    onRefresh: { viewModel.refreshSetupStatus() },
                    onResume: { viewModel.resumeSelectedPrinter() },
                    onPause: { viewModel.pauseSelectedPrinter() },
                    onCancelJobs: { viewModel.cancelSelectedPrinterJobs() }
                )
            }

            if viewModel.isPollingSetupStatus {
                Text("Checking again — the printer may take a moment to come online. Please stand by.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RequirementsPanel(
                viewModel: viewModel,
                isExpanded: isChecklistExpanded,
                onExpand: { isChecklistManuallyExpanded = true },
                onCollapse: { isChecklistManuallyExpanded = false }
            )
        }
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
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

            Label("Preview sends your label data to labelary.com over the network.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                }

            if viewModel.labelsToPrintCount > 1 {
                HStack(spacing: 12) {
                    Text("Preview label")
                        .font(.subheadline)

                    Spacer()

                    Button {
                        viewModel.stepPreviewLabel(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.previewLabelNumber <= 1 || viewModel.isLoadingPreview)

                    TextField("Label", value: $viewModel.previewLabelNumber, format: .number)
                        .frame(width: 52)
                        .multilineTextAlignment(.center)
                        .disabled(viewModel.isLoadingPreview)

                    Text("of \(viewModel.labelsToPrintCount)")
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.stepPreviewLabel(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        viewModel.previewLabelNumber >= viewModel.labelsToPrintCount
                            || viewModel.isLoadingPreview
                    )
                }
                .onChange(of: viewModel.previewLabelNumber) { _ in
                    viewModel.clampPreviewLabelNumber()
                    viewModel.schedulePreviewLabelRefresh()
                }
            }

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
        .padding(AppLayout.panelPadding)
    }

    private func updateWindowTitle() {
        // SwiftUI doesnt always set the titlebar text on macOS 13
        for window in NSApplication.shared.windows {
            window.title = AppTitle.name
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif

private struct PrintScopeOptionsRow: View {
    let printScope: PrintLabelScope
    @Binding var printRangeFrom: Int
    @Binding var printRangeTo: Int
    @Binding var printPagesText: String

    var body: some View {
        ZStack(alignment: .leading) {
            switch printScope {
            case .all:
                Color.clear
            case .range:
                HStack(spacing: 8) {
                    Text("From")
                    TextField("From", value: $printRangeFrom, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                    Text("to")
                    TextField("To", value: $printRangeTo, format: .number)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                }
            case .pages:
                TextField("e.g. 1, 10, 15-20", text: $printPagesText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppLayout.printScopeOptionsHeight, alignment: .leading)
    }
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
                        viewModel.refreshSetupStatus()
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

                    Button {
                        viewModel.refreshSetupStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh printer and setup status")
                    .disabled(viewModel.isCheckingRequirements)
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

                        if requirement.id == "printer_ready" {
                            Button {
                                viewModel.refreshSetupStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh printer queue status")
                            .disabled(viewModel.isCheckingRequirements)

                            if requirement.status != .passed {
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
                        ? Color.primary.opacity(0.10)
                        : Color.orange.opacity(0.35),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

private struct PrinterQueueStatusBanner: View {
    let status: PrinterQueueStatus
    let pendingJobCount: Int
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onResume: () -> Void
    let onPause: () -> Void
    let onCancelJobs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                    if pendingJobCount > 0 {
                        Text(pendingJobCount == 1 ? "1 job in queue" : "\(pendingJobCount) jobs in queue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .help("Refresh queue status (polls for up to 15 seconds)")
                .disabled(isRefreshing)
            }

            HStack(spacing: 8) {
                if status == .paused {
                    Button("Resume") {
                        onResume()
                    }
                    .controlSize(.small)
                    .disabled(isRefreshing)
                } else if status == .ready {
                    Button("Pause") {
                        onPause()
                    }
                    .controlSize(.small)
                    .disabled(isRefreshing)
                }

                if pendingJobCount > 0 {
                    Button("Cancel jobs") {
                        onCancelJobs()
                    }
                    .controlSize(.small)
                    .disabled(isRefreshing)
                }
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
        case .ready, .unknown:
            // Healthy/idle is the quietest signal — reserve tint for problems.
            return Color(nsColor: .controlBackgroundColor)
        case .paused:
            return Color.orange.opacity(0.12)
        case .offline:
            return Color.red.opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch status {
        case .ready, .unknown:
            return Color.primary.opacity(0.10)
        case .paused:
            return Color.orange.opacity(0.45)
        case .offline:
            return Color.red.opacity(0.40)
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
