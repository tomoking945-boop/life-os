import SwiftUI

/// すべての画面に共通の背景（Calm Future 第4段階）。
/// 今日画面と同じ、時間帯でごく弱く変わる背景を敷く。開発用設定の「時間帯の背景」も反映する。
/// AppState が無いプレビューでも落ちないよう、AppState は任意で受け取る。
struct LifeScreenBackground: View {
    @Environment(AppState.self) private var appState: AppState?

    var body: some View {
        LifeAmbientBackground(timeOfDay: appState?.ambientPreview ?? LifeTimeOfDay(date: LifeCalendar.now))
    }
}

extension View {
    /// 画面の背景を Calm Future の共通背景にする（従来の `LifeColors.background` の代わり）
    func lifeScreenBackground() -> some View {
        background(LifeScreenBackground())
    }
}
