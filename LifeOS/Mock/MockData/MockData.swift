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
        let yesterday = LifeCalendar.calendar.date(byAdding: .day, value: -1, to: today) ?? today
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
            // 習慣（水を飲む・ストレッチ）は Calm Future 第3段階から、毎日くり返す `Habit` として `habits()` に置く。
            // 昨日残ったもの（v2「未完了救済」の確認用 Mock）
            LifeItem(title: "粗大ゴミの申し込み", kind: .todo, ownership: .personal,
                     date: yesterday, assignee: .me),
            LifeItem(title: "郵便を出す", kind: .todo, ownership: .personal,
                     date: yesterday, assignee: .me)
        ]
    }

    // MARK: - 習慣（Calm Future 第3段階）

    /// 余力が「少ない」日にも出す軽い習慣（Mock）。
    /// 新しい解釈：仕様に区別が無いため、「水を飲む」を軽い習慣、「ストレッチ」を通常の習慣とした。
    static let lightHabitTitles: Set<String> = ["水を飲む"]

    /// v2 仕様の習慣の例。リズムの見え方を確認できるよう、直近のできた日を入れておく。
    /// 水を飲む：6日中5日（最近、自然に続いています）／ストレッチ：6日中3日（少しずつ、リズムができています）
    static func habits(now: Date = LifeCalendar.now) -> [Habit] {
        let today = LifeCalendar.startOfDay(now)
        func daysAgo(_ days: Int) -> Date {
            LifeCalendar.calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        return [
            Habit(title: "水を飲む", isLight: lightHabitTitles.contains("水を飲む"),
                  startedAt: daysAgo(30), doneDays: [1, 2, 4, 5, 6].map(daysAgo)),
            Habit(title: "ストレッチ", isLight: lightHabitTitles.contains("ストレッチ"),
                  startedAt: daysAgo(30), doneDays: [2, 4, 6].map(daysAgo))
        ]
    }

    // MARK: - 暮らしメモリー

    /// v2 仕様の Mock 例（シャンプー・歯医者・エアコンフィルター・家賃・ゴミ）
    /// Calm Future 第3段階：前回・平均周期・誰が対応したか・季節・提案の履歴を確認できるよう、記録の例を入れている。
    static func memories(now: Date = LifeCalendar.now) -> [LifeMemory] {
        let today = LifeCalendar.startOfDay(now)
        func daysAgo(_ days: Int) -> Date {
            LifeCalendar.calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        return [
            LifeMemory(title: "シャンプー",
                       rule: .sinceLast(lastDate: daysAgo(49), dueAfterDays: 42),
                       action: .addToShopping("シャンプーを買う"),
                       history: [
                           MemoryRecord(date: daysAgo(140), by: .me),
                           MemoryRecord(date: daysAgo(93), by: .me),
                           MemoryRecord(date: daysAgo(49), by: .partner)
                       ],
                       decisions: [
                           MemoryDecision(decidedAt: daysAgo(95), choice: .accepted),
                           MemoryDecision(decidedAt: daysAgo(51), choice: .accepted)
                       ]),
            LifeMemory(title: "歯医者",
                       rule: .sinceLast(lastDate: daysAgo(182), dueAfterDays: 180),
                       action: .addToTodo("歯医者を予約する"),
                       history: [
                           MemoryRecord(date: daysAgo(365), by: .me),
                           MemoryRecord(date: daysAgo(182), by: .me)
                       ]),
            // 新しい解釈：季節の例として、冷暖房を使う月（6〜9月・12〜2月）は30日ごとにする
            LifeMemory(title: "エアコンフィルター掃除",
                       rule: .sinceLast(lastDate: daysAgo(61), dueAfterDays: 60),
                       action: .addOnSaturday("エアコンフィルター掃除"),
                       history: [
                           MemoryRecord(date: daysAgo(128), by: .me),
                           MemoryRecord(date: daysAgo(95), by: .partner),
                           MemoryRecord(date: daysAgo(61), by: .me)
                       ],
                       decisions: [
                           MemoryDecision(decidedAt: daysAgo(96), choice: .skipped)
                       ],
                       seasonal: SeasonalCycle(months: [6, 7, 8, 9, 12, 1, 2], dueAfterDays: 30,
                                               note: "冷暖房を使う季節（6〜9月・12〜2月）")),
            LifeMemory(title: "家賃",
                       rule: .monthlyDay(day: 27, noticeDaysBefore: 3),
                       action: .addToTodo("家賃を払う")),
            LifeMemory(title: "ゴミ",
                       rule: .weekdays([3, 6]),
                       action: .notifyOnly)
        ]
    }

    // MARK: - よく買うもの

    /// v2 仕様 11 の Mock 例（牛乳 食品/冷蔵、ティッシュ 日用品 など）
    static func frequentPurchases(now: Date = LifeCalendar.now) -> [FrequentPurchase] {
        let today = LifeCalendar.startOfDay(now)
        func daysAgo(_ days: Int) -> Date {
            LifeCalendar.calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        return [
            FrequentPurchase(title: "牛乳", categories: [.food, .chilled], lastPurchasedAt: daysAgo(4)),
            FrequentPurchase(title: "卵", categories: [.food, .chilled], lastPurchasedAt: daysAgo(6)),
            FrequentPurchase(title: "ティッシュ", categories: [.dailyGoods], lastPurchasedAt: daysAgo(21)),
            FrequentPurchase(title: "お茶", categories: [.drinks], lastPurchasedAt: daysAgo(9)),
            FrequentPurchase(title: "食パン", categories: [.food], lastPurchasedAt: daysAgo(3))
        ]
    }

    /// 共有スターターで選べる「よく買うもの」の候補
    static let starterFrequentCandidates = ["牛乳", "卵", "食パン", "米", "トイレットペーパー", "洗剤"]

    // MARK: - 献立 → 買い物（Mock）

    /// v2 仕様 12 の固定データ（月：カレー、火：鮭、水：外食）
    /// TODO: 献立の入力・提案（AI）・材料の分量は未実装。高度な献立連携は Premium 候補。
    static let mealPlan: [MealPlanDay] = [
        MealPlanDay(id: "mon", dayLabel: "月", dish: "カレー", ingredients: ["玉ねぎ", "人参", "カレールー"]),
        MealPlanDay(id: "tue", dayLabel: "火", dish: "鮭", ingredients: ["鮭"]),
        MealPlanDay(id: "wed", dayLabel: "水", dish: "外食", ingredients: [])
    ]

    // MARK: - 家事オートパイロット

    /// v2 仕様の Mock ロジック（少ない＝2件、普通＝＋風呂掃除、余裕あり＝＋掃除機・シーツ交換）
    static let choreTemplates: [ChoreTemplate] = [
        ChoreTemplate(id: "trash", title: "ゴミをまとめる", minutes: 2, minimumEnergy: .low),
        ChoreTemplate(id: "laundry", title: "洗濯機を回す", minutes: 3, minimumEnergy: .low),
        ChoreTemplate(id: "bath", title: "風呂掃除", minutes: 10, minimumEnergy: .normal),
        ChoreTemplate(id: "vacuum", title: "掃除機", minutes: 15, minimumEnergy: .high),
        ChoreTemplate(id: "sheets", title: "シーツ交換", minutes: 10, minimumEnergy: .high)
    ]

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
