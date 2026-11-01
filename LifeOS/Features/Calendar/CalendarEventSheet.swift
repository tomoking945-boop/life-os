import SwiftUI

/// カレンダーで選んだ日から予定を追加するシート（Build 12）。
/// タイトル・日付・終日／時刻指定・時刻を入れて保存する。保存先はいつも「自分だけ」（予定の共有はまだしない）
struct CalendarEventSheet: View {
    @State private var draft: NewEventDraft
    let onSave: (NewEventDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var isTitleFocused: Bool

    init(draft: NewEventDraft, onSave: @escaping (NewEventDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
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
                } footer: {
                    Text("自分だけの予定として保存します。予定の共有は、まだできません。")
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
                    Button("保存") { onSave(draft) }
                        .disabled(!draft.canSave)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }
}

#Preview {
    CalendarEventSheet(draft: NewEventDraft(day: LifeCalendar.now), onSave: { _ in }, onCancel: {})
}
