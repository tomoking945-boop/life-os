import Foundation

#if canImport(FirebaseFunctions)
import FirebaseFunctions

/// わが家のサーバー（Cloud Functions の Callable）を呼ぶ実装（docs/FIREBASE_INVITE_JOIN_MEMBERSHIP.md）
///
/// - Firebase の SDK が、サインインの情報と App Check のトークンを自動で付ける（サーバーは両方を必須にしている）
/// - サーバーのエラーは、決まった理由（details.reason）だけを使って HouseholdFailure に分ける。生のエラー文は使わない・出さない
/// - 送るのは、わが家の名前・共有する種類・招待のトークン（招待のリンクの中にあったもの）だけ
final class FirebaseHouseholdBackend: HouseholdBackend {
    /// Cloud Functions の地域（サーバーの setGlobalOptions と同じ）
    static let region = "asia-northeast1"

    private var functions: Functions { Functions.functions(region: Self.region) }

    func fetchMyHousehold() async throws -> HouseholdSummary? {
        let result = try await call("getMyHousehold", [:])
        guard let dictionary = result as? [String: Any] else { throw HouseholdFailure.other }
        if dictionary["household"] == nil || dictionary["household"] is NSNull { return nil }
        guard let summary = HouseholdSummary(payload: dictionary["household"]) else { throw HouseholdFailure.other }
        return summary
    }

    func createHousehold(name: String, kinds: [SharedSpaceKind]) async throws -> HouseholdSummary {
        let result = try await call("createHousehold", ["name": name, "sharedKinds": kinds.map(\.rawValue)])
        guard let dictionary = result as? [String: Any],
              let summary = HouseholdSummary(payload: dictionary["household"]) else { throw HouseholdFailure.other }
        return summary
    }

    func createInvite() async throws -> CreatedInvite {
        let result = try await call("createInvite", [:])
        guard let invite = CreatedInvite(payload: result) else { throw HouseholdFailure.other }
        return invite
    }

    func revokeInvite() async throws {
        _ = try await call("revokeInvite", [:])
    }

    func fetchInvitePreview(token: String) async throws -> InvitePreview {
        let result = try await call("getInvitePreview", ["token": token])
        guard let dictionary = result as? [String: Any],
              let preview = InvitePreview(payload: dictionary["preview"]) else { throw HouseholdFailure.other }
        return preview
    }

    func acceptInvite(token: String) async throws -> HouseholdSummary {
        let result = try await call("acceptInvite", ["token": token])
        guard let dictionary = result as? [String: Any],
              let summary = HouseholdSummary(payload: dictionary["household"]) else { throw HouseholdFailure.other }
        return summary
    }

    func updateHousehold(name: String?, syncKinds: [SharedSpaceKind]?) async throws -> HouseholdSummary {
        var data: [String: Any] = [:]
        if let name { data["name"] = name }
        if let syncKinds { data["syncKinds"] = syncKinds.map(\.rawValue) }
        let result = try await call("updateHousehold", data)
        guard let dictionary = result as? [String: Any],
              let summary = HouseholdSummary(payload: dictionary["household"]) else { throw HouseholdFailure.other }
        return summary
    }

    func deleteHousehold() async throws {
        _ = try await call("deleteHousehold", [:])
    }

    func leaveHousehold() async throws {
        _ = try await call("leaveHousehold", [:])
    }

    private func call(_ name: String, _ data: [String: Any]) async throws -> Any {
        do {
            return try await functions.httpsCallable(name).call(data).data
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Cloud Functions のエラーを、画面で説明できる種類に分ける（エラーの中身は画面に出さない）
    static func failure(from error: Error) -> HouseholdFailure {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        guard nsError.domain == FunctionsErrorDomain else { return .other }
        let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        if let reason = details?["reason"] as? String, reason != "internal" {
            return HouseholdFailure(reason: reason)
        }
        switch FunctionsErrorCode(rawValue: nsError.code) ?? .unknown {
        case .unavailable, .deadlineExceeded:
            return .network
        case .notFound, .unimplemented, .unauthenticated, .permissionDenied:
            // Function がまだ公開されていない・App Check やサインインの確認が通らない
            return .notConnected
        default:
            return .other
        }
    }
}
#endif
