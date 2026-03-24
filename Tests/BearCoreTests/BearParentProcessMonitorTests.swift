import BearCore
import Testing

@Test
func parentMonitorReturnsWhenParentPIDChanges() async {
    let parentPID = SequenceProbe(values: [200, 200, 1])

    await BearParentProcessMonitor.waitForParentExit(
        originalParentPID: 200,
        pollInterval: .zero,
        currentParentPID: { parentPID.next() },
        isProcessAlive: { _ in true },
        sleep: { _ in }
    )

    #expect(parentPID.readCount == 3)
}

@Test
func parentMonitorReturnsWhenOriginalParentDisappears() async {
    let processState = SequenceProbe(values: [1, 0])

    await BearParentProcessMonitor.waitForParentExit(
        originalParentPID: 200,
        pollInterval: .zero,
        currentParentPID: { 200 },
        isProcessAlive: { _ in processState.next() == 1 },
        sleep: { _ in }
    )

    #expect(processState.readCount == 2)
}

@Test
func processExistsRejectsInvalidPID() {
    #expect(BearParentProcessMonitor.processExists(pid: 0) == false)
    #expect(BearParentProcessMonitor.processExists(pid: -1) == false)
}

private final class SequenceProbe: @unchecked Sendable {
    private var values: [Int32]
    private(set) var readCount = 0

    init(values: [Int32]) {
        self.values = values
    }

    func next() -> Int32 {
        readCount += 1
        if values.count > 1 {
            return values.removeFirst()
        }
        return values[0]
    }
}
