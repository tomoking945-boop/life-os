import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import LifeOS

// Premium「大切な書類」保証書管理 MVP（2026-10-13）のテスト（docs/WARRANTY_MANAGEMENT_MVP_SPEC.md 12）
// - 期限の計算（1年・うるう日・月末）
// - 以前の保存データ（保証書なし）から読める・再起動後も残る
// - Free / Premium / Premium 終了後
// - 自分／共有の初期値と変更
// - 通知：過去は予約しない・合計59件以下・削除した保証書の通知が残らない
// - 写真：原本のまま・UUID のファイル名・失敗時に孤立ファイルを残さない・削除後に残らない
// - 読み取り候補：承認前は反映しない・入力済みを上書きしない
// - 外部通信なし

// MARK: - 補助

enum WarrantyTestImages {
    /// 小さな PNG（色ごとに違うデータ）
    static func png(_ color: UIColor = .systemTeal, size: CGFloat = 24) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// 位置情報（GPS）が入った JPEG
    static func jpegWithLocation() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let data = NSMutableData()
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            fatalError("テスト用の画像を作れませんでした")
        }
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 34.65,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 135.5,
            kCGImagePropertyGPSLongitudeRef: "E"
        ]
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 文字を書いた画像（Vision の読み取り用）
    static func text(_ lines: [String]) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 900, height: 120 * CGFloat(lines.count) + 80)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 40, y: 40 + CGFloat(index) * 120), withAttributes: attributes)
            }
        }
    }
}

/// 一時フォルダを使うテストの土台（実際の利用者データと衝突させない）
class WarrantyStorageTestCase: XCTestCase {
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WarrantyTests-\(UUID().uuidString)", isDirectory: true)
        LocalStorage.directoryOverride = temporaryDirectory
    }

    override func tearDown() {
        LocalStorage.directoryOverride = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    func makeStorage() -> WarrantyAttachmentStorage {
        WarrantyAttachmentStorage(root: temporaryDirectory, staging: temporaryDirectory.appendingPathComponent("staging", isDirectory: true))
    }

    /// 保存する LifeStore（以前の利用者と同じ：Mock で始まる）
    func makePersistentStore() -> LifeStore {
        let store = LifeStore.persistent()
        store.warrantyStorage = makeStorage()
        return store
    }

    func document(_ title: String = "冷蔵庫", expiresAt: Date? = nil, now: Date = TestDates.friday) -> WarrantyDocument {
        WarrantyDocument(
            title: title,
            category: .appliance,
            warrantyExpiresAt: expiresAt,
            expirationSource: expiresAt == nil ? .none : .manual,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - 期限の計算

final class WarrantyExpirationTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date { TestDates.make(year, month, day) }

    func testPurchaseDatePlusOneYear() {
        let purchase = date(2026, 10, 13)
        let oneYear = WarrantyDuration(value: 1, unit: .year)
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: purchase, duration: oneYear), date(2027, 10, 13))
        XCTAssertEqual(WarrantyExpiration.basisText(purchaseDate: purchase, duration: oneYear), "購入日 2026/10/13 ＋ 1年")
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: purchase, duration: WarrantyDuration(value: 90, unit: .day)), date(2027, 1, 11))
        XCTAssertNil(WarrantyExpiration.expirationDate(purchaseDate: purchase, duration: WarrantyDuration(value: 0, unit: .year)))
    }

    /// うるう日：応当日が無ければその月の末日
    func testLeapDay() {
        let leapDay = date(2024, 2, 29)
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: leapDay, duration: WarrantyDuration(value: 1, unit: .year)), date(2025, 2, 28))
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: leapDay, duration: WarrantyDuration(value: 4, unit: .year)), date(2028, 2, 29))
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: leapDay, duration: WarrantyDuration(value: 12, unit: .month)), date(2025, 2, 28))
    }

    /// 月末：1/31 ＋ 1か月は 2/28（うるう年は 2/29）、3/31 ＋ 6か月は 9/30
    func testMonthEnd() {
        let oneMonth = WarrantyDuration(value: 1, unit: .month)
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: date(2026, 1, 31), duration: oneMonth), date(2026, 2, 28))
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: date(2028, 1, 31), duration: oneMonth), date(2028, 2, 29))
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: date(2026, 3, 31), duration: WarrantyDuration(value: 6, unit: .month)), date(2026, 9, 30))
        XCTAssertEqual(WarrantyExpiration.expirationDate(purchaseDate: date(2026, 8, 31), duration: oneMonth), date(2026, 9, 30))
    }

    func testStatusSectionsAndNearest() {
        let now = TestDates.friday
        func days(_ value: Int) -> Date { LifeCalendar.calendar.date(byAdding: .day, value: value, to: LifeCalendar.startOfDay(now))! }
        let soon = WarrantyDocument(title: "冷蔵庫", warrantyExpiresAt: days(28), createdAt: now, updatedAt: now)
        let today = WarrantyDocument(title: "掃除機", warrantyExpiresAt: days(0), createdAt: now, updatedAt: now)
        let active = WarrantyDocument(title: "ソファ", warrantyExpiresAt: days(31), createdAt: now, updatedAt: now)
        let expired = WarrantyDocument(title: "電子レンジ", warrantyExpiresAt: days(-1), createdAt: now, updatedAt: now)
        let unknown = WarrantyDocument(title: "ルーター", createdAt: now, updatedAt: now)

        XCTAssertEqual(WarrantyExpiration.status(of: soon, now: now), .expiringSoon(days: 28))
        XCTAssertEqual(WarrantyExpiration.status(of: today, now: now), .expiringSoon(days: 0))
        XCTAssertEqual(WarrantyExpiration.remainingText(for: today, now: now), "今日まで")
        XCTAssertEqual(WarrantyExpiration.status(of: active, now: now), .active(days: 31))
        XCTAssertEqual(WarrantyExpiration.status(of: expired, now: now), .expired)
        XCTAssertEqual(WarrantyExpiration.status(of: unknown, now: now), .noExpiration)

        let groups = WarrantyListSection.group([expired, active, unknown, soon, today], now: now)
        XCTAssertEqual(groups.map(\.section), [.expiringSoon, .active, .expired, .noExpiration], "期限が近い・保証期間中・期限終了の順")
        XCTAssertEqual(groups[0].documents.map(\.title), ["掃除機", "冷蔵庫"])

        XCTAssertEqual(WarrantyExpiration.nearestExpiringSoon([active, soon, expired], now: now)?.title, "冷蔵庫")
        XCTAssertNil(WarrantyExpiration.nearestExpiringSoon([active, expired, unknown], now: now), "30日以内が無ければ今日画面に出さない")
    }

    func testSearchTargets() {
        let document = WarrantyDocument(
            title: "冷蔵庫", manufacturer: "見本電機", modelNumber: "AB-123", serialNumber: "SECRET-9",
            retailer: "駅前電器", physicalStorageLocation: "リビングの書類ケース", createdAt: TestDates.friday, updatedAt: TestDates.friday
        )
        for query in ["冷蔵", "見本", "ab-123", "駅前", "書類ケース"] {
            XCTAssertTrue(document.matches(query), query)
        }
        XCTAssertFalse(document.matches("SECRET"), "製造番号は検索の対象外（spec 3）")
    }
}

// MARK: - 保存（後方互換・再起動）

final class WarrantyPersistenceTests: WarrantyStorageTestCase {
    /// 以前の保存データ（保証書の項目が無い）から、保証書が空で読み込める
    func testOldSnapshotLoadsWithEmptyWarranties() throws {
        let first = LifeStore.persistent()
        let itemCount = first.items.count
        let fileURL = temporaryDirectory.appendingPathComponent(LifeStore.fileName)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        json.removeValue(forKey: "warranties")
        json.removeValue(forKey: "warrantyAttachments")
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL)

        let reloaded = LifeStore.persistent()
        XCTAssertEqual(reloaded.warranties, [])
        XCTAssertEqual(reloaded.warrantyAttachments, [])
        XCTAssertEqual(reloaded.items.count, itemCount, "ほかのデータはそのまま（初期化しない）")
    }

    /// 追加・編集・削除のあと、再起動しても残る（写真も）
    func testAddEditDeleteSurviveRelaunch() throws {
        let store = makePersistentStore()
        let photo = WarrantyTestImages.png()
        let staged = try store.warrantyStorage.stage(data: photo, contentType: .png, originalFileName: "photo.png")
        let saved = try store.saveWarranty(document(expiresAt: TestDates.make(2027, 10, 13)), adding: [staged], now: TestDates.friday)

        var relaunched = LifeStore.persistent()
        XCTAssertEqual(relaunched.warranties.map(\.title), ["冷蔵庫"])
        let attachment = try XCTUnwrap(relaunched.attachments(for: saved.id).first)
        XCTAssertEqual(try relaunched.warrantyStorage.data(for: attachment), photo, "写真が残っている（原本のまま）")

        var edited = try XCTUnwrap(relaunched.warranty(id: saved.id))
        edited.title = "冷蔵庫（キッチン）"
        edited.physicalStorageLocation = "書類ケース"
        try relaunched.saveWarranty(edited, now: TestDates.saturday)

        relaunched = LifeStore.persistent()
        let reloaded = try XCTUnwrap(relaunched.warranty(id: saved.id))
        XCTAssertEqual(reloaded.title, "冷蔵庫（キッチン）")
        XCTAssertEqual(reloaded.physicalStorageLocation, "書類ケース")
        XCTAssertEqual(reloaded.createdAt, saved.createdAt, "作成日時は変わらない")
        XCTAssertEqual(reloaded.attachmentIDs, [attachment.id])

        relaunched.deleteWarranty(id: saved.id)
        relaunched = LifeStore.persistent()
        XCTAssertTrue(relaunched.warranties.isEmpty)
        XCTAssertTrue(relaunched.warrantyAttachments.isEmpty)
        XCTAssertEqual(makeStorage().storedFileCount(), 0, "削除した保証書の写真が残らない")
    }

    /// 製品名だけで保存できる。製品名が空なら保存できない
    func testProductNameIsTheOnlyRequiredField() throws {
        let store = makePersistentStore()
        XCTAssertThrowsError(try store.saveWarranty(document("   "))) { error in
            XCTAssertEqual(error as? WarrantySaveError, .missingTitle)
        }
        try store.saveWarranty(document("エアコン"))
        XCTAssertEqual(store.warranties.map(\.title), ["エアコン"])
    }

    /// 所有範囲の初期値は「自分」。共有を選べば共有で保存される
    func testOwnershipDefaultsToPersonalAndCanChange() throws {
        XCTAssertEqual(WarrantyDocument(title: "a", createdAt: TestDates.friday, updatedAt: TestDates.friday).ownership, .personal)
        XCTAssertEqual(WarrantyDraft().ownership, .personal)

        let store = makePersistentStore()
        let viewModel = WarrantyEditorViewModel(repository: store, mode: .create, now: TestDates.friday)
        viewModel.draft.title = "洗濯機"
        viewModel.requestOwnership(.shared)
        XCTAssertEqual(viewModel.prompt, .confirmSharing, "共有の前に写真の枚数と項目名を確認する")
        XCTAssertEqual(viewModel.draft.ownership, .personal, "確認するまでは自分のまま")
        viewModel.confirmSharing()
        XCTAssertTrue(viewModel.save(now: TestDates.friday))

        let relaunched = LifeStore.persistent()
        XCTAssertEqual(relaunched.warranties.first?.ownership, .shared)
    }

    func testTooManyPhotosAreRejectedWithoutSavingAnything() throws {
        let store = makePersistentStore()
        let files = try (0..<11).map { index in
            try store.warrantyStorage.stage(data: WarrantyTestImages.png(UIColor(white: CGFloat(index) / 11, alpha: 1)), contentType: .png, originalFileName: "p.png")
        }
        XCTAssertThrowsError(try store.saveWarranty(document(), adding: files)) { error in
            XCTAssertEqual(error as? WarrantyAttachmentError, .tooManyAttachments)
        }
        XCTAssertTrue(store.warranties.isEmpty)
        XCTAssertEqual(store.warrantyStorage.storedFileCount(), 0)
    }
}

// MARK: - 写真の保存

final class WarrantyAttachmentStorageTests: WarrantyStorageTestCase {
    /// 再圧縮しない・ファイル名は UUID だけ・保存先は WarrantyDocuments/{documentID}/
    func testCommitKeepsOriginalBytesAndUsesUUIDFileNames() throws {
        let storage = makeStorage()
        let photo = WarrantyTestImages.png()
        let staged = try storage.stage(data: photo, contentType: .png, originalFileName: "冷蔵庫の保証書.png")
        let documentID = UUID()
        let attachments = try storage.commit([staged], documentID: documentID, now: TestDates.friday)

        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(try storage.data(for: attachment), photo, "受け取ったデータと同じ（再圧縮しない）")
        XCTAssertEqual(attachment.relativeFilePath, "WarrantyDocuments/\(documentID.uuidString)/\(attachment.id.uuidString).png")
        XCTAssertFalse(attachment.relativeFilePath.contains("冷蔵庫"), "ファイル名に製品名を使わない")
        XCTAssertEqual(attachment.sha256, WarrantyAttachmentStorage.sha256(photo))
        XCTAssertEqual(attachment.byteCount, Int64(photo.count))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path), "一時フォルダからは移動済み")

        let url = try XCTUnwrap(storage.url(for: attachment))
        let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
        try XCTSkipIf(protection == nil, "シミュレーターではファイル保護の状態を読めないため、実機で確認します")
        XCTAssertEqual(protection, .complete)
    }

    /// 保存の途中で失敗したら、孤立ファイルを残さない
    func testFailedCommitLeavesNoOrphanFiles() throws {
        let storage = makeStorage()
        let files = try (0..<3).map { index in
            try storage.stage(data: WarrantyTestImages.png(UIColor(white: CGFloat(index) / 3, alpha: 1)), contentType: .png, originalFileName: "p.png")
        }
        var moves = 0
        storage.moveItem = { source, destination in
            moves += 1
            if moves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        XCTAssertThrowsError(try storage.commit(files, documentID: UUID(), now: TestDates.friday)) { error in
            XCTAssertEqual(error as? WarrantyAttachmentError, .writeFailed)
        }
        XCTAssertEqual(storage.storedFileCount(), 0, "保存先に途中のファイルが残らない")
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }, "一時フォルダに戻っている（やり直せる）")

        storage.discard(files)
        XCTAssertFalse(files.contains { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    /// 保存に失敗したら、保証書のデータも変えない
    func testStoreRollsBackWhenPhotoSavingFails() throws {
        let store = makePersistentStore()
        let file = try store.warrantyStorage.stage(data: WarrantyTestImages.png(), contentType: .png, originalFileName: "p.png")
        store.warrantyStorage.moveItem = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try store.saveWarranty(document(), adding: [file]))
        XCTAssertTrue(store.warranties.isEmpty)
        XCTAssertTrue(store.warrantyAttachments.isEmpty)
        XCTAssertEqual(store.warrantyStorage.storedFileCount(), 0)
    }

    /// どの保証書からも参照されていない写真は、起動時の掃除で消える
    func testRemoveOrphans() throws {
        let storage = makeStorage()
        let kept = try storage.commit(
            [try storage.stage(data: WarrantyTestImages.png(.red), contentType: .png, originalFileName: "a.png")],
            documentID: UUID(), now: TestDates.friday
        )
        let orphanDocument = UUID()
        _ = try storage.commit(
            [try storage.stage(data: WarrantyTestImages.png(.blue), contentType: .png, originalFileName: "b.png")],
            documentID: orphanDocument, now: TestDates.friday
        )
        XCTAssertEqual(storage.storedFileCount(), 2)

        XCTAssertEqual(storage.removeOrphans(keeping: kept), 1)
        XCTAssertEqual(storage.storedFileCount(), 1)
        XCTAssertTrue(storage.fileExists(for: kept[0]))
        let orphanFolder = temporaryDirectory.appendingPathComponent("WarrantyDocuments/\(orphanDocument.uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFolder.path), "空のフォルダも消える")
    }

    /// 25MB を超える・HEIC/JPEG/PNG 以外は追加前に断る
    func testSizeAndTypeLimits() {
        XCTAssertNoThrow(try WarrantyAttachmentStorage.validate(byteCount: WarrantyAttachmentStorage.maxFileBytes, contentType: .heic))
        XCTAssertNoThrow(try WarrantyAttachmentStorage.validate(byteCount: 10, contentType: .jpeg))
        XCTAssertNoThrow(try WarrantyAttachmentStorage.validate(byteCount: 10, contentType: .png))
        XCTAssertThrowsError(try WarrantyAttachmentStorage.validate(byteCount: WarrantyAttachmentStorage.maxFileBytes + 1, contentType: .heic)) { error in
            XCTAssertEqual(error as? WarrantyAttachmentError, .tooLarge(byteCount: WarrantyAttachmentStorage.maxFileBytes + 1))
        }
        XCTAssertThrowsError(try WarrantyAttachmentStorage.validate(byteCount: 10, contentType: .pdf)) { error in
            XCTAssertEqual(error as? WarrantyAttachmentError, .unsupportedType, "PDF は第2段階")
        }
        XCTAssertThrowsError(try WarrantyAttachmentStorage.validate(byteCount: 10, contentType: .gif))
    }

    /// 同じ写真（SHA-256 が同じ）は確認を出す。確認してから追加できる
    func testDuplicatePhotoAsksBeforeAdding() throws {
        let store = makePersistentStore()
        let photo = WarrantyTestImages.png(.purple)
        let staged = try store.warrantyStorage.stage(data: photo, contentType: .png, originalFileName: "p.png")
        try store.saveWarranty(document("テレビ"), adding: [staged])

        let viewModel = WarrantyEditorViewModel(repository: store, mode: .create)
        viewModel.addPhoto(data: photo, contentType: .png, originalFileName: "same.png")
        guard case .duplicate(let id, let title) = viewModel.prompt else {
            return XCTFail("同じ写真の確認が出ていない")
        }
        XCTAssertEqual(title, "テレビ")
        XCTAssertTrue(viewModel.stagedFiles.isEmpty, "確認するまでは追加しない")
        viewModel.confirmDuplicate(id)
        XCTAssertEqual(viewModel.stagedFiles.count, 1)
        viewModel.cancel()
    }

    /// 撮影・選択のあとキャンセルしても、空の保証書を作らず、一時ファイルも残さない
    func testCancelCreatesNothingAndRemovesTemporaryFiles() throws {
        let store = makePersistentStore()
        let viewModel = WarrantyEditorViewModel(repository: store, mode: .create)
        viewModel.addPhoto(data: WarrantyTestImages.png(.green), contentType: .png, originalFileName: "p.png")
        let staged = try XCTUnwrap(viewModel.stagedFiles.first)
        viewModel.cancel()
        XCTAssertTrue(store.warranties.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertEqual(store.warrantyStorage.storedFileCount(), 0)
    }

    /// 写真を1枚消すと、ファイルも消える
    func testDeletingOnePhoto() throws {
        let store = makePersistentStore()
        let files = try [UIColor.red, .blue].map {
            try store.warrantyStorage.stage(data: WarrantyTestImages.png($0), contentType: .png, originalFileName: "p.png")
        }
        let saved = try store.saveWarranty(document(), adding: files)
        let first = try XCTUnwrap(store.attachments(for: saved.id).first)
        store.deleteWarrantyAttachment(id: first.id)
        XCTAssertEqual(store.attachments(for: saved.id).count, 1)
        XCTAssertEqual(store.warranty(id: saved.id)?.attachmentIDs.count, 1)
        XCTAssertFalse(store.warrantyStorage.fileExists(for: first))
        XCTAssertEqual(store.warrantyStorage.storedFileCount(), 1)
    }
}

// MARK: - Free / Premium / Premium 終了後

final class WarrantyAccessTests: WarrantyStorageTestCase {
    func testFreeCannotCreateAndPremiumCan() {
        let free = WarrantyAccess.resolve(isPremium: false, hasSavedDocuments: false)
        XCTAssertEqual(free, .locked)
        XCTAssertFalse(free.canCreate)
        XCTAssertFalse(free.canView)

        let premium = WarrantyAccess.resolve(isPremium: true, hasSavedDocuments: false)
        XCTAssertEqual(premium, .full)
        XCTAssertTrue(premium.canCreate && premium.canEdit && premium.canRecognizeText && premium.canScheduleReminders)
    }

    /// Premium 終了後：閲覧・書き出し・削除はできる。新規・編集・読み取り・新しい通知はできない
    func testAfterPremiumEndsDocumentsCanBeViewedExportedAndDeleted() throws {
        let store = makePersistentStore()
        let appState = AppState()
        appState.plan = .premium
        let staged = try store.warrantyStorage.stage(data: WarrantyTestImages.png(), contentType: .png, originalFileName: "p.png")
        let saved = try store.saveWarranty(document(expiresAt: TestDates.make(2026, 12, 1)), adding: [staged])

        appState.plan = .free
        let access = WarrantyAccess.resolve(isPremium: appState.isPremium, hasSavedDocuments: !store.warranties.isEmpty)
        XCTAssertEqual(access, .readOnly)
        XCTAssertTrue(access.canView && access.canExport && access.canDelete)
        XCTAssertFalse(access.canCreate || access.canEdit || access.canRecognizeText || access.canScheduleReminders)

        // データは消えていない（解約時に削除しない）
        XCTAssertEqual(store.warranties.count, 1)

        // 書き出し
        let exportRoot = temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        let urls = try WarrantyExporter.makeExport(
            document: saved, attachments: store.attachments(for: saved.id), storage: store.warrantyStorage,
            removingLocation: true, now: TestDates.friday, root: exportRoot
        )
        XCTAssertEqual(urls.count, 2, "保証書の情報と写真1枚")
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        WarrantyExporter.clearTemporaryFiles(root: exportRoot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportRoot.path), "書き出しの一時ファイルは消える")

        // 削除
        store.deleteWarranty(id: saved.id)
        XCTAssertTrue(store.warranties.isEmpty)
        XCTAssertEqual(store.warrantyStorage.storedFileCount(), 0)

        // 再加入すると同じデータから再開できる（データが残っていれば full に戻る）
        XCTAssertEqual(WarrantyAccess.resolve(isPremium: true, hasSavedDocuments: true), .full)
    }
}

// MARK: - 通知

final class FakeNotificationCenter: LifeNotificationCenter {
    var pending: Set<String>
    var added: [LifeNotificationRequest] = []
    var authorized: Bool?
    private(set) var didRequestAuthorization = false

    init(pending: Set<String> = [], authorized: Bool? = true) {
        self.pending = pending
        self.authorized = authorized
    }

    func pendingRequestIdentifiers() async -> [String] { Array(pending) }

    func add(_ request: LifeNotificationRequest, calendar: Calendar) async throws {
        pending.insert(request.identifier)
        added.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        pending.subtract(identifiers)
    }

    func isAuthorized() async -> Bool? { authorized }

    func requestAuthorization() async -> Bool {
        didRequestAuthorization = true
        authorized = true
        return true
    }
}

final class WarrantyNotificationTests: XCTestCase {
    private let now = TestDates.friday

    private func days(_ value: Int) -> Date {
        LifeCalendar.calendar.date(byAdding: .day, value: value, to: LifeCalendar.startOfDay(now))!
    }

    private func document(_ title: String, expiresInDays: Int?, offsets: Set<Int> = WarrantyDocument.defaultReminderOffsets) -> WarrantyDocument {
        WarrantyDocument(
            title: title,
            serialNumber: "SN-SECRET-001",
            warrantyExpiresAt: expiresInDays.map(days),
            expirationSource: .manual,
            physicalStorageLocation: "寝室の金庫",
            reminderOffsetsInDays: offsets,
            createdAt: now,
            updatedAt: now
        )
    }

    /// 初期値：30日前・7日前・当日の 9:00
    func testDefaultRemindersAtNine() {
        let requests = LifeNotificationPlanner.warrantyRequests(documents: [document("冷蔵庫", expiresInDays: 60)], now: now)
        XCTAssertEqual(requests.count, 3)
        let calendar = LifeCalendar.calendar
        XCTAssertEqual(requests.map(\.fireDate), [30, 7, 0].map { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: days(60 - $0))! })
        XCTAssertTrue(requests.allSatisfy { $0.identifier.hasPrefix("lifeos.warranty.") })
        XCTAssertEqual(requests.first?.body, "冷蔵庫の保証終了まであと30日です")
        XCTAssertEqual(requests.last?.body, "冷蔵庫の保証は今日までです")
    }

    /// 通知日が過去なら予約しない。終了日なし・終了済み・通知 OFF は予約しない
    func testPastAndDisabledRemindersAreNotScheduled() {
        let requests = LifeNotificationPlanner.warrantyRequests(documents: [document("冷蔵庫", expiresInDays: 10)], now: now)
        XCTAssertEqual(requests.map(\.body), ["冷蔵庫の保証終了まであと7日です", "冷蔵庫の保証は今日までです"], "30日前はもう過ぎている")

        // 当日でも 9:00 を過ぎていれば予約しない（いまは 9:10）
        XCTAssertTrue(LifeNotificationPlanner.warrantyRequests(documents: [document("今日まで", expiresInDays: 0)], now: now).isEmpty)

        let none = [
            document("終了日なし", expiresInDays: nil),
            document("終了済み", expiresInDays: -1),
            document("通知オフ", expiresInDays: 60, offsets: [])
        ]
        XCTAssertTrue(LifeNotificationPlanner.warrantyRequests(documents: none, now: now).isEmpty)
    }

    /// 製造番号・保管場所は通知本文に出さない
    func testBodyDoesNotContainSerialOrStorageLocation() {
        let requests = LifeNotificationPlanner.warrantyRequests(documents: [document("冷蔵庫", expiresInDays: 60)], now: now)
        for request in requests {
            XCTAssertFalse(request.body.contains("SN-SECRET-001"))
            XCTAssertFalse(request.body.contains("金庫"))
            XCTAssertFalse(request.title.contains("SN-SECRET-001") || request.title.contains("金庫"))
        }
    }

    /// 保証書は期限が近い6件 × 3通知 = 18件まで
    func testWarrantyBudgetIsSixDocuments() {
        let documents = (1...10).map { document("製品\($0)", expiresInDays: 40 + $0) }
        let planned = LifeNotificationService.plannedRequests(warranties: documents, isPremium: true, warrantyRemindersEnabled: true, now: now)
        XCTAssertEqual(planned.count, 18)
        let titles = Set(planned.map { $0.body.components(separatedBy: "の保証").first ?? "" })
        XCTAssertEqual(titles, Set((1...6).map { "製品\($0)" }), "期限が近い6件")
    }

    /// 既存の予定・タスクの通知を含めても、合計59件以下
    func testTotalWithExistingNotificationsStaysWithinLimit() {
        let warranty = LifeNotificationPlanner.warrantyRequests(
            documents: (1...10).map { document("製品\($0)", expiresInDays: 40 + $0) }, now: now
        )
        let events = (1...50).map { index in
            LifeNotificationRequest(identifier: "lifeos.event.\(index)", category: .event, title: "予定", body: "予定\(index)", fireDate: days(1).addingTimeInterval(Double(index) * 600))
        }
        let tasks = (1...3).map { index in
            LifeNotificationRequest(identifier: "lifeos.task.\(index)", category: .task, title: "やること", body: "未完了", fireDate: days(index))
        }
        let plan = LifeNotificationPlanner.plan(warranty: warranty, events: events, tasks: tasks)
        XCTAssertLessThanOrEqual(plan.count, 59)
        XCTAssertEqual(plan.count, 59)
        XCTAssertEqual(plan.filter { $0.category == .warranty }.count, 18)
        XCTAssertEqual(plan.filter { $0.category == .event }.count, 40)
        XCTAssertEqual(plan.filter { $0.category == .task }.count, 1)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count, "同じ通知を二重に予約しない")
    }

    /// Premium 終了後・通知設定 OFF では、保証書の通知を予約しない
    func testNoWarrantyRemindersWhenPremiumEndedOrDisabled() {
        let documents = [document("冷蔵庫", expiresInDays: 60)]
        XCTAssertTrue(LifeNotificationService.plannedRequests(warranties: documents, isPremium: false, warrantyRemindersEnabled: true, now: now).isEmpty)
        XCTAssertTrue(LifeNotificationService.plannedRequests(warranties: documents, isPremium: true, warrantyRemindersEnabled: false, now: now).isEmpty)
        XCTAssertEqual(LifeNotificationService.plannedRequests(warranties: documents, isPremium: true, warrantyRemindersEnabled: true, now: now).count, 3)
    }

    /// 予約し直すとき、アプリが管理する通知（lifeos.）だけを入れ替える。削除した保証書の通知は残らない
    func testResyncReplacesOnlyAppManagedRequests() async {
        let center = FakeNotificationCenter(pending: ["other.reminder", "lifeos.warranty.OLD.30"])
        let service = LifeNotificationService(center: center)
        let fridge = document("冷蔵庫", expiresInDays: 60)

        await service.resync(warranties: [fridge], isPremium: true, warrantyRemindersEnabled: true, now: now)
        XCTAssertTrue(center.pending.contains("other.reminder"), "ほかの通知は消さない")
        XCTAssertFalse(center.pending.contains("lifeos.warranty.OLD.30"), "古い予約は消す")
        XCTAssertEqual(center.pending.filter { $0.hasPrefix("lifeos.") }.count, 3)

        // 削除したら通知も残らない
        await service.resync(warranties: [], isPremium: true, warrantyRemindersEnabled: true, now: now)
        XCTAssertEqual(center.pending, ["other.reminder"])

        // Premium が終わったら、保証書の通知予約だけを消す
        await service.resync(warranties: [fridge], isPremium: true, warrantyRemindersEnabled: true, now: now)
        await service.resync(warranties: [fridge], isPremium: false, warrantyRemindersEnabled: true, now: now)
        XCTAssertEqual(center.pending, ["other.reminder"])
    }

    /// 通知が許可されていなければ予約しない。許可のお願いは未確認のときだけ
    func testNoSchedulingWithoutPermission() async {
        let denied = FakeNotificationCenter(authorized: false)
        await LifeNotificationService(center: denied).resync(warranties: [document("冷蔵庫", expiresInDays: 60)], isPremium: true, warrantyRemindersEnabled: true, now: now)
        XCTAssertTrue(denied.added.isEmpty)

        let unknown = FakeNotificationCenter(authorized: nil)
        let service = LifeNotificationService(center: unknown)
        await service.requestAuthorizationIfNeeded()
        XCTAssertTrue(unknown.didRequestAuthorization)

        let alreadyDenied = FakeNotificationCenter(authorized: false)
        await LifeNotificationService(center: alreadyDenied).requestAuthorizationIfNeeded()
        XCTAssertFalse(alreadyDenied.didRequestAuthorization, "拒否された人には何度もお願いしない")
    }
}

// MARK: - 読み取り候補

final class WarrantyExtractionTests: XCTestCase {
    private func lines(_ texts: [String], confidence: Float = 0.95) -> [WarrantyRecognizedLine] {
        texts.map { WarrantyRecognizedLine(text: $0, confidence: confidence) }
    }

    func testExtractsLabeledFieldsFromWarrantyCard() throws {
        let proposal = WarrantyFieldExtractor.extract(from: lines([
            "保証書",
            "品名 冷蔵庫",
            "メーカー パナソニック",
            "型番 NR-F507HPX",
            "製造番号 1234567",
            "お買上げ日 2026年10月13日",
            "保証期間 本体1年間",
            "販売店 ヨドバシカメラ梅田"
        ]))
        XCTAssertEqual(proposal.field(.title)?.value, "冷蔵庫")
        XCTAssertEqual(proposal.field(.manufacturer)?.value, "パナソニック")
        XCTAssertEqual(proposal.field(.modelNumber)?.value, "NR-F507HPX")
        XCTAssertEqual(proposal.field(.serialNumber)?.value, "1234567")
        XCTAssertEqual(proposal.field(.purchaseDate)?.value, "2026/10/13")
        XCTAssertEqual(proposal.field(.warrantyDuration)?.duration, WarrantyDuration(value: 1, unit: .year))
        XCTAssertEqual(proposal.field(.retailer)?.value, "ヨドバシカメラ梅田")
        XCTAssertNil(proposal.field(.warrantyExpiresAt))
        XCTAssertFalse(try XCTUnwrap(proposal.field(.title)).needsReview)
    }

    func testJapaneseEraFullWidthAndExpirationLine() {
        let proposal = WarrantyFieldExtractor.extract(from: lines([
            "お買い上げ日：令和8年10月13日",
            "型番　ＡＢ－１２３",
            "保証期限 2027.10.12"
        ]))
        XCTAssertEqual(proposal.field(.purchaseDate)?.value, "2026/10/13")
        XCTAssertEqual(proposal.field(.modelNumber)?.value, "AB-123")
        XCTAssertEqual(proposal.field(.warrantyExpiresAt)?.value, "2027/10/12")
        XCTAssertNil(proposal.field(.warrantyDuration), "日付の「2027」を保証期間と読み違えない")
    }

    /// 複数の候補・信頼度が低い・見出しの無い日付は「確認が必要」
    func testAmbiguousFieldsNeedReview() throws {
        let multiple = WarrantyFieldExtractor.extract(from: lines(["購入日 2026/10/13", "購入日 2026/10/20"]))
        let date = try XCTUnwrap(multiple.field(.purchaseDate))
        XCTAssertTrue(date.needsReview)
        XCTAssertEqual(date.alternatives, ["2026/10/20"])

        let blurry = WarrantyFieldExtractor.extract(from: [WarrantyRecognizedLine(text: "型番 AB-123", confidence: 0.3)])
        XCTAssertTrue(try XCTUnwrap(blurry.field(.modelNumber)).needsReview)

        let receipt = WarrantyFieldExtractor.extract(from: lines(["ヨドバシカメラ", "2026/10/13 12:34", "合計 ¥98,000"]))
        XCTAssertEqual(receipt.field(.retailer)?.value, "ヨドバシカメラ")
        XCTAssertEqual(receipt.field(.purchaseDate)?.value, "2026/10/13")
        XCTAssertTrue(try XCTUnwrap(receipt.field(.purchaseDate)).needsReview, "見出しの無い日付は確認が必要")
    }

    func testNothingFound() {
        XCTAssertTrue(WarrantyFieldExtractor.extract(from: lines(["ありがとうございました"])).isEmpty)
        XCTAssertTrue(WarrantyFieldExtractor.extract(from: []).isEmpty)
    }
}

// MARK: - 候補の反映（承認制）

final class WarrantyProposalApplyTests: XCTestCase {
    private let proposal = WarrantyFieldExtractor.extract(from: [
        WarrantyRecognizedLine(text: "品名 冷蔵庫"),
        WarrantyRecognizedLine(text: "型番 AB-123"),
        WarrantyRecognizedLine(text: "お買上げ日 2026年10月13日"),
        WarrantyRecognizedLine(text: "保証期間 1年")
    ])

    /// 「候補を反映」を押すまでは、入力欄にも保証書にも入らない
    func testProposalIsNotWrittenUntilApplied() {
        let store = LifeStore()
        let viewModel = WarrantyEditorViewModel(repository: store, mode: .create)
        viewModel.proposal = proposal
        XCTAssertEqual(viewModel.draft, WarrantyDraft(), "候補を出しただけでは入力欄は変わらない")
        XCTAssertTrue(store.warranties.isEmpty)

        viewModel.discardProposal()
        XCTAssertNil(viewModel.proposal)
        XCTAssertEqual(viewModel.draft, WarrantyDraft(), "反映しなかった候補は残らない")

        viewModel.proposal = proposal
        viewModel.applyProposal(proposal, selected: Set(WarrantyFieldKind.allCases))
        XCTAssertEqual(viewModel.draft.title, "冷蔵庫")
        XCTAssertEqual(viewModel.draft.modelNumber, "AB-123")
        XCTAssertTrue(store.warranties.isEmpty, "保存するまで保証書は作られない")
    }

    /// 入力済みの値は上書きしない。選ばなかった候補は入れない
    func testDoesNotOverwriteUserInputOrUnselectedFields() {
        var draft = WarrantyDraft()
        draft.title = "自分で入力した名前"
        let applied = draft.apply(proposal, selected: [.title, .purchaseDate, .warrantyDuration])
        XCTAssertEqual(draft.title, "自分で入力した名前")
        XCTAssertFalse(applied.contains(.title))
        XCTAssertEqual(draft.modelNumber, "", "選ばなかった項目は入れない")
        XCTAssertEqual(draft.purchaseDate, TestDates.make(2026, 10, 13))
        XCTAssertEqual(draft.expiration, TestDates.make(2027, 10, 13), "購入日＋保証期間で計算")
        XCTAssertEqual(draft.expirationSource, .calculated)
        XCTAssertEqual(draft.basisText, "購入日 2026/10/13 ＋ 1年")
    }

    /// 手入力だけで保存できる（読み取りに失敗しても）
    func testManualEntryWithoutPhotosOrRecognition() {
        let store = LifeStore()
        let viewModel = WarrantyEditorViewModel(repository: store, mode: .create)
        XCTAssertFalse(viewModel.canSave)
        viewModel.draft.title = "掃除機"
        XCTAssertTrue(viewModel.save(now: TestDates.friday))
        XCTAssertEqual(store.warranties.first?.title, "掃除機")
        XCTAssertEqual(store.warranties.first?.ownership, .personal)
        XCTAssertEqual(store.warranties.first?.reminderOffsetsInDays, [30, 7, 0])
    }
}

// MARK: - プライバシー

/// URLSession を通る通信を記録する（通信は止めない）
final class NetworkSpyProtocol: URLProtocol {
    static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        if let url = request.url { requestedURLs.append(url) }
        return false
    }
}

final class WarrantyPrivacyTests: WarrantyStorageTestCase {
    /// 登録・読み取り・閲覧・書き出し・通知予約で、外部へ通信しない
    func testNoNetworkAccessDuringWarrantyFlow() async throws {
        NetworkSpyProtocol.requestedURLs = []
        URLProtocol.registerClass(NetworkSpyProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkSpyProtocol.self) }

        let store = makePersistentStore()
        let image = WarrantyTestImages.text(["保証書", "型番 AB-123", "お買上げ日 2026/10/13"])

        // 読み取り（端末内の Vision）。シミュレーターで読めなくても、通信しないことを確かめる
        let recognized = (try? await WarrantyTextRecognizer.proposal(for: [image])) ?? WarrantyExtractionProposal(recognizedText: "", fields: [])
        _ = recognized

        // 登録・保存
        let staged = try store.warrantyStorage.stage(data: image, contentType: .png, originalFileName: "p.png")
        let saved = try store.saveWarranty(document(expiresAt: TestDates.make(2026, 12, 1)), adding: [staged])

        // 閲覧
        let attachment = try XCTUnwrap(store.attachments(for: saved.id).first)
        XCTAssertNotNil(WarrantyImageLoader.image(at: try XCTUnwrap(store.warrantyStorage.url(for: attachment)), maxPixelSize: 200))

        // 書き出し
        let exportRoot = temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        _ = try WarrantyExporter.makeExport(document: saved, attachments: [attachment], storage: store.warrantyStorage, removingLocation: true, root: exportRoot)

        // 通知予約
        let center = FakeNotificationCenter()
        await LifeNotificationService(center: center).resync(warranties: store.warranties, isPremium: true, warrantyRemindersEnabled: true, now: TestDates.friday)

        XCTAssertEqual(NetworkSpyProtocol.requestedURLs, [], "外部への通信は行わない")
    }

    /// 書き出しで位置情報を除ける（保存している原本は変えない）
    func testExportCanRemoveLocation() {
        let original = WarrantyTestImages.jpegWithLocation()
        XCTAssertTrue(WarrantyExporter.containsLocation(original))
        let cleaned = WarrantyExporter.dataWithoutLocation(original)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(WarrantyExporter.containsLocation(cleaned ?? original))
        XCTAssertTrue(WarrantyExporter.containsLocation(original), "原本はそのまま")
    }

    /// 書き出す文字に、保証の有効性の断定は入れない
    func testSummaryText() {
        let document = WarrantyDocument(
            title: "冷蔵庫", purchaseDate: TestDates.make(2026, 10, 13), warrantyDuration: WarrantyDuration(value: 1, unit: .year),
            warrantyExpiresAt: TestDates.make(2027, 10, 13), expirationSource: .calculated,
            physicalStorageLocation: "書類ケース", createdAt: TestDates.friday, updatedAt: TestDates.friday
        )
        let text = WarrantyExporter.summaryText(document: document, attachmentCount: 2, now: TestDates.friday)
        XCTAssertTrue(text.contains("保証終了日：2027/10/13（購入日 2026/10/13 ＋ 1年）"))
        XCTAssertTrue(text.contains("保管場所：書類ケース"))
        XCTAssertTrue(text.contains("写真：2枚"))
    }
}
