import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "com.patentego.app.network-monitor")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    pathMonitor.start(queue: pathMonitorQueue)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.patentego.app/download_preflight",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getDownloadEnvironment" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let self else {
          result(["connectionType": "unknown"])
          return
        }
        result([
          "connectionType": self.currentConnectionType(),
          "availableStorageBytes": self.availableStorageBytes() as Any,
        ])
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func currentConnectionType() -> String {
    let path = pathMonitor.currentPath
    guard path.status == .satisfied else { return "offline" }
    if path.usesInterfaceType(.wifi) { return "wifi" }
    if path.usesInterfaceType(.wiredEthernet) { return "ethernet" }
    if path.usesInterfaceType(.cellular) { return "cellular" }
    return "unknown"
  }

  private func availableStorageBytes() -> Int64? {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let keys: Set<URLResourceKey> = [
      .volumeAvailableCapacityForImportantUsageKey,
      .volumeAvailableCapacityKey,
    ]
    guard let values = try? home.resourceValues(forKeys: keys) else { return nil }
    if let capacity = values.volumeAvailableCapacityForImportantUsage {
      return capacity
    }
    if let capacity = values.volumeAvailableCapacity {
      return Int64(capacity)
    }
    return nil
  }
}
