import SwiftUI

/// 「招待リンクを入力」（2026-10-28。docs/INVITE_OPEN_BUTTON_FIX.md）
///
/// 招待リンクをタップしてもブラウザが開いてしまうときの、アプリの中の代わりの入り口。
/// - クリップボードは自動で読まない。利用者が欄をタップして、自分で貼り付ける
/// - Universal Link（https）と、くらしOS専用の URL Scheme のどちらの形も受け付け、同じ InviteLink の判定を通す
/// - 正しければ「わが家への招待を受け取りました」の確認画面へ進む。貼り付けただけでは参加しない
/// - エラーの文にトークンは入れない。入力した内容は保存しない（画面を離れると消す）
struct InviteLinkEntryView: View {
    @Environment(InviteLinkCoordinator.self) private var inviteLinks: InviteLinkCoordinator?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showsError = false

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsScreen(title: "招待リンクを入力", showsQuickAdd: false) {
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                Text("パートナーから届いた招待リンクを、下の欄に貼り付けてください。")
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                LifeSectionTitle("招待リンク")
                TextField("ここをタップして貼り付け", text: $text, axis: .vertical)
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .lineLimit(1...4)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .privacySensitive()
                    .padding(LifeSpacing.md)
                    .frame(minHeight: LifeSpacing.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                            .fill(LifeColors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LifeRadius.field, style: .continuous)
                            .stroke(showsError ? LifeColors.accent : LifeColors.divider, lineWidth: 1)
                    )
                    .accessibilityLabel("招待リンク")
                    .onChange(of: text) { showsError = false }
            }

            if showsError {
                InviteCard(
                    systemImage: "exclamationmark.circle",
                    title: "招待リンクが正しくありません",
                    detail: "届いたリンクを、そのまま全部貼り付けてください。くらしOSの招待リンクだけを使えます。"
                )
            }

            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                SettingsNote(text: "貼り付けただけでは参加しません。次の画面で内容を確かめてから「参加する」を押したときだけ参加します。")
                SettingsNote(text: "この画面はクリップボードを自動で読み取りません。入力した内容は保存しません。")
            }

            LifeButton("招待を確認", systemImage: "envelope.open", kind: .primary, action: submit)
                .disabled(!hasText || inviteLinks == nil)
        }
        .onDisappear {
            text = ""
            showsError = false
        }
    }

    private func submit() {
        guard let inviteLinks, hasText else { return }
        switch inviteLinks.submitManualEntry(text) {
        case .presented, .alreadyShowing:
            text = ""
            dismiss()
        case .invalid:
            showsError = true
        }
    }
}

/// 共有用アカウント・わが家の画面に置く「招待リンクを入力」への入り口（わが家に参加する前だけ）
struct InviteLinkEntryLink: View {
    var body: some View {
        NavigationLink {
            InviteLinkEntryView()
        } label: {
            LifeButtonLabel(title: "招待リンクを入力", systemImage: "link", kind: .secondary)
        }
        .buttonStyle(LifePressButtonStyle())
    }
}
