import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MobileBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "xin.dart.deer/mobile",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "acquireMulticast", "releaseMulticast":
        // iOS has no multicast lock; the multicast entitlement is used instead.
        result(nil)
      case "getClipboardImage":
        if let image = UIPasteboard.general.image,
           let data = image.pngData() {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
      case "deviceLabel":
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        result(name.isEmpty ? "iPhone" : name)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
