import SwiftUI

/// 共有用アカウント（パートナー共有の土台・2026-10-19）
/// Appleでサインイン・サインイン状態・サインアウト・アカウント削除。
/// 今回はサインインして「誰か」を確かめるだけ。生活データは送らず、Firestore にも書き込まない。
struct PartnerAccountView: View {
    @Bindable var auth: AuthService
    /// 招待リンクから開いたとき、参加は次の段階で使えるようになることを案内する（2026-10-21）
    var showsInviteNotice = false
    /// 「なんでも追加」を出すか（招待の確認画面の中では出さない）
    var showsQuickAdd = true
    /// 削除の確認画面を出しているか（画面の中だけの状態。削除の処理はこの値に関係なく動く）
    @State private var isConfirmingDeletion = false

    var body: some View {
        SettingsScreen(title: "共有用アカウント", showsQuickAdd: showsQuickAdd) {
            if showsInviteNotice {
                inviteNotice
            }

            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                Text("パートナー共有を使う人を確かめるための、Appleでのサインインです。")
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("共有を有効にするまで、予定やタスクなどの生活データは送信されません。")
                    .font(LifeTypography.bodyEmphasis)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statusSection

            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                SettingsNote(text: "サインインのときに送られるのは、Appleが発行するサインイン用の情報（あなたを見分ける番号）だけです。名前とメールアドレスはAppleに求めていません。")
                SettingsNote(text: "サインインしなくても、くらしOSのほかの機能はこれまでどおり使えます。")
            }
        }
        .onAppear { auth.refresh() }
        .confirmationDialog(
            "共有用アカウントを削除しますか？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            // 確定したときだけ削除する。確認画面が閉じる処理の順番には関係しない
            Button("アカウントを削除", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
            // やめる・確認画面を閉じたときは、何もしない
            Button("やめる", role: .cancel) {}
        } message: {
            Text("もう一度Appleで確かめたあと、共有用アカウントを削除し、Appleでのサインインの連携も解除します。この iPhone の中の予定やタスクなどのデータは消えません。")
        }
    }

    /// 招待リンクから開いたときの案内（参加の処理はまだ無い。サインインも自動では始めない）
    private var inviteNotice: some View {
        statusCard(
            systemImage: "envelope.open",
            title: "招待への参加は、次のアップデートで使えるようになります",
            detail: "いまはまだ、ここから参加できません。受け取った招待リンクは保存していないので、参加できるようになったら、もう一度リンクを開いてください（招待の期限は24時間です）。この iPhone の中のデータは変わっていません。"
        )
    }

    @ViewBuilder
    private var statusSection: some View {
        switch auth.status {
        case .unavailable(let reason):
            statusCard(systemImage: "icloud.slash", title: "いまは使えません", detail: reason.message)

        case .signedOut:
            VStack(alignment: .leading, spacing: LifeSpacing.md) {
                statusCard(systemImage: "person.crop.circle", title: "サインインしていません", detail: nil)
                appleButton
            }

        case .working(let operation, _):
            HStack(spacing: LifeSpacing.sm) {
                ProgressView()
                Text(operation.message)
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LifeSpacing.md)
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            .accessibilityElement(children: .combine)

        case .signedIn(let account):
            signedInSection(account)

        case .failed(let failure, let account):
            VStack(alignment: .leading, spacing: LifeSpacing.md) {
                statusCard(systemImage: "exclamationmark.circle", title: "うまくいきませんでした", detail: failure.message)
                LifeButton("閉じる", kind: .secondary) { auth.dismissFailure() }
                if account == nil {
                    appleButton
                }
            }
        }
    }

    private func signedInSection(_ account: AuthAccount) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            statusCard(
                systemImage: "checkmark.circle",
                title: "Appleでサインイン済み",
                detail: "アカウントの番号：\(account.maskedUID)"
            )
            LifeButton("サインアウト", systemImage: "rectangle.portrait.and.arrow.right", kind: .secondary) {
                auth.signOut()
            }
            LifeButton("アカウントを削除", systemImage: "trash", kind: .destructive) {
                isConfirmingDeletion = true
            }
            .disabled(!auth.canDeleteAccount)
        }
    }

    private var appleButton: some View {
        Button {
            Task { await auth.signIn() }
        } label: {
            HStack(spacing: LifeSpacing.xs) {
                Image(systemName: "applelogo")
                    .accessibilityHidden(true)
                Text("Appleでサインイン")
            }
            .font(LifeTypography.button)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: LifeSpacing.buttonHeight)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(LifePressButtonStyle())
        .disabled(auth.status.isWorking)
        .accessibilityLabel("Appleでサインイン")
    }

    private func statusCard(systemImage: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: LifeSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(LifeColors.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(title)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                if let detail {
                    Text(detail)
                        .font(LifeTypography.footnote)
                        .foregroundStyle(LifeColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LifeSpacing.md)
        .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// プレビュー用（Firebase にも Apple にも接続しない）
private final class PreviewAppleSignIn: AppleSignInProviding {
    func requestCredential(hashedNonce: String) async throws -> AppleCredential {
        throw AuthFailure.canceled
    }
}

private final class PreviewBackend: AuthBackend {
    var currentAccount: AuthAccount?
    init(account: AuthAccount?) { currentAccount = account }
    func signIn(with credential: AppleCredential, rawNonce: String) async throws -> AuthAccount { AuthAccount(uid: "preview") }
    func signOut() throws { currentAccount = nil }
    func reauthenticate(with credential: AppleCredential, rawNonce: String) async throws {}
    func revokeAppleToken(authorizationCode: String) async throws {}
    func deleteCurrentUser() async throws { currentAccount = nil }
}

#Preview("サインインしていない") {
    NavigationStack {
        PartnerAccountView(auth: AuthService(backend: PreviewBackend(account: nil), apple: PreviewAppleSignIn()))
    }
    .environment(AppState())
    .environment(LifeStore())
}

#Preview("サインイン済み") {
    NavigationStack {
        PartnerAccountView(auth: AuthService(backend: PreviewBackend(account: AuthAccount(uid: "abcd1234efgh5678")), apple: PreviewAppleSignIn()))
    }
    .environment(AppState())
    .environment(LifeStore())
}

#Preview("使えない（Firebase 未設定）") {
    NavigationStack {
        PartnerAccountView(auth: AuthService(backend: nil, unavailableReason: .missingConfiguration, apple: PreviewAppleSignIn()))
    }
    .environment(AppState())
    .environment(LifeStore())
}
#endif
