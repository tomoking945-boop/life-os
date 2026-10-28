import SwiftUI
import UIKit

/// 共有用アカウント → わが家 → 設定（2026-10-28。docs/SHARED_TODO_SHOPPING_FOUNDATION.md）
///
/// - わが家の名前・共有する種類：オーナーもパートナーも変えられる（サーバーがメンバーかを確かめる）
/// - 共有する種類：いま2台で同期できるのは ToDo・買い物だけ。ほかは「今後対応」として見せるだけ（保存されていても消さない）
/// - オフにしても、すでにある共有項目は消さない。端末の中の個人データを勝手に共有しない
/// - 危険な操作：わが家の削除（オーナーで1人のときだけ・2回確認）、わが家からの退出（パートナーだけ）
/// - UID・招待のリンク（トークン）は画面に出さない
struct HouseholdSettingsView: View {
    @Bindable var household: HouseholdService
    /// 共有の通知（2026-10-28 Build 8。docs/SHARED_PUSH_NOTIFICATIONS.md）
    var push: SharedPushService = .live
    /// 共有 ToDo・買い物の同期（共有の状態の確認。2026-10-28 Build 9）
    var sharedItems: SharedItemsService = .live
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draftName = ""
    /// 削除の確認の段階（2段階）
    @State private var deletionStep: DeletionStep = .none
    @State private var isConfirmingLeave = false

    enum DeletionStep: Equatable {
        case none
        case first
        case second
    }

    var body: some View {
        SettingsScreen(title: "わが家の設定", showsQuickAdd: false) {
            if let summary = household.state.summary {
                content(summary)
            } else {
                SettingsNote(text: "わが家に参加していません。")
            }
        }
        // 通知の許可の状態を読み直す（許可画面は出さない）
        .task { await push.refreshAuthorization() }
        .onAppear {
            household.dismissActionFailure()
            draftName = household.state.summary?.name ?? ""
        }
        // 1回目の確認
        .alert("わが家を削除しますか？", isPresented: stepBinding(.first)) {
            Button("次へ", role: .destructive) { deletionStep = .second }
            Button("やめる", role: .cancel) { deletionStep = .none }
        } message: {
            Text("わが家と、わが家で共有したToDo・買い物がすべて消えます。サインインのアカウントと、この iPhone の中の個人データは消えません。")
        }
        // 2回目の確認（ここで「削除する」を押したときだけ削除する）
        .alert("本当に削除しますか？", isPresented: stepBinding(.second)) {
            Button("削除する", role: .destructive) {
                deletionStep = .none
                Task {
                    if await household.deleteHousehold() { dismiss() }
                }
            }
            Button("やめる", role: .cancel) { deletionStep = .none }
        } message: {
            Text("元に戻せません。")
        }
        .alert("わが家から退出しますか？", isPresented: $isConfirmingLeave) {
            Button("退出する", role: .destructive) {
                Task {
                    if await household.leaveHousehold() { dismiss() }
                }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("わが家で共有しているToDo・買い物が見られなくなります。わが家と共有項目は、オーナーの側に残ります。この iPhone の中の個人データは消えません。")
        }
    }

    @ViewBuilder
    private func content(_ summary: HouseholdSummary) -> some View {
        // 名前
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            SettingsTextField(label: "わが家の名前", text: $draftName, onCommit: {})
            LifeButton("名前を保存", kind: .secondary) {
                Task { _ = await household.rename(to: draftName) }
            }
            .disabled(!canSaveName(summary))
        }

        // メンバー
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("メンバー")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(summary.members.enumerated()), id: \.offset) { _, member in
                    SettingsValueRow(title: member.label, value: "参加中")
                }
                if !summary.isFull {
                    SettingsValueRow(title: "パートナー", value: "参加待ち")
                }
            }
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
        }

        // 共有する種類
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("共有する種類")
            VStack(spacing: 0) {
                ForEach(SharedSpaceKind.syncSupported) { kind in
                    SettingsToggleRow(title: kind.title, isOn: kindBinding(kind, summary: summary))
                }
            }
            SettingsNote(text: "オンにすると、その種類を作るときに「わが家で共有」を選べるようになります。オフにしても、すでに共有した項目は消えません。今ある個人のデータが勝手に共有されることもありません。")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SharedSpaceKind.comingSoon) { kind in
                    SettingsValueRow(title: kind.title, value: summary.comingSoonKinds.contains(kind) ? "今後対応（選択済み）" : "今後対応")
                }
            }
            .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
            SettingsNote(text: "予定・家事・家計簿・保証書・リスト・メモの共有は、今後のアップデートで対応します。いまは共有されません。")
        }

        pushSection

        syncCheckSection

        // 招待の状態
        VStack(alignment: .leading, spacing: LifeSpacing.xs) {
            LifeSectionTitle("招待")
            SettingsNote(text: inviteStatusText(summary))
        }

        failureAndProgress

        // 危険な操作
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("危険な操作")
            if summary.canDelete {
                LifeButton("わが家を削除", systemImage: "trash", kind: .destructive) {
                    deletionStep = .first
                }
                .disabled(household.isWorking)
                SettingsNote(text: "メンバーがあなた1人のときだけ削除できます。")
            } else if summary.isOwner {
                SettingsNote(text: "パートナーが参加しているあいだは、わが家を削除・退出できません（オーナーを引き継ぐ機能は今後対応します）。")
            }
            if summary.canLeave {
                LifeButton("わが家から退出", systemImage: "rectangle.portrait.and.arrow.right", kind: .destructive) {
                    isConfirmingLeave = true
                }
                .disabled(household.isWorking)
                SettingsNote(text: "退出したあとは、別の招待からわが家に参加できます。")
            }
        }
    }

    /// 共有の状態の確認（2026-10-28 Build 9）：共有の保存が断られたとき、どこで止まっているかを確かめる（読み取りだけ）
    private var syncCheckSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("共有の状態")
            if let failure = sharedItems.lastFailure {
                SettingsNote(text: "最近の共有の保存：失敗（\(failure.reason)）")
            }
            LifeButton("共有の状態を確かめる", systemImage: "stethoscope", kind: .secondary) {
                Task { await sharedItems.runDiagnosis() }
            }
            if let diagnosis = sharedItems.diagnosis {
                VStack(alignment: .leading, spacing: LifeSpacing.xxs) {
                    ForEach(diagnosis.lines, id: \.self) { line in
                        Text(line)
                            .font(LifeTypography.footnote)
                            .foregroundStyle(LifeColors.text)
                    }
                }
                .padding(LifeSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lifeSurface(.sunken, cornerRadius: LifeRadius.band)
                SettingsNote(text: "うまくいかないときは、この結果を開発者に伝えてください（アカウントの番号などは表示していません）。")
            }
        }
    }

    /// 共有の通知（初期値はオフ。オンにしたときだけ iOS の許可画面を出す）
    private var pushSection: some View {
        VStack(alignment: .leading, spacing: LifeSpacing.sm) {
            LifeSectionTitle("共有の通知")
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "共有の通知を受け取る",
                    detail: "パートナーが共有のToDo・買い物を追加・変更したときにお知らせします",
                    isOn: Binding(
                        get: { push.preferences.receives },
                        set: { isOn in Task { await push.setReceives(isOn) } }
                    )
                )
                SettingsToggleRow(
                    title: "通知に項目名を表示する",
                    detail: "オフのときは「わが家のToDoが更新されました」のように、項目名を出しません",
                    isOn: Binding(
                        get: { push.preferences.receives && push.preferences.showsTitle },
                        set: { isOn in Task { await push.setShowsTitle(isOn) } }
                    )
                )
                .disabled(!push.canChangeShowsTitle)
            }
            if let message = push.status.message {
                SettingsNote(text: message)
            }
            if push.status == .denied || (push.authorization == .denied && push.preferences.receives) {
                LifeButton("設定を開く", systemImage: "gear", kind: .secondary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
            SettingsNote(text: "自分の操作・自分だけの項目では通知しません。通知に出すのは、項目名を表示するときも名前だけです。")
        }
    }

    @ViewBuilder
    private var failureAndProgress: some View {
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

    private func canSaveName(_ summary: HouseholdSummary) -> Bool {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != summary.name
            && HouseholdRules.canCreate(name: trimmed, kinds: [.todo])
            && !household.isWorking
    }

    private func inviteStatusText(_ summary: HouseholdSummary) -> String {
        if summary.isFull { return "2人がそろっています。" }
        if !summary.isOwner { return "招待を作れるのはオーナーだけです。" }
        if let expiresAt = summary.activeInviteExpiresAt {
            return "有効な招待があります（期限：\(HouseholdDateText.deadline(expiresAt))）。送り直すときは、前の画面で新しい招待を作ってください。"
        }
        return "有効な招待はありません。前の画面の「パートナーを招待」から作れます。"
    }

    private func kindBinding(_ kind: SharedSpaceKind, summary: HouseholdSummary) -> Binding<Bool> {
        Binding(
            get: { summary.sharedKinds.contains(kind) },
            set: { isOn in
                var sync = Set(summary.sharedKinds.filter(\.isSyncSupported))
                if isOn { sync.insert(kind) } else { sync.remove(kind) }
                // 1つも残らない変更は送らない（わが家の共有する種類は1つ以上）
                guard summary.sharedKinds(afterSettingSyncKinds: sync) != nil else { return }
                Task { _ = await household.setSyncKinds(sync) }
            }
        )
    }

    /// 確認の段階の表示。閉じたとき、まだその段階のままなら「やめる」と同じにする（次の段階へ進んだあとは戻さない）
    private func stepBinding(_ step: DeletionStep) -> Binding<Bool> {
        Binding(
            get: { deletionStep == step },
            set: { isPresented in
                if !isPresented, deletionStep == step { deletionStep = .none }
            }
        )
    }
}
