import SwiftUI

/// 招待リンクを受け取ったときの確認画面（2026-10-21 招待リンクの土台、2026-10-22 参加。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
///
/// 1. 「わが家への招待を受け取りました」：「招待を確認」「あとで」
/// 2. 参加の確認：サインインしていなければ「参加するにはAppleでサインインしてください」（押したときだけサインイン）。
///    サインイン済みなら招待の内容（グループ名・共有する種類・期限）と「参加する」「やめる」
/// 3. 参加できた：メンバーの画面と「わが家に参加しました」
///
/// 参加は「参加する」を押したときだけ。「あとで」「やめる」・閉じるでは何も変えず、招待を捨てる。招待トークンは表示しない
struct InviteLinkSheet: View {
    @Bindable var coordinator: InviteLinkCoordinator
    let auth: AuthService
    let household: HouseholdService

    var body: some View {
        NavigationStack {
            switch coordinator.step {
            case .prompt:
                InviteReceivedPromptView(
                    onLater: { coordinator.later() },
                    onConfirm: { coordinator.confirm() }
                )
            case .join:
                InviteJoinView(coordinator: coordinator, auth: auth, household: household)
            case .joined:
                PartnerAccountView(auth: auth, household: household, showsQuickAdd: false)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { coordinator.close() }
                        }
                    }
            }
        }
        .lifeSheetPresentation()
        .onDisappear { household.resetPreview() }
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

/// 参加の確認（サインインの案内 → 招待の内容 → 「参加する」「やめる」）
struct InviteJoinView: View {
    @Bindable var coordinator: InviteLinkCoordinator
    @Bindable var auth: AuthService
    @Bindable var household: HouseholdService

    private var isSignedIn: Bool { auth.account != nil }

    var body: some View {
        SettingsScreen(title: "招待の確認", showsQuickAdd: false) {
            content
        }
        // サインインしたら（サインインの画面から戻ったら）、もう一度招待の内容を読む
        .task(id: isSignedIn) {
            guard isSignedIn, let invite = coordinator.pendingInvite else { return }
            await household.loadPreview(for: invite)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isAvailable || !household.isAvailable {
            InviteCard(systemImage: "icloud.slash", title: "いまは参加できません", detail: HouseholdFailure.notConnected.message)
            LifeButton("やめる", kind: .secondary) { coordinator.close() }
        } else if !isSignedIn {
            signInSection
        } else {
            previewSection
        }
    }

    /// サインインしていないとき：押したときだけサインインする（やめたら参加しない）
    private var signInSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            InviteCard(
                systemImage: "person.crop.circle",
                title: "参加するにはAppleでサインインしてください",
                detail: "サインインしたあと、招待の内容をもう一度表示します。サインインしただけでは参加しません。"
            )
            if case .failed(let failure, _) = auth.status {
                InviteCard(systemImage: "exclamationmark.circle", title: "サインインできませんでした", detail: failure.message)
            }
            if auth.status.isWorking {
                HStack(spacing: LifeSpacing.sm) {
                    ProgressView()
                    Text("サインインしています…")
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            } else {
                AppleSignInButton { Task { await auth.signIn() } }
            }
            LifeButton("やめる", kind: .secondary) { coordinator.close() }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch household.preview {
        case .idle, .loading:
            HStack(spacing: LifeSpacing.sm) {
                ProgressView()
                Text("招待の内容を確認しています…")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }
            LifeButton("やめる", kind: .secondary) { coordinator.close() }

        case .loaded(let preview):
            loadedPreview(preview)

        case .joining:
            HStack(spacing: LifeSpacing.sm) {
                ProgressView()
                Text("参加しています…")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }

        case .joined:
            InviteCard(systemImage: "checkmark.circle", title: "わが家に参加しました", detail: nil)

        case .failed(let failure):
            InviteCard(systemImage: "exclamationmark.circle", title: "この招待には参加できません", detail: failure.message)
            if failure == .network {
                LifeButton("もう一度確認する", kind: .primary) {
                    guard let invite = coordinator.pendingInvite else { return }
                    Task { await household.loadPreview(for: invite) }
                }
            }
            LifeButton("閉じる", kind: .secondary) { coordinator.close() }
        }
    }

    private func loadedPreview(_ preview: InvitePreview) -> some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            Text("\(preview.groupName)への招待")
                .font(LifeTypography.editorialTitle)
                .foregroundStyle(LifeColors.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                LifeSectionTitle("共有される種類")
                ForEach(preview.sharedKinds) { kind in
                    Label(kind.title, systemImage: "checkmark")
                        .font(LifeTypography.body)
                        .foregroundStyle(LifeColors.text)
                }
            }

            InviteCard(systemImage: "lock", title: "現在iPhoneにある個人データは共有されません", detail: "参加しても、いまこの iPhone にある予定・お金・保証書などは送られません。")
            SettingsNote(text: "招待の期限：\(HouseholdDateText.deadline(preview.expiresAt))")

            LifeButton("参加する", kind: .primary) {
                guard let invite = coordinator.pendingInvite else { return }
                Task {
                    if await household.join(invite) {
                        coordinator.completeJoin()
                    }
                }
            }
            LifeButton("やめる", kind: .secondary) { coordinator.close() }
        }
    }
}

/// アイコン・見出し・説明のカード（招待・わが家の画面で使う）
struct InviteCard: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: LifeSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(LifeColors.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text(title)
                    .font(LifeTypography.headline)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
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

/// 「Appleでサインイン」のボタン（共有用アカウントと同じ見た目）
struct AppleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel("Appleでサインイン")
    }
}

/// 期限の表示（例：10月23日 18:30まで）
enum HouseholdDateText {
    static func deadline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 H:mm"
        return "\(formatter.string(from: date))まで"
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
