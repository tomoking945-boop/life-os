import SwiftUI
import UIKit

/// キーボードを閉じやすくする（2026-11-10 Build 22。docs/BUILD_22_KEYBOARD_AND_RECEIPT_NUMBER_ACCURACY.md）。
///
/// - 標準の機能を先に使う：`@FocusState`（入力欄ごと）・`.scrollDismissesKeyboard(.interactively)`（スクロールで閉じる）・
///   キーボードの上の「完了」（`ToolbarItemGroup(placement: .keyboard)`）
/// - 背景（入力欄の外）をタップしたときは、画面の上に「タップを奪わない」見えない部品を置いて閉じる：
///   タップをボタン・候補・保存・キャンセルへそのまま届ける（cancelsTouchesInView = false・ほかのジェスチャーと同時に動く）。
///   入力欄の上のタップでは閉じない（別の入力欄へ移れる）
/// - 画面を離れたとき・別のタブへ移ったときも閉じる。閉じても入力した文字はそのまま残る（閉じるだけで、値は変えない）
enum LifeKeyboard {
    /// 今のキーボードを閉じる（入力中の文字はそのまま）
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 背景のタップで閉じてよいか：入力欄（とその中）のタップでは閉じない。それ以外（ボタン・候補・空いた場所）は閉じる
    @MainActor
    static func shouldDismiss(forTouchIn view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView || candidate is UISearchBar { return false }
            current = candidate.superview
        }
        return true
    }
}

/// 背景のタップでキーボードを閉じる、タップを奪わないジェスチャー（Build 22）
@MainActor
final class KeyboardDismissTapHandler: NSObject, UIGestureRecognizerDelegate {
    let recognizer: UITapGestureRecognizer

    override init() {
        recognizer = UITapGestureRecognizer()
        super.init()
        recognizer.addTarget(self, action: #selector(handleTap(_:)))
        // タップはボタン・候補・保存・キャンセルへそのまま届ける（奪わない・遅らせない）
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.requiresExclusiveTouchType = false
        recognizer.delegate = self
    }

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        dismissKeyboard()
    }

    /// 付けている画面（ウインドウ）のキーボードを閉じる（入力した文字は変えない）
    func dismissKeyboard() {
        recognizer.view?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        LifeKeyboard.shouldDismiss(forTouchIn: touch.view)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// 画面のウインドウに、タップを奪わないジェスチャーを付け外しする見えない部品（Build 22）
private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        InstallerView(frame: .zero)
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let handler: KeyboardDismissTapHandler
        private weak var attachedWindow: UIWindow?

        override init(frame: CGRect) {
            handler = KeyboardDismissTapHandler()
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if attachedWindow !== window {
                attachedWindow?.removeGestureRecognizer(handler.recognizer)
                attachedWindow = window
                window?.addGestureRecognizer(handler.recognizer)
            }
        }
    }
}

extension View {
    /// キーボードを閉じやすくする（スクロールで閉じる・背景のタップで閉じる・画面を離れたら閉じる。Build 22）
    func lifeKeyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissTapInstaller().frame(width: 0, height: 0).accessibilityHidden(true))
            .onDisappear { LifeKeyboard.dismiss() }
    }

    /// キーボードの上に「完了」を出す（押すとキーボードを閉じる。入力した文字はそのまま。Build 22）
    func lifeKeyboardDoneButton(_ action: @escaping () -> Void = {}) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    action()
                    LifeKeyboard.dismiss()
                }
                .accessibilityHint("キーボードを閉じます。入力した内容はそのまま残ります")
            }
        }
    }
}
