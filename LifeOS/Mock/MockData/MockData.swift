import Foundation

/// UIプロトタイプ用の固定データ。
/// 外部サービス接続時は LifeStore の読み込み元をここから差し替える。
enum MockData {
    // MARK: - プロフィール

    static let profile = UserProfile(
        name: "池上",
        groupName: "わが家",
        members: [
            Member(name: "池上", isCurrentUser: true),
            Member(name: "妻", isCurrentUser: false)
        ]
    )

    // MARK: - 今日の項目

    /// 仕様「今日画面のMockデータ」の6件＋レイアウト例の「ゴミ出し」。
    /// 種類（予定 / ToDo / 家事 / 買い物 / 支払予定）と担当者の割り当ては仕様に明記がないため、
    /// タイトルから最低限判断している。
    /// 決定済み：「クリーニング受取」は家事（2026-10-01）。
    /// 決定済み：「外食」の担当は「どちらでも」（2026-10-01）。
    /// 決定済み：「ゴミ出し」はレイアウト例に合わせ、自分の家事として追加（2026-09-28）。
    /// 「筋トレ」はMockデータ一覧にあるがレイアウト例のTODAYには無い。Mockデータ一覧を優先して表示している。
    static func items(now: Date = LifeCalendar.now) -> [LifeItem] {
        let today = LifeCalendar.startOfDay(now)
        return [
            // 自分
            LifeItem(title: "歯医者", kind: .event, ownership: .personal,
                     date: LifeCalendar.date(on: today, hour: 10, minute: 30), hasTime: true, assignee: .me),
            LifeItem(title: "ゴミ出し", kind: .chore, ownership: .personal,
                     date: today, assignee: .me),
            LifeItem(title: "電気代を払う", kind: .payment, ownership: .personal,
                     date: today, assignee: .me),
            LifeItem(title: "筋トレ", kind: .todo, ownership: .personal,
                     date: today, assignee: .me),
            // 共有
            LifeItem(title: "外食", kind: .event, ownership: .shared,
                     date: LifeCalendar.date(on: today, hour: 20, minute: 0), hasTime: true, assignee: .either),
            LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .shared,
                     date: today, assignee: .either),
            LifeItem(title: "クリーニング受取", kind: .chore, ownership: .shared,
                     date: today, assignee: .partner),
            // 習慣（v2 仕様の例）
            // TODO: 習慣を毎日くり返す仕組み（くり返し設定）は未実装。現状は Mock の日付の分だけ表示する。
            LifeItem(title: "水を飲む", kind: .habit, ownership: .personal,
                     date: today, assignee: .me),
            LifeItem(title: "ストレッチ", kind: .habit, ownership: .personal,
                     date: today, assignee: .me)
        ]
    }

    // MARK: - おまかせInbox

    /// v2 仕様の初期 Mock 例（分類・日時・担当は未設定のまま保存されたメモ）
    static func inbox(now: Date = LifeCalendar.now) -> [InboxItem] {
        [
            InboxItem(text: "明日牛乳買う", createdAt: now),
            InboxItem(text: "妻と旅行相談", createdAt: now),
            InboxItem(text: "電気代を払う", createdAt: now),
            InboxItem(text: "美容院を予約する", createdAt: now)
        ]
    }

    // MARK: - お金

    /// 決定済み：Netflix は3日前・サブスク、スーパーは今日・食費（2026-10-01）。
    static func expenses(now: Date = LifeCalendar.now) -> [Expense] {
        let today = LifeCalendar.startOfDay(now)
        let threeDaysAgo = LifeCalendar.calendar.date(byAdding: .day, value: -3, to: today) ?? today
        return [
            Expense(title: "スーパー", amount: 3_520, category: .food, date: today),
            Expense(title: "Netflix", amount: 1_590, category: .subscription, date: threeDaysAgo)
        ]
    }

    /// 今月合計 ¥82,450 / 予算 ¥120,000（残り ¥37,550）
    /// TODO: 今月合計は仕様の固定値。支出一覧（2件）の合計とは一致しない。
    static func budget(now: Date = LifeCalendar.now) -> MonthlyBudget {
        MonthlyBudget(month: LifeCalendar.startOfMonth(now), spent: 82_450, budget: 120_000)
    }

    // MARK: - リスト

    /// 決定済み：リストの項目は詳細画面で追加・削除できる。各リストに表示確認用の例を2件ずつ入れる（2026-10-01）。
    static let lists: [LifeList] = [
        LifeList(title: "行きたい場所", items: [
            LifeListItem(title: "箱根の温泉"),
            LifeListItem(title: "近所の新しいカフェ")
        ]),
        LifeList(title: "観たいもの", items: [
            LifeListItem(title: "話題の映画"),
            LifeListItem(title: "美術館の企画展")
        ]),
        LifeList(title: "欲しいもの", items: [
            LifeListItem(title: "加湿器"),
            LifeListItem(title: "旅行用のバッグ")
        ]),
        LifeList(title: "二人で相談", items: [
            LifeListItem(title: "年末の帰省"),
            LifeListItem(title: "冷蔵庫の買い替え")
        ])
    ]

    // MARK: - なんでも追加（AIを使わない固定結果）

    /// 「整理する」を押したときの固定結果
    /// 追加先（自分 / 共有）は確認画面で選ぶ（QuickAddViewModel.addSelected で上書き）。
    static func quickAddResults(now: Date = LifeCalendar.now) -> [LifeItem] {
        let today = LifeCalendar.startOfDay(now)
        return [
            LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .personal, date: today, assignee: .me),
            LifeItem(title: "卵を買う", kind: .shopping, ownership: .personal, date: today, assignee: .me),
            LifeItem(title: "美容院", kind: .event, ownership: .personal,
                     date: LifeCalendar.date(on: today, hour: 19, minute: 0), hasTime: true, assignee: .me)
        ]
    }
}
