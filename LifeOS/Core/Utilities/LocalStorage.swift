import Foundation

/// アプリのデータを端末内（アプリ専用の保存領域）に JSON ファイルとして保存する。
/// 外部サービスには送らない。
/// 決定済み：データを端末に保存し、アプリを閉じても残す（2026-10-01）。
/// TODO: Firebase 接続時は、LifeStore / AppState の保存先をここから差し替える。
enum LocalStorage {
    /// テスト用：保存先を一時フォルダに差し替える（nil ならアプリ専用の保存領域）。
    /// はじめての設定（2026-10-09）で追加。実際の利用者データと衝突させないため。
    static var directoryOverride: URL?

    private static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LifeOS", isDirectory: true)
    }

    /// 保存ファイルがあるか（読めるかどうかは問わない）。既存の利用者かどうかの判定に使う
    static func exists(_ name: String) -> Bool {
        guard let url = fileURL(name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func fileURL(_ name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }

    static func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        // 形式が合わない（古い・壊れている）場合は nil を返し、Mock の初期データで始める
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<Value: Encodable>(_ value: Value, to name: String) {
        guard let directory, let url = fileURL(name) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // 保存に失敗しても画面上のデータはそのまま使えるため、処理は続ける。
        }
    }
}
