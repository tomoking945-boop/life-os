import SwiftUI

/// カレンダーで選んだ日から予定を追加するシート（Build 12）。
/// タイトル・日付・終日／時刻指定・時刻を入れて保存する。
/// Build 14：保存先（自分だけ／わが家で共有）を選べる。初期値は必ず「自分だけ」。
/// 共有できないとき（サインインしていない・わが家に参加していない・わが家の設定で「予定」がオフ）は
/// 「わが家で共有」を選べず、理由を日本語で出す
struct CalendarEventSheet: View {
    @State private var draft: NewEventDraft
    /// 「わが家で共有」にできない理由（できるなら nil）
    let sharingBlock: EventSharingBlock?
    let onSave: (NewEventDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var isTitleFocused: Bool

    init(
        draft: NewEventDraft,
        sharingBlock: EventSharingBlock?,
        onSave: @escaping (NewEventDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        var initial = draft
        // 共有できないときは、必ず「自分だけ」から始める
        if sharingBlock != nil { initial.destination = .personal }
        _draft = State(initialValue: initial)
        self.sharingBlock = sharingBlock
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

                // 保存先（Build 14）。初期値は「自分だけ」。共有できないときは選べず、理由を出す
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
            .navigationTitle("予定を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                        .foregroundStyle(LifeColors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(draftToSave) }
                        .disabled(!draft.canSave)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }

    /// 保存先の下の説明
    private var destinationFooter: String {
        if let sharingBlock { return sharingBlock.message }
        switch draft.destination {
        case .personal:
            return "この iPhone だけに保存します。"
        case .household:
            return "わが家のメンバーのカレンダーと今日にも出ます。送るのはタイトル・日付・時刻だけです。"
        }
    }
}

#Preview {
    CalendarEventSheet(draft: NewEventDraft(day: LifeCalendar.now), sharingBlock: nil, onSave: { _ in }, onCancel: {})
}
