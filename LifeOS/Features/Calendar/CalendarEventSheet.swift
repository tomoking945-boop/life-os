import SwiftUI

enum CalendarEventSheetPurpose: Equatable {
    case add
    case edit

    var title: String {
        switch self {
        case .add: return "予定を追加"
        case .edit: return "予定を編集"
        }
    }
}

/// カレンダーで選んだ日から予定を追加するシート（Build 12）。
/// タイトル・日付・終日／時刻指定・時刻を入れて保存する。
/// Build 14：保存先（自分だけ／わが家で共有）を選べる。初期値は必ず「自分だけ」。
/// 共有できないとき（サインインしていない・わが家に参加していない・わが家の設定で「予定」がオフ）は
/// 「わが家で共有」を選べず、理由を日本語で出す
/// Build 16：予定の編集でも保存先を出す。初期値は今の保存先。
/// 「わが家で共有」→「自分だけ」は、保存するときに確認を出す（CalendarView）
struct CalendarEventSheet: View {
    @State private var draft: NewEventDraft
    /// 「わが家で共有」にできない理由（できるなら nil）。共有している予定の編集では nil（自分だけへ戻せる）
    let sharingBlock: EventSharingBlock?
    let purpose: CalendarEventSheetPurpose
    /// 編集のとき、開いたときの保存先（追加のときは nil）
    let originalDestination: SaveDestination?
    let onSave: (NewEventDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var isTitleFocused: Bool

    init(
        draft: NewEventDraft,
        sharingBlock: EventSharingBlock?,
        purpose: CalendarEventSheetPurpose = .add,
        originalDestination: SaveDestination? = nil,
        onSave: @escaping (NewEventDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        var initial = draft
        // 共有できないときは、必ず「自分だけ」から始める
        if sharingBlock != nil { initial.destination = .personal }
        _draft = State(initialValue: initial)
        self.sharingBlock = sharingBlock
        self.purpose = purpose
        self.originalDestination = originalDestination
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// 保存のときに使う下書き（共有できないのに「わが家で共有」になっていたら「自分だけ」に戻す）
    private var draftToSave: NewEventDraft {
        var saved = draft
        if sharingBlock != nil { saved.destination = .personal }
        return saved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル（必須）", text: $draft.title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .accessibilityLabel("予定のタイトル")
                }

                Section {
                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                    Toggle("終日", isOn: $draft.isAllDay)
                    if !draft.isAllDay {
                        DatePicker("時刻", selection: $draft.time, displayedComponents: .hourAndMinute)
                    }
                }

                // 保存先（Build 14）。Build 16 から編集でも出す（初期値は今の保存先）
                Section {
                    Picker("保存先", selection: $draft.destination) {
                        ForEach(SaveDestination.allCases) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(sharingBlock != nil)
                    .accessibilityLabel("保存先")
                    .accessibilityIdentifier("calendar.eventDestination")
                } header: {
                    Text("保存先")
                } footer: {
                    Text(destinationFooter)
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.calendar, LifeCalendar.calendar)
            .scrollContentBackground(.hidden)
            .background(LifeColors.background.ignoresSafeArea())
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(draftToSave) }
                        .disabled(!draft.canSave)
                        .accessibilityIdentifier("calendar.saveEvent")
                }
            }
            .onAppear { if purpose == .add { isTitleFocused = true } }
        }
    }

    /// 保存先の下の説明
    private var destinationFooter: String {
        if let sharingBlock { return sharingBlock.message }
        if let originalDestination {
            return Self.editFooter(from: originalDestination, to: draft.destination)
        }
        switch draft.destination {
        case .personal:
            return "この iPhone だけに保存します。"
        case .household:
            return "わが家のメンバーのカレンダーと今日にも出ます。送るのはタイトル・日付・時刻だけです。"
        }
    }

    /// 編集のときの保存先の説明（Build 16）
    static func editFooter(from original: SaveDestination, to selected: SaveDestination) -> String {
        switch (original, selected) {
        case (.personal, .personal):
            return "この iPhone だけに保存します。"
        case (.personal, .household):
            return "わが家のメンバーのカレンダーと今日にも出ます。共有の保存が確かめられるまで、この iPhone の予定は消しません。送るのはタイトル・日付・時刻だけです。"
        case (.household, .household):
            return "わが家で共有しています。変更は、パートナーのカレンダーにも反映されます。"
        case (.household, .personal):
            return "保存するときに確認します。変更すると、この予定はパートナーのカレンダーから削除されます。"
        }
    }
}

#Preview {
    CalendarEventSheet(draft: NewEventDraft(day: LifeCalendar.now), sharingBlock: nil, onSave: { _ in }, onCancel: {})
}
