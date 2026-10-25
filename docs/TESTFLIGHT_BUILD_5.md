# TestFlight ビルド5（わが家の作成・招待・参加）

作業用ブランチ：`prepare-testflight-5`（main `12407c2` から作成。**main にはまだ入れていない**）

## 目的

わが家の作成・招待・参加・メンバー表示を、**別の Apple ID の iPhone どうし** で TestFlight から確かめる。
サーバー側（Firestore のルール・索引、Functions 8個）は 2026-10-25 に本番へ公開済み（[FIREBASE_INVITE_JOIN_MEMBERSHIP.md](FIREBASE_INVITE_JOIN_MEMBERSHIP.md) の「本番公開結果」）。

## 設定（`LifeOS.xcodeproj/project.pbxproj`）

| 項目 | 値 | 対象 |
| --- | --- | --- |
| Version（`MARKETING_VERSION`） | 1.0（変更なし） | アプリ・テスト（Debug／Release） |
| Build（`CURRENT_PROJECT_VERSION`） | 4 → **5** | アプリ・テスト（Debug／Release）の4か所 |
| Bundle Identifier | アプリ `com.tomoking945boop.lifeos`、テスト `com.tomoking945boop.lifeos.tests`（変更なし） | |
| 暗号化の申告（`ITSAppUsesNonExemptEncryption`） | NO（変更なし） | アプリ（Debug／Release） |

ビルド5のための変更は Build 番号と説明の文書だけ。アプリの機能のコード、Functions、Firestore のルール・索引、Firebase と Apple の設定、アイコン、通知は変えていない。Apple の Team・証明書・秘密鍵・Debug Token は GitHub に保存していない。

## ビルド4との違い

- わが家の作成・招待・参加・メンバー表示・共有する種類（[FIREBASE_INVITE_JOIN_MEMBERSHIP.md](FIREBASE_INVITE_JOIN_MEMBERSHIP.md)）
- 招待リンク（Universal Links。Associated Domains `applinks:kurashi-os-production.web.app`）を受け取って、参加の確認へ進む（[FIREBASE_INVITE_LINK_FOUNDATION.md](FIREBASE_INVITE_LINK_FOUNDATION.md)）
  - ビルド4には Associated Domains が入っていないので、TestFlight で招待リンクからアプリが開くのはビルド5から
- アカウントの番号（UID）を表示しない
- アカウント削除のあとの Firestore の整理（サーバー側。[FIREBASE_ACCOUNT_DELETION_CLEANUP.md](FIREBASE_ACCOUNT_DELETION_CLEANUP.md)）
- Firebase の部品に FirebaseFunctions を追加
- **生活データ（予定・ToDo・家計簿・保証書など）の同期はまだ無い**。わが家に参加しても、端末の中のデータは送られない

## Archive の手順（Mac）

（この作業では Archive・App Store Connect へのアップロードはしていない）

1. GitHub でブランチ `prepare-testflight-5` を選び、ZIP でダウンロードして Xcode で開く（Firebase の部品、特に FirebaseFunctions の読み込みが終わるまで待つ）
2. Signing & Capabilities で自分の Team を選び、**Associated Domains・Sign in with Apple・App Attest** の3つがあることを確かめる（この変更は GitHub に送らない）
3. ⌘U でテスト（301件の想定・失敗0件を確認）
4. 上の端末の選択を「Any iOS Device (arm64)」にする
5. メニューの Product → Archive（Release なので App Check は App Attest を使う）
6. Organizer で、いちばん上の Archive が **Version 1.0・Build 5** であることを確かめる
7. 「Distribute App」→ TestFlight 向け（「TestFlight Internal Only」など）→ Upload（Firebase の部品の dSYM の警告が出ても、これまでと同じくアップロードは続けてよい）
8. App Store Connect の TestFlight で 1.0 (5) の処理が終わったら、内部テスターに追加する

## TestFlight 版で確かめること

2台の iPhone と、**別々の Apple ID** を使う（A：オーナー、B：パートナー）。どちらも TestFlight から 1.0 (5) を入れる。

1. 既存の機能：今日・カレンダー・やること・リスト・お金・なんでも追加・保証書・通知がこれまでどおり使える
2. A：プロフィール → 共有用アカウント → Appleでサインイン。アカウントの番号が表示されないこと
3. A：「わが家を作る」→ 名前（わが家）・共有する種類（はじめは ToDo・買い物）を確かめて作る。メンバーが「あなた（オーナー）」と「パートナー：参加待ち」になる
4. A：「パートナーを招待」→ 期限が24時間後になっている →「共有」で、B にメッセージなどで送る
5. B：受け取ったリンクをタップ → Safari ではなく「くらしOS」が開き、「わが家への招待を受け取りました」が出る
6. B：「招待を確認」→ サインインしていなければ「参加するにはAppleでサインインしてください」。ボタンを押したときだけサインインが始まる（一度やめて、参加しないことも確かめる）
7. B：サインイン後、「○○への招待」・共有される種類・「現在iPhoneにある個人データは共有されません」が出る →「参加する」→「わが家に参加しました」とメンバーの画面
8. A：共有用アカウントを開き直す → メンバーが「あなた（オーナー）」と「パートナー」になり、招待のボタンが消える（2人そろった）
9. B が同じリンクをもう一度開いても、参加し直しにならない。別の人（3人目）が同じリンクを開いても参加できない（使用済み）
10. （任意）A が招待を作り直す・取り消すと、前のリンクが使えなくなる
11. Firebase Console → App Check →「API」→ Authentication で「確認済みのリクエスト」が増えていること（強制適用はまだ変えない。Functions はコードで App Check を必須にしているので、App Check の情報が無ければ参加などが断られる）
12. Firestore の中身：予定・ToDo などの生活データが無いこと（groups・members・memberships・invites だけ）

App Store への審査提出・公開はしない。問題がなければ、このブランチを main に入れる。

## 元に戻す方法

- このブランチは main に入れていない。やめるときはブランチを使わなければよい
- TestFlight で問題があれば、そのビルドのテストを止め、ビルド4を使い続ける（ビルド4にはわが家の機能が無い）
- サーバー側（Functions・ルール）を止める方法は [FIREBASE_INVITE_JOIN_MEMBERSHIP.md](FIREBASE_INVITE_JOIN_MEMBERSHIP.md) の「元に戻す方法」
