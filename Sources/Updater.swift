import Combine
import Foundation
import Sparkle
import SwiftUI

/// Wraps Sparkle 2's SPUStandardUpdaterController for checking updates.
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    let controller: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    @Published var canCheckForUpdates: Bool = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
