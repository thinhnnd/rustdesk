import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var rawOrientationToken: Int32 = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    do {
      // Mix remote audio with other apps while still respecting silent mode.
      try AVAudioSession.sharedInstance().setCategory(.ambient)
    } catch {
      NSLog("Failed to configure audio mixing: %@", error.localizedDescription)
    }
    dummyMethodToEnforceBundling()
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupHardwareOrientationSync()
    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    syncSceneOrientationWithHardware()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.syncSceneOrientationWithHardware()
    }
  }

  private func setupHardwareOrientationSync() {
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDeviceOrientationChanged),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )

    notify_register_dispatch(
      "com.apple.backboardd.rawOrientation",
      &rawOrientationToken,
      DispatchQueue.main
    ) { [weak self] _ in
      self?.syncSceneOrientationWithHardware()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.syncSceneOrientationWithHardware()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      self?.syncSceneOrientationWithHardware()
    }
  }

  @objc private func handleDeviceOrientationChanged() {
    syncSceneOrientationWithHardware()
  }

  private func syncSceneOrientationWithHardware() {
    var rawState: UInt64 = 0
    if rawOrientationToken != 0 {
      notify_get_state(rawOrientationToken, &rawState)
    } else {
      var tempToken: Int32 = 0
      if notify_register_check("com.apple.backboardd.rawOrientation", &tempToken) == NOTIFY_STATUS_OK {
        notify_get_state(tempToken, &rawState)
        notify_cancel(tempToken)
      }
    }

    var targetMask: UIInterfaceOrientationMask?
    // backboardd rawOrientation values:
    // 1 = portrait, 2 = portraitUpsideDown, 3 = device landscapeLeft, 4 = device landscapeRight
    switch rawState {
    case 1:
      targetMask = .portrait
    case 2:
      targetMask = .portraitUpsideDown
    case 3:
      targetMask = .landscapeRight
    case 4:
      targetMask = .landscapeLeft
    default:
      switch UIDevice.current.orientation {
      case .portrait:
        targetMask = .portrait
      case .portraitUpsideDown:
        targetMask = .portraitUpsideDown
      case .landscapeLeft:
        targetMask = .landscapeRight
      case .landscapeRight:
        targetMask = .landscapeLeft
      default:
        break
      }
    }

    guard let mask = targetMask else { return }
    if #available(iOS 16.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        if let windowScene = scene as? UIWindowScene {
          windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            NSLog("Orientation sync error: %@", error.localizedDescription)
          }
          for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
          }
        }
      }
    }
  }

  @discardableResult
  public func dummyMethodToEnforceBundling() -> Int64 {
    let v1 = dummy_method_to_enforce_bundling()
    let v2 = Int64(Int(bitPattern: session_get_rgba(nil, 0)))
    if v1 == 0x7fffffff_ffffffff && v2 == 0x7fffffff_ffffffff {
      NSLog("FFI bundle ref: %lld %lld", v1, v2)
    }
    return v1 ^ v2
  }
}

