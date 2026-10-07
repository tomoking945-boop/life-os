import Foundation
import Observation

@Observable
final class PremiumViewModel {
    private let appState: AppState

    /// 決定済み：初期選択は月額（2026-10-01）。
    var selectedOption: PremiumBillingOption = .monthly

    init(appState: AppState) {
        self.appState = appState
        self.previewTheme = appState.selectedTheme
    }

    let title = "生活OS Premium"
    let catchCopy = "暮らしを、\nもう少し自動に。"
    let trialText = "2週間無料"

    /// 表示のみ（今回はどの機能も外部サービスに接続しない）
    let features = [
        "広告なし",
        "AI利用拡張",
        "レシート読み取り",
        "Appleカレンダー連携",
        "位置リマインダー",
        "高度なウィジェット",
        "献立・買い物連携"
    ]

    let options = PremiumBillingOption.allCases

    // MARK: - LifeOS Themes（テーマとダークモード 2026-10-08：Premium で選んだテーマをアプリ全体に反映）

    let themeSectionTitle = "自分らしい生活OSに"
    let themes = LifeTheme.allCases
    /// プレビューで選んでいるテーマ（最初は今のテーマ）
    var previewTheme: LifeTheme

    /// いまアプリで使っているテーマ（Free は Forest）
    var currentTheme: LifeTheme { appState.effectiveTheme }

    /// 「このテーマを使う」を押せるか（Premium で、今と違うテーマを選んでいるとき）
    var canApplyTheme: Bool { isPremium && previewTheme != currentTheme }

    var applyThemeTitle: String {
        previewTheme == currentTheme ? "\(currentTheme.name) を使用中" : "\(previewTheme.name) を使う"
    }

    var themeNote: String {
        isPremium
            ? "選んだテーマはアプリ全体の色になります（反映すると、最初の画面に戻ります）。ライト／ダークはプロフィール →「表示設定」で選べます。"
            : "テーマは Premium で使えます。Free の今は見た目の確認だけで、アプリは Forest のままです。"
    }

    /// 選んだテーマをアプリ全体に反映する（Premium のときだけ）
    func applyTheme() {
        guard canApplyTheme else { return }
        appState.selectTheme(previewTheme)
    }

    var isPremium: Bool { appState.isPremium }

    var ctaTitle: String {
        isPremium ? "Premiumをご利用中です" : "2週間無料で試す"
    }

    func priceText(for option: PremiumBillingOption) -> String {
        LifeFormatters.yen(option.price)
    }

    func spokenPrice(for option: PremiumBillingOption) -> String {
        LifeFormatters.yenSpoken(option.price)
    }

    /// StoreKit には接続せず、Mock として Premium 状態に切り替えるだけ。
    /// TODO: StoreKit 接続時に購入処理・無料体験の開始処理へ置き換える。
    func startTrial() {
        appState.plan = .premium
    }
}
