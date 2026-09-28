import Foundation
import Observation

@Observable
final class ProfileViewModel {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var name: String { appState.profile.name }
    var groupName: String { appState.profile.groupName }
    var members: [Member] { appState.profile.members }
    var memberCountText: String { "\(members.count)人" }
    var planLabel: String { appState.plan.label }
}
