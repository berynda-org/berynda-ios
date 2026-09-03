import BeryndaCore
import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var state: SessionState = .anonymous
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var registrationEmail: String?
    @Published var passwordResetEmail: String?

    private let session: SessionController
    private let authentication: any AuthenticationServing
    private let repository: any AccountRepository
    private let localPositions: LocalReadingPositionStore
    private var didRestore = false

    init(
        session: SessionController,
        authentication: any AuthenticationServing,
        repository: any AccountRepository,
        localPositions: LocalReadingPositionStore
    ) {
        self.session = session
        self.authentication = authentication
        self.repository = repository
        self.localPositions = localPositions
    }

    func restore() async {
        guard !didRestore else { return }
        didRestore = true
        state = await session.state()
        guard state == .authenticated else { return }
        await loadProfile()
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform {
            let user = try await session.signIn(email: email, password: password)
            profile = user
            state = .authenticated
            registrationEmail = nil
        }
    }

    func register(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            let result = try await authentication.register(
                email: email,
                password: password,
                displayName: displayName
            )
            registrationEmail = result.requiresEmailConfirmation ? result.email : nil
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        await perform {
            try await authentication.requestPasswordReset(email: email)
            passwordResetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func loadProfile() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            profile = try await repository.profile()
            state = .authenticated
        } catch {
            let current = await session.state()
            state = current
            if current != .authenticated { profile = nil }
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(_ update: ProfileUpdate) async -> Bool {
        await perform {
            profile = try await repository.updateProfile(update)
            state = .authenticated
            if update.privacySettings?["reading_history_enabled"] == false {
                await localPositions.clearAll()
            }
        }
    }

    func signOut() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        profile = nil
        state = .anonymous
        await localPositions.clearAll()
    }

    private func perform(_ operation: () async throws -> Void) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            state = await session.state()
            return false
        }
    }
}
