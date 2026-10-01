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
    /// TODO: 各項目の種類・担当者の正式な割り当てを確認する（特に「外食」の担当、「クリーニング受取」の種類）。
    /// 決定済み：「ゴミ出し」はレイアウト例に合わせ、自分の家事として追加（2026-09-28）。
    /// TODO: 「筋トレ」はMockデータ一覧にあるがレイアウト例のTODAYには無い。現状はMockデータ一覧を優先して表示。
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
                     date: LifeCalendar.date(on: today, hour: 20, minute: 0), hasTime: true),
            LifeItem(title: "牛乳を買う", kind: .shopping, ownership: .shared,
                     date: today, assignee: .either),
            LifeItem(title: "クリーニング受取", kind: .chore, ownership: .shared,
                     date: today, assignee: .partner)
        ]
    }

    // MARK: - お金

    /// TODO: Netflix の支払日は仕様未定。「今日 ¥3,520」と合わせるため今日以外（3日前）にしている。
    static func expenses(now: Date = LifeCalendar.now) -> [Expense] {
        let today = LifeCalendar.startOfDay(now)
        let threeDaysAgo = LifeCalendar.calendar.date(byAdding: .day, value: -3, to: today) ?? today
        return [
            // TODO: 「スーパー」のカテゴリーは仕様未定。現状は「食費」。
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

    /// TODO: 各リストの中身は仕様未定のため空。
    static let lists: [LifeList] = [
        LifeList(title: "行きたい場所"),
        LifeList(title: "観たいもの"),
        LifeList(title: "欲しいもの"),
        LifeList(title: "二人で相談")
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
