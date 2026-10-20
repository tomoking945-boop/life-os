import SwiftUI

/// 招待リンクを受け取ったときの確認画面（2026-10-21 招待リンクの土台。docs/FIREBASE_INVITE_LINK_FOUNDATION.md）
///
/// - 「あとで」・閉じる：何も変えず、招待を捨てる
/// - 「招待を確認」：共有用アカウントの画面へ進み、参加は次の段階で使えるようになることを案内する
/// - 参加・サインイン・Firestore への書き込みは、ここでは始めない。招待トークンは表示しない
struct InviteLinkSheet: View {
    @Bindable var coordinator: InviteLinkCoordinator
    let auth: AuthService

    var body: some View {
        NavigationStack {
            switch coordinator.step {
            case .prompt:
                InviteReceivedPromptView(
                    onLater: { coordinator.later() },
                    onConfirm: { coordinator.confirm() }
                )
            case .account:
                PartnerAccountView(auth: auth, showsInviteNotice: true, showsQuickAdd: false)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { coordinator.close() }
                        }
                    }
            }
        }
        .lifeSheetPresentation()
    }
}

/// 「わが家への招待を受け取りました」
struct InviteReceivedPromptView: View {
    let onLater: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeSpacing.lg) {
                Image(systemName: "envelope.open")
                    .font(.largeTitle)
                    .foregroundStyle(LifeColors.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                    Text("わが家への招待を受け取りました")
                        .font(LifeTypography.editorialTitle)
                        .foregroundStyle(LifeColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("参加する前に、共有される内容を確認してください")
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsNote(text: "このリンクを開いただけでは、参加もサインインもしません。この iPhone の中の予定やタスクなどのデータも変わりません。")

                VStack(spacing: LifeSpacing.sm) {
                    LifeButton("招待を確認", kind: .primary, action: onConfirm)
                    LifeButton("あとで", kind: .secondary, action: onLater)
                }
            }
            .padding(.horizontal, LifeSpacing.screenHorizontal)
            .padding(.vertical, LifeSpacing.screenVertical)
        }
        .lifeScreenBackground()
        .navigationTitle("招待")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("招待を受け取った") {
    NavigationStack {
        InviteReceivedPromptView(onLater: {}, onConfirm: {})
    }
    .environment(AppState())
    .environment(LifeStore())
}
#endif
