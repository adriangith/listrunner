import Foundation
import Capacitor
import WebKit

@objc(StoreSessionPlugin)
public class StoreSessionPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "StoreSessionPlugin"
    public let jsName = "StoreSession"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "closeSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "search", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setStore", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateOverlay", returnType: CAPPluginReturnPromise)
    ]

    var storeSessionVC: StoreSessionViewController?

    @objc func openSession(_ call: CAPPluginCall) {
        guard let storeId = call.getString("storeId"),
              let urlString = call.getString("url"),
              let url = URL(string: urlString) else {
            call.reject("Invalid storeId or url")
            return
        }

        DispatchQueue.main.async {
            if self.storeSessionVC == nil {
                self.storeSessionVC = StoreSessionViewController()
                self.storeSessionVC?.plugin = self
            }
            self.storeSessionVC?.loadStore(url: url, storeId: storeId)

            if let window = UIApplication.shared.keyWindow,
               let rootVC = window.rootViewController {
                rootVC.present(self.storeSessionVC!, animated: true) {
                    call.resolve()
                }
            } else {
                call.reject("Could not present store session")
            }
        }
    }

    @objc func closeSession(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.storeSessionVC?.dismiss(animated: true) {
                call.resolve()
            }
        }
    }

    @objc func search(_ call: CAPPluginCall) {
        guard let query = call.getString("query") else {
            call.reject("Invalid query")
            return
        }

        DispatchQueue.main.async {
            self.storeSessionVC?.performSearch(query: query)
            call.resolve()
        }
    }

    @objc func setStore(_ call: CAPPluginCall) {
        guard let storeId = call.getString("storeId") else {
            call.reject("Invalid storeId")
            return
        }

        DispatchQueue.main.async {
            self.storeSessionVC?.setStore(storeId: storeId)
            call.resolve()
        }
    }

    @objc func updateOverlay(_ call: CAPPluginCall) {
        guard let itemName = call.getString("itemName"),
              let searchTerm = call.getString("searchTerm"),
              let mode = call.getString("mode"),
              let activeIndex = call.getInt("activeIndex"),
              let primaryAction = call.getString("primaryAction"),
              let secondaryAction = call.getString("secondaryAction"),
              let secondaryEnabled = call.getBool("secondaryEnabled"),
              let rawCards = call.getArray("cards") as? [[String: Any]] else {
            call.reject("Invalid overlay payload")
            return
        }

        let cards = rawCards.compactMap { raw -> StoreSessionOverlayCard? in
            guard let id = raw["id"] as? String,
                  let title = raw["title"] as? String,
                  let quantity = raw["quantity"] as? String,
                  let state = raw["state"] as? String else {
                return nil
            }
            return StoreSessionOverlayCard(
                id: id,
                title: title,
                quantity: quantity,
                state: state,
                badge: raw["badge"] as? String
            )
        }

        let payload = StoreSessionOverlayPayload(
            mode: mode,
            cards: cards,
            activeIndex: activeIndex,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            secondaryEnabled: secondaryEnabled,
            cooldownSeconds: call.getInt("cooldownSeconds"),
            cooldownProgress: call.getDouble("cooldownProgress"),
            itemName: itemName,
            searchTerm: searchTerm
        )

        DispatchQueue.main.async {
            self.storeSessionVC?.updateOverlay(payload: payload)
            call.resolve()
        }
    }

    func notifyEvent(eventName: String, data: [String: Any] = [:]) {
        self.notifyListeners(eventName, data: data)
    }
}
