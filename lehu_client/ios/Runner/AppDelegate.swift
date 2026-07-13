import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingImageSaveResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "cn.edu.shu.lehu_client/image_saver",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      if call.method == "saveImage" {
        self?.saveImage(call: call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterMethodChannel(
      name: "cn.edu.shu.lehu_client/emoji_recents",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "getEmojiRecents":
        result(UserDefaults.standard.stringArray(forKey: "emoji_recents") ?? [])
      case "setEmojiRecents":
        let args = call.arguments as? [String: Any]
        let shortcodes = args?["shortcodes"] as? [String] ?? []
        UserDefaults.standard.set(shortcodes, forKey: "emoji_recents")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func saveImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingImageSaveResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "Image saver is already running",
          details: nil
        )
      )
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let typedData = args["bytes"] as? FlutterStandardTypedData,
      let image = UIImage(data: typedData.data)
    else {
      result(
        FlutterError(
          code: "invalid_image",
          message: "Cannot decode image bytes",
          details: nil
        )
      )
      return
    }
    pendingImageSaveResult = result
    UIImageWriteToSavedPhotosAlbum(
      image,
      self,
      #selector(image(_:didFinishSavingWithError:contextInfo:)),
      nil
    )
  }

  @objc private func image(
    _ image: UIImage,
    didFinishSavingWithError error: Error?,
    contextInfo: UnsafeRawPointer
  ) {
    guard let result = pendingImageSaveResult else {
      return
    }
    pendingImageSaveResult = nil
    if let error {
      result(
        FlutterError(
          code: "save_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
      return
    }
    result(true)
  }
}
