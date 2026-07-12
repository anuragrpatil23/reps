import LocalAuthentication

/// Gate for progress photos. Uses Face ID / Touch ID and falls back to the
/// device passcode, so it still works on devices without biometrics enrolled
/// (and in the Simulator via Features → Face ID → Matching Face).
enum PhotoAuth {
    static func authenticate(reason: String = "View your progress photos") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        // .deviceOwnerAuthentication = biometrics with automatic passcode fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: reason)
        } catch {
            return false   // user cancelled or auth failed → stay locked
        }
    }
}
