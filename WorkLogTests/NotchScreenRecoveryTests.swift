import Testing
@testable import WorkLog

@MainActor
struct NotchScreenRecoveryTests {
    @Test func unavailableScreenKeepsMonitoring() {
        var recoveryCount = 0
        let recovery = NotchScreenRecovery(isScreenAvailable: { false }) {
            recoveryCount += 1
        }

        recovery.start()
        recovery.checkAvailability()
        recovery.checkAvailability()

        #expect(recovery.isMonitoring)
        #expect(recoveryCount == 0)
        recovery.stop()
    }

    @Test func returningScreenStopsMonitoringBeforeRecovery() {
        var isAvailable = false
        var recoveryCount = 0
        weak var observedRecovery: NotchScreenRecovery?
        let recovery = NotchScreenRecovery(isScreenAvailable: { isAvailable }) {
            #expect(observedRecovery?.isMonitoring == false)
            recoveryCount += 1
        }
        observedRecovery = recovery

        recovery.start()
        recovery.checkAvailability()
        #expect(recoveryCount == 0)

        isAvailable = true
        recovery.checkAvailability()
        recovery.checkAvailability()

        #expect(!recovery.isMonitoring)
        #expect(recoveryCount == 1)
    }

    @Test func stoppedMonitoringIgnoresLaterAvailability() {
        var isAvailable = false
        var recoveryCount = 0
        let recovery = NotchScreenRecovery(isScreenAvailable: { isAvailable }) {
            recoveryCount += 1
        }

        recovery.start()
        recovery.stop()
        isAvailable = true
        recovery.checkAvailability()

        #expect(!recovery.isMonitoring)
        #expect(recoveryCount == 0)
    }

    @Test func repeatedStartProducesOneRecovery() {
        var recoveryCount = 0
        let recovery = NotchScreenRecovery(isScreenAvailable: { true }) {
            recoveryCount += 1
        }

        recovery.start()
        recovery.start()
        recovery.checkAvailability()
        recovery.checkAvailability()

        #expect(!recovery.isMonitoring)
        #expect(recoveryCount == 1)
    }

    @Test func monitoringTaskDoesNotRetainRecovery() {
        var recovery: NotchScreenRecovery? = NotchScreenRecovery(isScreenAvailable: { false }, onRecovery: {})
        weak let weakRecovery = recovery
        recovery?.start()

        #expect(recovery?.isMonitoring == true)
        recovery = nil

        #expect(weakRecovery == nil)
    }
}
