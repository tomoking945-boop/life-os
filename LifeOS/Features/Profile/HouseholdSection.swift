import SwiftUI

/// 共有用アカウントの中の「わが家」（2026-10-22。docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
///
/// - わが家が無い：「わが家を作る」（招待リンクを開いていれば「招待内容を確認」も）
/// - わが家がある：メンバー（あなた／パートナー・参加待ち）、共有する種類、オーナーなら招待（作る・共有・取り消す）
/// - UID・招待のリンク（トークン）は画面に文字として出さない。リンクは共有シートで送るだけ
struct HouseholdSection: View {
    @Bindable var household: HouseholdService
    @Environment(InviteLinkCoordinator.self) private var inviteLinks: InviteLinkCoordinator?

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            LifeSectionTitle("わが家")

            if let notice = household.notice {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    InviteCard(systemImage: "checkmark.circle", title: notice, detail: nil)
                    LifeButton("閉じる", kind: .secondary) { household.dismissNotice() }
                }
            }

            stateContent

            if let failure = household.actionFailure {
                VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                    InviteCard(systemImage: "exclamationmark.circle", title: "うまくいきませんでした", detail: failure.message)
                    LifeButton("閉じる", kind: .secondary) { household.dismissActionFailure() }
                }
            }

            if let operation = household.operation {
                HStack(spacing: LifeSpacing.sm) {
                    ProgressView()
                    Text(operation.message)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch household.state {
        case .unavailable:
            InviteCard(systemImage: "icloud.slash", title: "いまは共有を使えません", detail: HouseholdFailure.notConnected.message)

        case .signedOut:
            EmptyView()

        case .idle, .loading:
            HStack(spacing: LifeSpacing.sm) {
                ProgressView()
                Text("わが家を確認しています…")
                    .font(LifeTypography.callout)
                    .foregroundStyle(LifeColors.secondaryText)
            }

        case .none:
            noHousehold

        case .loaded(let summary):
            HouseholdDetail(summary: summary, household: household)

        case .failed(let failure):
            InviteCard(systemImage: "exclamationmark.circle", title: "わが家を読み込めませんでした", detail: failure.message)
            LifeButton("もう一度読み込む", kind: .secondary) {
                Task { await household.refresh() }
            }
        }
    }

    private var noHousehold: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            SettingsNote(text: "わが家を作ると、パートナーを1人招待できます（2人まで）。招待を受け取った人は、招待のリンクから参加します。")
            NavigationLink {
                CreateHouseholdView(household: household)
            } label: {
                LifeButtonLabel(title: "わが家を作る", systemImage: "house", kind: .primary)
            }
            .buttonStyle(LifePressButtonStyle())
            .disabled(household.isWorking)

            if let inviteLinks, inviteLinks.pendingInvite != nil, !inviteLinks.isPresented {
                LifeButton("招待内容を確認", systemImage: "envelope.open", kind: .secondary) {
                    inviteLinks.reopen()
                }
            }

            // 招待リンクをタップしてもブラウザが開いてしまうときの代わりの入り口（参加する前だけ。2026-10-28）
            SettingsNote(text: "招待を受け取った人は、届いたリンクをタップするか、ここに貼り付けて参加できます。")
            InviteLinkEntryLink()
        }
    }
}

/// わが家の中身（メンバー・共有する種類・招待）
private struct HouseholdDetail: View {
    let summary: HouseholdSummary
    @Bindable var household: HouseholdService

    var body: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.md) {
            Text(summary.name)
                .font(LifeTypography.headline)
                .foregroundStyle(LifeColors.text)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(summary.members.enumerated()), id: \.offset) { _, member in
                    SettingsValueRow(title: member.label, value: "参加中")
                }
                if !summary.isFull {
                    SettingsValueRow(title: "パートナー", value: "参加待ち")
                }
            }
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)

            VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                Text("共有する種類")
                    .font(LifeTypography.footnoteEmphasis)
                    .foregroundStyle(LifeColors.secondaryText)
                Text(SharedSpaceKind.titles(summary.sharedKinds))
                    .font(LifeTypography.body)
                    .foregroundStyle(LifeColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsNote(text: "予定やお金などのデータは、まだ共有されません（共有は次のアップデートから、種類ごとに始まります）。共有する種類の変更も、次のアップデートで相手の確認とあわせて使えるようになります。")
            }

            if summary.isOwner {
                inviteSection
            } else if summary.isFull {
                SettingsNote(text: "2人がそろっています。")
            }
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        if summary.isFull {
            SettingsNote(text: "2人がそろっています。")
        } else if let invite = household.activeInvite {
            // この起動中に作った招待：共有シートで送れる（リンクの文字は画面に出さない）
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                SettingsNote(text: "招待の期限：\(HouseholdDateText.deadline(invite.expiresAt))。1回だけ使えます。")
                ShareLink(item: invite.url, subject: Text("くらしOSへの招待"), message: Text("くらしOSのわが家に招待します。24時間以内に開いてください。")) {
                    LifeButtonLabel(title: "共有", systemImage: "square.and.arrow.up", kind: .primary)
                }
                .buttonStyle(LifePressButtonStyle())
                LifeButton("招待を取り消す", kind: .destructive) {
                    Task { await household.revokeInvite() }
                }
                .disabled(household.isWorking)
            }
        } else if let expiresAt = summary.activeInviteExpiresAt {
            // アプリを開き直したなどで、リンクが手元に無い招待：取り消すか、新しく作り直す
            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                SettingsNote(text: "有効な招待があります（期限：\(HouseholdDateText.deadline(expiresAt))）。もう一度送るときは、新しい招待を作ってください（前の招待は使えなくなります）。")
                LifeButton("新しい招待を作る", systemImage: "person.badge.plus", kind: .primary) {
                    Task { await household.createInvite() }
                }
                .disabled(household.isWorking)
                LifeButton("招待を取り消す", kind: .destructive) {
                    Task { await household.revokeInvite() }
                }
                .disabled(household.isWorking)
            }
        } else {
            LifeButton("パートナーを招待", systemImage: "person.badge.plus", kind: .primary) {
                Task { await household.createInvite() }
            }
            .disabled(household.isWorking)
        }
    }
}

/// わが家を作る（名前・共有する種類）
struct CreateHouseholdView: View {
    @Bindable var household: HouseholdService
    @Environment(\.dismiss) private var dismiss
    @State private var name = HouseholdRules.defaultName
    @State private var kinds: Set<SharedSpaceKind> = SharedSpaceKind.defaultSelection

    private var canCreate: Bool {
        HouseholdRules.canCreate(name: name, kinds: kinds) && !household.isWorking
    }

    var body: some View {
        SettingsScreen(title: "わが家を作る", showsQuickAdd: false) {
            SettingsTextField(label: "わが家の名前", text: $name, onCommit: {})

            VStack(alignment: .leading, spacing: LifeSpacing.sm) {
                LifeSectionTitle("共有する種類")
                VStack(spacing: 0) {
                    ForEach(SharedSpaceKind.allCases) { kind in
                        SettingsToggleRow(title: kind.title, isOn: binding(for: kind))
                    }
                }
                if kinds.isEmpty {
                    SettingsNote(text: "1つ以上選んでください。")
                }
            }

            VStack(alignment: .leading, spacing: LifeSpacing.xs) {
                SettingsNote(text: "選んだ種類は「これから共有する場所」を用意するだけです。いま iPhone にある予定やお金などの個人データは送信されません。")
                SettingsNote(text: "送るのは、わが家の名前・選んだ種類・あなたを見分けるための番号（Appleでのサインインの情報）だけです。")
                SettingsNote(text: "作ったあとに種類を変える機能は、次のアップデートで用意します。")
            }

            if let failure = household.actionFailure {
                InviteCard(systemImage: "exclamationmark.circle", title: "わが家を作れませんでした", detail: failure.message)
            }

            if household.operation == .creating {
                HStack(spacing: LifeSpacing.sm) {
                    ProgressView()
                    Text(HouseholdService.Operation.creating.message)
                        .font(LifeTypography.callout)
                        .foregroundStyle(LifeColors.secondaryText)
                }
            }

            LifeButton("わが家を作る", systemImage: "house", kind: .primary) {
                Task {
                    if await household.create(name: name, kinds: kinds) {
                        dismiss()
                    }
                }
            }
            .disabled(!canCreate)
        }
        .onAppear { household.dismissActionFailure() }
    }

    private func binding(for kind: SharedSpaceKind) -> Binding<Bool> {
        Binding(
            get: { kinds.contains(kind) },
            set: { isOn in
                if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
            }
        )
    }
}
