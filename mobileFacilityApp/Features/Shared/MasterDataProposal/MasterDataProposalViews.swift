import SwiftUI

/// The edit button `_buildHeaderForm` places beside a value list that offers
/// "Pflege durch Admin". It is enabled only while that entry is selected and
/// shows a filled icon once the field has a proposal.
struct MasterDataProposalButton: View {
    static let width: CGFloat = 56

    let isEnabled: Bool
    let hasProposal: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: hasProposal ? "square.and.pencil.circle.fill" : "square.and.pencil")
                .font(.title3)
                .foregroundStyle(isEnabled ? FacilityTheme.blue : .secondary)
                .frame(width: Self.width, height: 48)
                .briefingFieldChrome(invalid: false, isDisabled: !isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("inspection.masterData.proposal.edit"))
    }
}

/// `VorschlagPopover.fragment.xml` as a centered, modal editor: the title
/// bar, the read-only "Vorgeschlagene Werte" token box (tapping a token
/// copies it into the input below), the required "Neuer Vorschlag" input (at
/// most 80 characters) and the Cancel / Save footer. Present it over the
/// whole form like `NotificationCommentEditorOverlay`.
///
/// Save hands back the raw input: a text stores the proposal, an empty text
/// removes it (`onPressVorschlagSave`).
struct MasterDataProposalEditor: View {
    let fieldTitle: String
    /// Earlier proposals for this field and object, newest first. The legacy
    /// `Tokenizer` is hidden when there is nothing to show.
    let history: [String]
    let cancel: () -> Void
    let save: (String) -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    /// - Parameter initialText: this form's own proposal.
    ///   `vorschlagBeforeOpen` fills the input only with it; proposals from
    ///   other forms stay suggestions in `history`.
    init(
        fieldTitle: String,
        initialText: String,
        history: [String],
        cancel: @escaping () -> Void,
        save: @escaping (String) -> Void
    ) {
        self.fieldTitle = fieldTitle
        self.history = MasterDataProposalRules.history(history)
        self.cancel = cancel
        self.save = save
        _text = State(initialValue: String(initialText.prefix(MasterDataProposalRules.maximumLength)))
    }

    var body: some View {
        ZStack {
            FacilityTheme.dialogScrim
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)

            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    Text("vorschlagPopover.title")
                        .font(.headline)
                        .foregroundStyle(FacilityTheme.ink)
                    Text(verbatim: fieldTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 22)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    if !history.isEmpty {
                        SafetyFormField("vorschlag.history") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(history, id: \.self, content: token)
                                }
                            }
                            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                            .briefingFieldChrome(invalid: false, isDisabled: true)
                        }
                    }

                    SafetyFormField("vorschlag.new", required: true) {
                        TextField("", text: Binding(
                            get: { text },
                            set: { text = String($0.prefix(MasterDataProposalRules.maximumLength)) }
                        ))
                        .focused($isFocused)
                        .foregroundStyle(FacilityTheme.ink)
                        .briefingFieldChrome(invalid: false)
                    }
                }
                .padding(22)

                Divider()

                HStack(spacing: 28) {
                    Spacer()
                    Button("common.cancel", action: cancel)
                        .frame(minHeight: 44)
                    Button("inspection.masterData.proposal.save") { save(text) }
                        .fontWeight(.semibold)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(FacilityTheme.blue)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .facilityDialogFrame(width: 560, padding: 0)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.gray.opacity(0.28))
            }
            .shadow(color: Color.black.opacity(0.20), radius: 26, y: 12)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { isFocused = true }
    }

    /// `onPressVorschlagToken` copies the token text into the input.
    private func token(_ proposal: String) -> some View {
        Button { text = String(proposal.prefix(MasterDataProposalRules.maximumLength)) } label: {
            Text(verbatim: proposal)
                .font(.body)
                .foregroundStyle(FacilityTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.gray.opacity(0.4))
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("vorschlag.new"))
    }
}
