import ServiceManagement

/// 登录时自动启动。对应设置里的「开机自启 Hestia」
enum LoginItem {
    static func sync(_ on: Bool) {
        let app = SMAppService.mainApp
        do {
            if on, app.status != .enabled {
                try app.register()
            } else if !on, app.status == .enabled {
                try app.unregister()
            }
        } catch {
            NSLog("Hestia 登录项设置失败：\(error.localizedDescription)")
        }
    }
}
