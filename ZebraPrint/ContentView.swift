import AppKit
import SwiftUI

private enum AppTitle {
    static let name = "Zebra Label Print"
}

struct ContentView: View {
    @StateObject private var viewModel = PrintViewModel()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            controlsPanel
                .frame(width: 380)
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
        .onChange(of: viewModel.selectedPrinter) { printer in
            viewModel.persistPrinter(printer)
            viewModel.updatePrintDefinition()
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
        .alert("Print job sent", isPresented: $viewModel.showSuccessAlert) {
            Button("Close", role: .cancel) {}
        } message: {
            if let file = viewModel.selectedFileURL {
                Text("\"\(file.lastPathComponent)\" was sent to \(viewModel.selectedPrinter).")
            }
        }
        .alert("Print failed", isPresented: $viewModel.showErrorAlert) {
            Button("Close", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var controlsPanel: some View {
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

            Spacer()

            HStack {
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Print") {
                    viewModel.printFile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.selectedFileURL == nil
                        || viewModel.selectedPrinter.isEmpty
                        || viewModel.isPrinting
                )
            }
        }
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

            if viewModel.previewLabelCount > 1 {
                HStack {
                    Button {
                        viewModel.showPreviousPreviewLabel()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.previewLabelIndex == 0 || viewModel.isLoadingPreview)

                    Spacer()

                    Button {
                        viewModel.showNextPreviewLabel()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(
                        viewModel.previewLabelIndex >= max(
                            viewModel.previewLabelCount - ZPLPreviewService.previewStripCount,
                            0
                        ) || viewModel.isLoadingPreview
                    )
                }
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
        for window in NSApplication.shared.windows {
            window.title = AppTitle.name
        }
    }
}

#Preview {
    ContentView()
}
