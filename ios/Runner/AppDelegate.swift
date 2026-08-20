import Flutter
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingImageSaveResult: FlutterResult?
  private var pendingImagePickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterMethodChannel(
      name: "work.shuyo.app/image_saver",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      if call.method == "saveImage" {
        self?.saveImage(call: call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterMethodChannel(
      name: "work.shuyo.app/emoji_recents",
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
    FlutterMethodChannel(
      name: "work.shuyo.app/image_picker",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { [weak self] call, result in
      if call.method == "pickImage" {
        self?.pickImage(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickImage(result: @escaping FlutterResult) {
    guard pendingImagePickerResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "Image picker is already open",
          details: nil
        )
      )
      return
    }
    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "picker_unavailable",
          message: "Cannot find a view controller to present the image picker",
          details: nil
        )
      )
      return
    }

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    pendingImagePickerResult = result
    presenter.present(picker, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
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

extension AppDelegate: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard let result = pendingImagePickerResult else {
      picker.dismiss(animated: true)
      return
    }
    pendingImagePickerResult = nil
    picker.dismiss(animated: true)

    guard let provider = results.first?.itemProvider else {
      result(nil)
      return
    }
    let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.image.identifier
    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "read_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }
        guard let data, !data.isEmpty else {
          result(nil)
          return
        }
        let type = UTType(typeIdentifier)
        let mimeType = type?.preferredMIMEType ?? "image/jpeg"
        let extensionName = type?.preferredFilenameExtension ?? "jpg"
        result([
          "bytes": FlutterStandardTypedData(bytes: data),
          "filename": "lehu_\(Int(Date().timeIntervalSince1970)).\(extensionName)",
          "mimeType": mimeType
        ])
      }
    }
  }
}
