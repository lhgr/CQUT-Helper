import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for context in connectionOptions.urlContexts {
      WidgetBridge.shared.receive(context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = URLContexts.filter { !WidgetBridge.shared.receive($0.url) }
    if !remaining.isEmpty { super.scene(scene, openURLContexts: Set(remaining)) }
  }
}
