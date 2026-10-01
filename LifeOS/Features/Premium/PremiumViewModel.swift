import Foundation
import Observation

@Observable
final class PremiumViewModel {
    private let appState: AppState

    /// 決定済み：初期選択は月額（2026-10-01）。
    var selectedOption: PremiumBillingOption = .monthly

    init(appState: AppState) {
        self.appState = appState
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
