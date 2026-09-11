import Foundation
import IOKit.hid

/// Reads the MacBook lid angle from the internal HID sensor
/// (usage page 0x20 "Sensor", usage 0x8A). Degrees, 0 = closed.
final class LidAngleSensor {
    /// The manager has to outlive init: releasing it invalidates its devices.
    private let manager: IOHIDManager
    private let device: IOHIDDevice

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Matching on the usage keys misses this service, so enumerate and filter.
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first(where: {
                  LidAngleSensor.property($0, kIOHIDPrimaryUsagePageKey) == 0x20
                      && LidAngleSensor.property($0, kIOHIDPrimaryUsageKey) == 0x8A
              }),
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        else { return nil }
        self.device = device
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? -1
    }

    /// Current lid angle, or nil when the feature report cannot be read.
    func read() -> Double? {
        var buffer = [UInt8](repeating: 0, count: 8)
        var length = buffer.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buffer, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        return Double(UInt16(buffer[1]) | (UInt16(buffer[2]) << 8))
    }
}
