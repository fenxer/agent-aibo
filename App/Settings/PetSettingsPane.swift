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
        ZStack {
            PetNameMarquee(name: record.displayName)
                .id(record.displayName)
            PetSpriteView(
                record: record,
                activity: .idle,
                spriteState: .idle,
                size: 96
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 138)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.displayName)
    }
}

/// Repeating pet-name watermark. Linear `withAnimation` loop — not `TimelineView`.
private struct PetNameMarquee: View {
    var name: String

    @State private var offset: CGFloat = 0
    @State private var lineWidth: CGFloat = 0

    private static let fontSize: CGFloat = 40
    private static let pointsPerSecond: CGFloat = 40
    private static let repeatsPerLine = 8
    private static let edgeFade: CGFloat = 0.12

    private var line: String {
        String(repeating: "\(name) ", count: Self.repeatsPerLine)
    }

    var body: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    lineText
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            guard width > 0, width != lineWidth else { return }
                            lineWidth = width
                            start()
                        }
                    lineText
                }
                .offset(x: offset)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: Self.edgeFade),
                        .init(color: .black, location: 1 - Self.edgeFade),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start() }
    }

    private var lineText: some View {
        Text(verbatim: line)
            .font(.system(size: Self.fontSize, weight: .black).italic())
            .foregroundStyle(.quaternary)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
    }

    private func start() {
        let width = lineWidth
        guard width > 0 else { return }
        // Settings first-attach can drop a same-turn animation; wait one turn.
        Task { @MainActor in
            await Task.yield()
            guard lineWidth == width else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                offset = 0
            }
            withAnimation(
                .linear(duration: width / Self.pointsPerSecond)
                .repeatForever(autoreverses: false)
            ) {
                offset = -width
            }
        }
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

            Toggle("Hide When Fullscreen", isOn: $settings.hideWhenFullscreen)
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
                    .frame(width: 132)
                    .disabled(isInstalling)

                Button("Install", action: onInstall)
                    .fixedSize()
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows all installed pets")
        .task(id: library.records) {
            occupiedBytes = library.occupiedDiskBytes()
        }
    }
}

private enum AllPetsSort: Hashable {
    case addedDate
    case name
    case size
}

private struct AllPetsSettingsView: View {
    var onBack: () -> Void

    @Bindable private var library = PetLibraryStore.shared
    @State private var sort: AllPetsSort = .addedDate
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var pendingDeleteIDs: [String] = []
    @State private var isConfirmingDelete = false
    @State private var sizeByID: [String: Int64] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(displayedRecords) { record in
                    AllPetsRow(
                        record: record,
                        occupiedBytes: sizeByID[record.id] ?? 0,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(record.id),
                        onTap: { handleTap(record) },
                        onDelete: record.isRemovable
                            ? { confirmDelete(ids: [record.id]) }
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
        ) {
            ToolbarItem {
                Picker(selection: $sort) {
                    Text("Added Date").tag(AllPetsSort.addedDate)
                        .padding(.horizontal, 8)
                    Text("Name").tag(AllPetsSort.name)
                        .padding(.horizontal, 8)
                    Text("Size").tag(AllPetsSort.size)
                        .padding(.horizontal, 8)
                } label: {
                    Text("Sort")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.body)
                .frame(height: AllPetsToolbarMetrics.controlHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
                .help("Sort")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                AllPetsSelectionToolbar(
                    isSelecting: isSelecting,
                    canDelete: !selectedIDs.isEmpty,
                    onToggleSelecting: toggleSelecting,
                    onDelete: confirmDeleteSelected
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: performPendingDelete)
            Button("Cancel", role: .cancel) {
                pendingDeleteIDs = []
            }
        } message: {
            Text(deleteDialogMessage)
        }
        .task(id: library.records) {
            var sizes: [String: Int64] = [:]
            for record in library.records {
                sizes[record.id] = library.occupiedDiskBytes(for: record)
            }
            sizeByID = sizes
        }
    }

    private var deleteDialogTitle: String {
        pendingDeleteIDs.count > 1
            ? String(localized: "Delete Pets?")
            : String(localized: "Delete Pet?")
    }

    private var displayedRecords: [PetLibraryRecord] {
        switch sort {
        case .addedDate:
            PetLibraryOrdering.installedAtNewestFirst(library.records)
        case .name:
            PetLibraryOrdering.byDisplayName(library.records)
        case .size:
            PetLibraryOrdering.bySizeLargestFirst(library.records, bytesForID: sizeByID)
        }
    }

    private var deleteDialogMessage: String {
        if pendingDeleteIDs.count == 1,
           let name = library.records.first(where: { $0.id == pendingDeleteIDs[0] })?.displayName
        {
            return String(localized: "Are you sure you want to delete “\(name)”?")
        }
        return String(localized: "Are you sure you want to delete \(pendingDeleteIDs.count) pets?")
    }

    private func handleTap(_ record: PetLibraryRecord) {
        if isSelecting {
            guard record.isRemovable else { return }
            if selectedIDs.contains(record.id) {
                selectedIDs.remove(record.id)
            } else {
                selectedIDs.insert(record.id)
            }
        } else {
            library.select(id: record.id)
        }
    }

    private func toggleSelecting() {
        withAnimation(.smooth) {
            isSelecting.toggle()
            if !isSelecting {
                selectedIDs.removeAll()
            }
        }
    }

    private func confirmDeleteSelected() {
        let ids = displayedRecords.map(\.id).filter { selectedIDs.contains($0) }
        confirmDelete(ids: ids)
    }

    private func confirmDelete(ids: [String]) {
        let removable = ids.filter { id in
            library.records.contains { $0.id == id && $0.isRemovable }
        }
        guard !removable.isEmpty else { return }
        pendingDeleteIDs = removable
        isConfirmingDelete = true
    }

    private func performPendingDelete() {
        library.remove(ids: pendingDeleteIDs)
        selectedIDs.subtract(pendingDeleteIDs)
        pendingDeleteIDs = []
        if isSelecting {
            withAnimation(.smooth) {
                isSelecting = false
                selectedIDs.removeAll()
            }
        }
    }
}

private enum AllPetsToolbarMetrics {
    static let controlHeight: CGFloat = 32
}

/// Delete + select live in one `GlassEffectContainer`. Morph is automatic
/// (`glassEffect` + `glassEffectID` + `withAnimation`); do not add
/// `glassEffectTransition` or view `.transition` on top of that.
private struct AllPetsSelectionToolbar: View {
    var isSelecting: Bool
    var canDelete: Bool
    var onToggleSelecting: () -> Void
    var onDelete: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if isSelecting {
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete")
                            .font(.body)
                            .frame(height: AllPetsToolbarMetrics.controlHeight)
                            .padding(.horizontal, 10)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular
                            .tint(canDelete ? Color.red : nil)
                            .interactive(),
                        in: .capsule
                    )
                    .disabled(!canDelete)
                    .glassEffectID("delete", in: glassNamespace)
                }

                Button(action: onToggleSelecting) {
                    Image(systemName: isSelecting ? "checkmark" : "checklist")
                        .font(.body)
                        .frame(
                            width: AllPetsToolbarMetrics.controlHeight,
                            height: AllPetsToolbarMetrics.controlHeight
                        )
                        .contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("select", in: glassNamespace)
                .help(isSelecting ? "Done" : "Select Pets")
                .accessibilityLabel(isSelecting ? "Done" : "Select Pets")
            }
        }
    }
}

private struct AllPetsRow: View {
    var record: PetLibraryRecord
    var occupiedBytes: Int64
    var isSelecting: Bool
    var isSelected: Bool
    var onTap: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 12) {
                    if isSelecting, record.isRemovable {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .imageScale(.medium)
                    }

                    PetSpriteView(
                        record: record,
                        activity: .idle,
                        spriteState: .idle,
                        size: 48
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        AllPetsSubtitle(record: record, occupiedBytes: occupiedBytes)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isSelecting, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete")
                .accessibilityLabel("Delete \(record.displayName)")
            }
        }
    }
}

private struct AllPetsSubtitle: View {
    var record: PetLibraryRecord
    var occupiedBytes: Int64

    var body: some View {
        HStack(spacing: 4) {
            sizeText
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: "·")
                .fixedSize()
            dateText
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: "·")
                .fixedSize()
            Text(installSourceText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var sizeText: some View {
        if record.kind == .builtInDefault {
            Text(verbatim: "—")
        } else {
            Text(occupiedBytes, format: .byteCount(style: .file))
        }
    }

    @ViewBuilder
    private var dateText: some View {
        if let installedAt = record.installedAt {
            Text(installedAt, format: .relative(presentation: .named))
        } else {
            Text(verbatim: "—")
        }
    }

    private var installSourceText: String {
        if let source = record.installSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty
        {
            return source
        }
        switch record.kind {
        case .builtInDefault:
            return String(localized: "Built-in")
        case .staticImage:
            return String(localized: "Local")
        case .petdex:
            if let slug = record.slug {
                return PetdexInstallAPI.petPageURL(slug: slug).absoluteString
            }
            return String(localized: "PetDex")
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
