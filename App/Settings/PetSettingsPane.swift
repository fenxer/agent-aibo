import AiboCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetSettingsPane: View {
    @State private var showsAllPets = false

    var body: some View {
        Group {
            if showsAllPets {
                AllPetsSettingsView {
                    showsAllPets = false
                }
            } else {
                PetSettingsRootView {
                    showsAllPets = true
                }
            }
        }
    }
}

private struct PetSettingsRootView: View {
    var onShowAllPets: () -> Void

    @Bindable private var settings = AppSettings.shared
    @Bindable private var library = PetLibraryStore.shared
    @State private var petdexInput = ""
    @State private var isImportingImage = false

    var body: some View {
        Form {
            PetPreviewAndSelectionSection(library: library)

            PetConfigurationSection(settings: settings)

            PetManageSection(
                petdexInput: $petdexInput,
                isInstalling: library.isInstalling,
                lastErrorMessage: library.lastErrorMessage,
                onAddImage: { isImportingImage = true },
                onInstallPetdex: installPetdex
            )

            Section {
                AllPetsEntryRow(action: onShowAllPets)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(title: String(localized: "Pet"))
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.png, .jpeg, .webP, .heic, .tiff, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImageImport(result)
        }
    }

    private func installPetdex() {
        let input = petdexInput
        Task {
            await library.installPetdex(from: input)
            if library.lastErrorMessage == nil {
                petdexInput = ""
            }
        }
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            library.importStaticImage(from: url)
        case .failure:
            break
        }
    }
}

private struct PetPreviewAndSelectionSection: View {
    var library: PetLibraryStore

    var body: some View {
        Section {
            PetPreviewBanner(record: library.selectedRecord)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color(nsColor: .windowBackgroundColor))

            Picker("Active Pet", selection: selectedPetBinding) {
                ForEach(library.records) { record in
                    Text(record.displayName).tag(record.id)
                }
            }
        }
    }

    private var selectedPetBinding: Binding<String> {
        Binding(
            get: { library.selectedID },
            set: { library.select(id: $0) }
        )
    }
}

private struct PetPreviewBanner: View {
    var record: PetLibraryRecord

    var body: some View {
        PetSpriteView(
            record: record,
            activity: .idle,
            spriteState: .idle,
            size: 96
        )
        .frame(maxWidth: .infinity)
        .frame(height: 138)
        .accessibilityLabel(record.displayName)
    }
}

private struct PetConfigurationSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            PetSizeRow(
                percent: $settings.petScalePercent,
                percentRange: AppSettings.petScalePercentRange
            )

            Toggle("Restore Last Position", isOn: $settings.restoreLastPetPosition)
        }
    }
}

private struct PetSizeRow: View {
    @Binding var percent: Double
    var percentRange: ClosedRange<Double>

    /// Tick marks only — do not use `step:` (that paints a mark at every increment).
    private static let tickPercents: [Double] = [0, 50, 100, 150, 200]

    var body: some View {
        LabeledContent("Pet Size") {
            HStack(spacing: 12) {
                Slider(value: roundedPercentBinding, in: percentRange) {
                    EmptyView()
                } ticks: {
                    SliderTickContentForEach(Self.tickPercents, id: \.self) { value in
                        SliderTick(value)
                    }
                }

                TextField(
                    "Pet Size",
                    value: percentIntBinding,
                    format: PetScalePercentFormat()
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
            }
        }
    }

    private var roundedPercentBinding: Binding<Double> {
        Binding(
            get: { percent },
            set: { percent = $0.rounded() }
        )
    }

    private var percentIntBinding: Binding<Int> {
        Binding(
            get: { Int(percent.rounded()) },
            set: { percent = Double($0) }
        )
    }
}

private struct PetManageSection: View {
    @Binding var petdexInput: String
    var isInstalling: Bool
    var lastErrorMessage: String?
    var onAddImage: () -> Void
    var onInstallPetdex: () -> Void

    var body: some View {
        Section {
            InstallFromLocalImageRow(isInstalling: isInstalling, action: onAddImage)

            InstallFromPetdexRow(
                petdexInput: $petdexInput,
                isInstalling: isInstalling,
                onInstall: onInstallPetdex
            )

            if isInstalling {
                ProgressView("Installing…")
                    .controlSize(.small)
            }

            if let lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Manage Pets")
        }
        .labeledContentStyle(VerticallyCenteredLabeledContentStyle())
    }
}

/// Centers the trailing control against a title + subtitle label.
/// Form `LabeledContent` otherwise aligns to the title baseline (visually top).
private struct VerticallyCenteredLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
        }
    }
}

private struct InstallFromLocalImageRow: View {
    var isInstalling: Bool
    var action: () -> Void

    var body: some View {
        LabeledContent {
            Button("Add Image", action: action)
                .disabled(isInstalling)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Install from Local Image")
                Text("Compatible with single images or Codex pet formats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct InstallFromPetdexRow: View {
    @Binding var petdexInput: String
    var isInstalling: Bool
    var onInstall: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField("PetDex URL or slug", text: $petdexInput)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 168)
                    .disabled(isInstalling)

                Button("Install", action: onInstall)
                    .disabled(
                        isInstalling
                            || petdexInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Install from PetDex")
                Text("Enter PetDex URL or slug to download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AllPetsEntryRow: View {
    var action: () -> Void

    @Bindable private var library = PetLibraryStore.shared
    @State private var occupiedBytes: Int64 = 0

    var body: some View {
        Button(action: action) {
            HStack {
                Text("All Pets")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(occupiedBytes, format: .byteCount(style: .file)) used")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows all installed pets")
        .task(id: library.records) {
            occupiedBytes = library.occupiedDiskBytes()
        }
    }
}

private struct AllPetsSettingsView: View {
    var onBack: () -> Void

    @Bindable private var library = PetLibraryStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(library.records) { record in
                    AllPetsRow(
                        record: record,
                        isActive: record.id == library.selectedID,
                        onSelect: { library.select(id: record.id) },
                        onDelete: record.isRemovable
                            ? { library.remove(id: record.id) }
                            : nil
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailChrome(
            title: String(localized: "All Pets"),
            canGoBack: true,
            onBack: onBack
        )
    }
}

private struct AllPetsRow: View {
    var record: PetLibraryRecord
    var isActive: Bool
    var onSelect: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                PetSpriteView(
                    record: record,
                    activity: .idle,
                    spriteState: .idle,
                    size: 36
                )

                Text(record.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Active")
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let onDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
        .contextMenu {
            if let onDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }
}

private struct PetScalePercentFormat: ParseableFormatStyle {
    var parseStrategy = PetScalePercentParseStrategy()

    func format(_ value: Int) -> String {
        "\(value)%"
    }
}

private struct PetScalePercentParseStrategy: ParseStrategy {
    func parse(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberPart = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        guard let parsed = Int(numberPart.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CocoaError.error(.formatting)
        }
        return parsed
    }
}
