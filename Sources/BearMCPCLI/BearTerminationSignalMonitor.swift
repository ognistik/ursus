import Darwin
import Dispatch
import Foundation

enum BearTerminationSignalMonitor {
    static func waitForTerminationSignal() async -> Int32 {
        await withCheckedContinuation { continuation in
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)

            let queue = DispatchQueue(label: "ursus.signal-monitor")
            var resumed = false
            var sources: [DispatchSourceSignal] = []

            func resume(with signalValue: Int32) {
                guard !resumed else {
                    return
                }

                resumed = true
                for source in sources {
                    source.cancel()
                }
                continuation.resume(returning: signalValue)
            }

            let supportedSignals: [Int32] = [SIGINT, SIGTERM]

            for signalValue in supportedSignals {
                let source = DispatchSource.makeSignalSource(signal: signalValue, queue: queue)
                source.setEventHandler {
                    resume(with: signalValue)
                }
                source.resume()
                sources.append(source)
            }
        }
    }
}
