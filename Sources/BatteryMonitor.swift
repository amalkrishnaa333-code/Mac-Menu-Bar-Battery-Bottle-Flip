import Foundation
import IOKit.ps

class BatteryMonitor {
    static let shared = BatteryMonitor()
    var onChange: ((Double) -> Void)?
    private var timer: Timer?

    func getBatteryLevel() -> Double {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)
                    .takeUnretainedValue() as? [String: Any] else { continue }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                return Double(current) / Double(max)
            }
        }
        return 1.0 // desktop Mac — show full bottle
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.onChange?(self.getBatteryLevel())
        }
    }
}
