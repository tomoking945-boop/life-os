import Foundation
import Observation

@Observable
final class ProfileViewModel {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var name: String { appState.profile.name }
    var planLabel: String { appState.plan.label }
}
