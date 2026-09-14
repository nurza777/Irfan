import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Канал для передачи токена APNs в Dart. Имя должно совпадать с тем,
  /// что слушает `lib/services/push_service.dart`.
  private static let channelName = "kg.irfan.irfan/push"

  /// Токен может прийти от системы РАНЬШЕ, чем Flutter успеет подписаться
  /// на канал. Поэтому придерживаем последний и отдаём, как только Dart
  /// спросит или как только канал появится.
  private var pendingToken: String?
  private var channel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Показ локальных уведомлений (напоминания о намазе), в т.ч. на переднем плане.
    if #available(iOS 10.0, *) {
      // Приведение БЕЗУСЛОВНОЕ. FlutterAppDelegate соответствует протоколу
      // через FlutterAppLifeCycleProvider, и если это когда-нибудь
      // изменится, сборка сломается здесь же. Условное `as?` вместо этого
      // молча подставило бы nil и оставило уведомления без делегата.
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Регистрация плагинов в ИЗОЛЯТЕ ДЕЙСТВИЙ — том, что просыпается по
    // нажатию «Да» или «Нет» в уведомлении при закрытом приложении.
    //
    // Без этой строки изолят поднимался, обработчик вызывался, но плагинов
    // в нём не было — а значит не было и SharedPreferences. Отметка намаза
    // писать ей было некуда, и ответ из уведомления не доходил до трекера:
    // человек нажимал кнопку, и ничего не происходило.
    //
    // Ошибки при этом не видно ниоткуда: изолят живёт секунды и умирает
    // молча. Требование описано в примере самого плагина.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Messenger берём через регистратор плагина: у моста явного движка
    // прямого доступа к нему нет, а регистратор — штатный способ.
    guard let registrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "IrfanPush") else { return }
    let ch = FlutterMethodChannel(name: AppDelegate.channelName,
                                  binaryMessenger: registrar.messenger())
    channel = ch
    ch.setMethodCallHandler { [weak self] (call: FlutterMethodCall,
                                           result: @escaping FlutterResult) in
      switch call.method {
      case "register":
        // Подписку на APNs запускает Dart — и только после того, как человек
        // разрешил уведомления. Регистрироваться раньше бессмысленно:
        // токен будет, а показать по нему нечего.
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      case "pendingToken":
        result(self?.pendingToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    if let t = pendingToken {
      ch.invokeMethod("token", arguments: t)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingToken = token
    channel?.invokeMethod("token", arguments: token)
    super.application(application,
                      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // Обычное дело в симуляторе и без настроенного профиля — не падаем.
    NSLog("push: не удалось зарегистрироваться в APNs: \(error.localizedDescription)")
    super.application(application,
                      didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
