import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@MainActor @Observable final class AppLockController {
    private let key = "appLockEnabled"
    var isLocked: Bool
    var errorMessage: String?
    var isAuthenticating = false
    private(set) var biometryDescription = "Face ID or passcode"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: "appLockEnabled")
        updateBiometryDescription()
    }

    func lockIfNeeded() {
        guard isEnabled else { isLocked = false; return }
        isLocked = true
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        if !enabled {
            // Turning the lock off still asks for the device owner, so someone
            // holding an unlocked phone cannot quietly disable protection.
            guard await authenticate(reason: "Turn off the Daymark app lock") else { return false }
            isEnabled = false
            isLocked = false
            return true
        }
        guard await authenticate(reason: "Protect Daymark with Face ID or your passcode") else { return false }
        isEnabled = true
        isLocked = false
        return true
    }

    /// Called by the lock screen. If the device has no passcode or biometrics,
    /// the app stays usable rather than trapping the owner outside their data.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        guard isEnabled else { isLocked = false; return }
        guard await authenticate(reason: "Unlock Daymark") else { return }
        isLocked = false
        errorMessage = nil
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            biometryDescription = "Device authentication"
            if isLocked {
                // Do not lock a user out when authentication is unavailable.
                isLocked = false
                errorMessage = "Device authentication is unavailable, so Daymark stayed unlocked. You can turn the lock off in Settings."
            } else {
                errorMessage = "Set a device passcode or enroll Face ID to use the app lock."
            }
            return false
        }
        switch context.biometryType {
        case .faceID: biometryDescription = "Face ID"
        case .touchID: biometryDescription = "Touch ID"
        case .opticID: biometryDescription = "Optic ID"
        default: biometryDescription = "Device passcode"
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success { errorMessage = nil }
            return success
        } catch {
            if (error as NSError).code != LAError.userCancel.rawValue {
                errorMessage = "Daymark could not verify your identity. Try again or use your device passcode."
            }
            return false
        }
    }

    private func updateBiometryDescription() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            switch context.biometryType {
            case .faceID: biometryDescription = "Face ID"
            case .touchID: biometryDescription = "Touch ID"
            case .opticID: biometryDescription = "Optic ID"
            default: biometryDescription = "Device passcode"
            }
        }
    }
}

struct AppLockView: View {
    @Environment(AppLockController.self) private var lock
    @State private var attempted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.accent.opacity(0.22), Palette.background, Palette.color("mint").opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Palette.surface)
                        .frame(width: 96, height: 96)
                        .shadow(color: Palette.accent.opacity(0.16), radius: 24, y: 10)
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Palette.color("amber"), Palette.accent)
                }
                VStack(spacing: 7) {
                    Text("Daymark is private").font(.title2.weight(.bold))
                    Text("Unlock to return to your journal, habits, and plans.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button {
                    Task { await lock.unlock() }
                } label: {
                    HStack(spacing: 8) {
                        if lock.isAuthenticating { ProgressView().tint(.white) }
                        else { Image(systemName: "faceid") }
                        Text(lock.isAuthenticating ? "Checking…" : "Unlock with \(lock.biometryDescription)")
                    }.font(.headline).frame(maxWidth: 300).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(lock.isAuthenticating)
                if let error = lock.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                Text("Your data stays on this device.").font(.caption2).foregroundStyle(.tertiary)
            }.padding(28)
        }
        .task {
            guard !attempted else { return }
            attempted = true
            await lock.unlock()
        }
    }
}
