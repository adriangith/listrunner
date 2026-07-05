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
              let searchTerm = call.getString("searchTerm") else {
            call.reject("Invalid itemName or searchTerm")
            return
        }

        DispatchQueue.main.async {
            self.storeSessionVC?.updateOverlay(itemName: itemName, searchTerm: searchTerm)
            call.resolve()
        }
    }

    func notifyEvent(eventName: String, data: [String: Any] = [:]) {
        self.notifyListeners(eventName, data: data)
    }
}
