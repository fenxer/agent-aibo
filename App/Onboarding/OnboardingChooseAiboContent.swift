import AiboCore
import SwiftUI

/// Interactive list / PetDex field / naming row inside the choose-aibo bubble.
struct OnboardingChooseAiboContent: View {
    var ink: Color
    var onInk: Color
    var fillIsLight: Bool

    @Bindable private var onboarding = OnboardingController.shared
    @Bindable private var library = AiboLibraryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch onboarding.choosePhase {
            case .options, .petdexInput:
                chooseList
                if onboarding.choosePhase == .petdexInput {
                    visitPetdexLink
                }
            case .naming:
                namingForm
            }

            if let error = onboarding.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, OnboardingChrome.chooseFooterLeadingPadding)
            }
        }
    }

    private var chooseList: some View {
        VStack(spacing: 0) {
            ChooseAiboRow(
                title: String(localized: "Use Default"),
                accessory: String(localized: "Can be set later in the menu"),
                ink: ink,
                enabled: !library.isInstalling,
                action: { onboarding.useDefaultAibo() }
            )
            divider
            ChooseAiboRow(
                title: String(localized: "Local Upload"),
                ink: ink,
                enabled: !library.isInstalling,
                action: { onboarding.presentLocalFilePicker() }
            )
            divider
            ChooseAiboRow(
                title: String(localized: "Enter a PetDex link"),
                ink: ink,
                enabled: !library.isInstalling,
                action: { onboarding.revealPetdexInput() }
            )
            if onboarding.choosePhase == .petdexInput {
                petdexInputRow
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .padding(.top, 6)
            }
        }
        .background(
            ink.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: OnboardingChrome.chooseListCornerRadius,
                style: .continuous
            )
        )
    }

    private var petdexInputRow: some View {
        HStack(spacing: 8) {
            chooseField(text: $onboarding.petdexURL, prompt: "https://...")
                .onSubmit {
                    Task { await onboarding.fetchPetdex() }
                }
            OnboardingSolidButton(
                title: String(localized: "Get"),
                ink: ink,
                onInk: onInk,
                fillIsLight: fillIsLight,
                isBusy: library.isInstalling,
                isEnabled: canFetchPetdex,
                action: {
                    Task { await onboarding.fetchPetdex() }
                }
            )
        }
        .onAppear {
            AiboPanelController.shared.updateOnboardingKeyWindow()
        }
    }

    private var namingForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                LabeledContent {
                    chooseField(text: $onboarding.namingDraft, prompt: "")
                        .onSubmit {
                            Task { await onboarding.saveImportedName() }
                        }
                } label: {
                    Text(String(localized: "Rename"))
                        .font(.system(size: 12))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .labeledContentStyle(OnboardingFormLabeledContentStyle())
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Rename"))
                divider
                OnboardingMetricSliderRow(
                    title: String(localized: "Aibo Size"),
                    unit: "%",
                    value: scaleBinding,
                    range: AiboLibraryRecord.scalePercentRange,
                    ink: ink
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                divider
                OnboardingMetricSliderRow(
                    title: String(localized: "Bubble Distance"),
                    unit: "pt",
                    value: distanceBinding,
                    range: AiboLibraryRecord.bubbleDistanceRange,
                    ink: ink
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(
                ink.opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: OnboardingChrome.chooseListCornerRadius,
                    style: .continuous
                )
            )
            HStack {
                Spacer(minLength: 0)
                OnboardingSolidButton(
                    title: String(localized: "Save"),
                    ink: ink,
                    onInk: onInk,
                    fillIsLight: fillIsLight,
                    isBusy: library.isInstalling,
                    isEnabled: canSaveName,
                    action: {
                        Task { await onboarding.saveImportedName() }
                    }
                )
            }
        }
        .onAppear {
            AiboPanelController.shared.updateOnboardingKeyWindow()
        }
        .onSubmit {
            Task { await onboarding.saveImportedName() }
        }
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { onboarding.namingScalePercent },
            set: { newValue in
                let clamped = AiboLibraryRecord.clampedScalePercent(newValue.rounded())
                onboarding.namingScalePercent = clamped
                guard !onboarding.namingIsPendingPack else { return }
                library.setScalePercent(clamped)
            }
        )
    }

    private var distanceBinding: Binding<Double> {
        Binding(
            get: { onboarding.namingBubbleDistance },
            set: { newValue in
                let clamped = AiboLibraryRecord.clampedBubbleDistance(newValue.rounded())
                onboarding.namingBubbleDistance = clamped
                guard !onboarding.namingIsPendingPack else { return }
                library.setBubbleDistance(clamped)
            }
        )
    }

    private var visitPetdexLink: some View {
        HStack(spacing: 3) {
            Text(String(localized: "Visit PetDex"))
            Image(systemName: "arrow.up.right")
        }
        .font(.system(size: 12))
        .foregroundStyle(ink.opacity(0.6))
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { onboarding.openPetdexSite() }
        )
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel(String(localized: "Visit PetDex"))
        .padding(.leading, OnboardingChrome.chooseFooterLeadingPadding)
    }

    private var divider: some View {
        Rectangle()
            .fill(ink.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private var canFetchPetdex: Bool {
        !library.isInstalling
            && !onboarding.petdexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSaveName: Bool {
        !library.isInstalling
            && AiboLibraryNaming.normalizedDisplayName(onboarding.namingDraft) != nil
            && (!onboarding.namingIsPendingPack
                || library.canConfirmPendingNamedImport(displayName: onboarding.namingDraft))
    }

    private func chooseField(text: Binding<String>, prompt: String) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(verbatim: prompt).foregroundStyle(ink.opacity(0.35))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: OnboardingChrome.chooseFieldHeight, maxHeight: OnboardingChrome.chooseFieldHeight)
        .background(
            ink.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: OnboardingChrome.chooseFieldCornerRadius,
                style: .continuous
            )
        )
    }
}

private struct OnboardingMetricSliderRow: View {
    let title: String
    let unit: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var ink: Color

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: roundedBinding, in: range)
                    .controlSize(.small)
                    .tint(ink)
                TextField(
                    title,
                    value: intBinding,
                    format: .number.grouping(.never)
                )
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(ink)
                .frame(width: 36)
                Text(verbatim: unit)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.45))
                    .frame(minWidth: 18, alignment: .leading)
            }
        } label: {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .labeledContentStyle(OnboardingFormLabeledContentStyle())
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value.rounded())) \(unit)")
    }

    private var roundedBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { value = $0.rounded() }
        )
    }

    private var intBinding: Binding<Int> {
        Binding(
            get: { Int(value.rounded()) },
            set: { value = Double($0) }
        )
    }
}

/// Settings `LabeledContent` is label | control on one row. Force that in the narrow bubble.
private struct OnboardingFormLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.label
                .fixedSize(horizontal: true, vertical: false)
            configuration.content
        }
    }
}

private struct ChooseAiboRow: View {
    let title: String
    var accessory: String? = nil
    let ink: Color
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let accessory {
                Text(accessory)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: OnboardingChrome.chooseListRowHeight)
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.45)
        .highPriorityGesture(TapGesture().onEnded {
            guard enabled else { return }
            action()
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }
}

private struct OnboardingSolidButton: View {
    let title: String
    let ink: Color
    let onInk: Color
    var fillIsLight: Bool
    var isBusy: Bool
    var isEnabled: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: OnboardingChrome.buttonFontSize, weight: .medium))
                .foregroundStyle(onInk)
                .opacity(isBusy ? 0 : 1)
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(onInk)
                    .colorScheme(fillIsLight ? .light : .dark)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: OnboardingChrome.chooseFieldHeight)
        .background(
            ink.opacity(isEnabled || isBusy ? 1 : 0.35),
            in: RoundedRectangle(
                cornerRadius: OnboardingChrome.chooseSolidButtonCornerRadius,
                style: .continuous
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: OnboardingChrome.chooseSolidButtonCornerRadius,
                style: .continuous
            )
        )
        .highPriorityGesture(TapGesture().onEnded {
            guard isEnabled else { return }
            action()
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
    }
}
