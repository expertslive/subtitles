import Foundation
import IOKit.pwr_mgt

final class SleepPreventer {
    private var displayAssertionID = IOPMAssertionID(0)
    private var systemAssertionID = IOPMAssertionID(0)

    var isEnabled: Bool {
        displayAssertionID != 0 || systemAssertionID != 0
    }

    func enable(reason: String) throws {
        guard !isEnabled else {
            return
        }

        do {
            try createAssertion(
                type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                reason: reason,
                assertionID: &displayAssertionID
            )
            try createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                reason: reason,
                assertionID: &systemAssertionID
            )
        } catch {
            disable()
            throw error
        }
    }

    func disable() {
        releaseAssertion(&displayAssertionID)
        releaseAssertion(&systemAssertionID)
    }

    deinit {
        disable()
    }

    private func createAssertion(
        type: CFString,
        reason: String,
        assertionID: inout IOPMAssertionID
    ) throws {
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            assertionID = 0
            throw SleepPreventerError.assertionFailed(result)
        }
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}

enum SleepPreventerError: LocalizedError {
    case assertionFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .assertionFailed(let code):
            "Could not prevent system sleep (IOKit \(code))."
        }
    }
}
