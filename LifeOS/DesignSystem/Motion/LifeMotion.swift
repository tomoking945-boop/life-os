import SwiftUI

/// 動きのトークン（Calm Future）。
/// 派手なアニメーションは使わない。どれも短く、ゆるやかに。
/// Reduce Motion のときはアニメーションしない（`withLifeAnimation` を使う）。
enum LifeMotion {
    /// 小さな切り替え（チェック・開閉）
    static let quickDuration: Double = 0.2
    /// ふつうの切り替え（並び替え・表示の入れ替え）
    static let standardDuration: Double = 0.3
    /// 背景・空気感の変化
    static let gentleDuration: Double = 0.6

    static let quick = Animation.easeOut(duration: quickDuration)
    static let standard = Animation.easeInOut(duration: standardDuration)
    static let gentle = Animation.easeInOut(duration: gentleDuration)

    /// 一言だけの表示が消えるまで（秒）
    static let bannerSeconds: Double = 3
    /// 「元に戻す」付きの表示が消えるまで（秒）。押す時間を残すため長め
    static let undoBannerSeconds: Double = 6

    /// Reduce Motion のときは nil（アニメーションしない）
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Reduce Motion を考慮して変更する
func withLifeAnimation(_ animation: Animation = LifeMotion.standard, reduceMotion: Bool, _ changes: () -> Void) {
    if reduceMotion {
        changes()
    } else {
        withAnimation(animation) { changes() }
    }
}
