import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var vehicleCredentials: VehicleCredentialsStore
    @EnvironmentObject var keylessSettings: KeylessSettingsStore
    @AppStorage(AppDiagnosticsSettings.vehicleControlRouteModeKey) private var vehicleControlRouteModeRaw = VehicleControlRouteMode.auto.rawValue
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0
    @State private var isAddressFloatingPresented = false
    @State private var isMQTTFloatingPresented = false
    @State private var isVehicleInfoFloatingPresented = false
    @State private var isNearbyBLEDevicesFloatingPresented = false
    @State private var statusToastText: String?
    @State private var activeCommand: CommandAction? = nil
    @State private var isExecutingDirectLockUnlock = false
    @State private var pendingControlServiceCode: String? = nil
    @State private var pendingControlTitle: String? = nil
    @State private var pendingControlSentAt: Date? = nil
    @State private var pendingControlWaitID: UUID? = nil

    private var vehicleStore: VehicleStateStore? {
        VehicleStateStoreBridge.current
    }

    private var mqttStore: MQTTVehicleStateStore? {
        vehicleStore as? MQTTVehicleStateStore
    }

    private var vehicleControlRouteMode: VehicleControlRouteMode {
        VehicleControlRouteMode(rawValue: vehicleControlRouteModeRaw) ?? .auto
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    StatusTopBarHost(
                        isRefreshing: isRefreshing,
                        refreshScale: refreshScale,
                        onRefresh: handleRefresh
                    )

                    StatusMainDashboardHost(
                        onCommand: { command in
                            if command == .lockUnlock,
                               !keylessSettings.settings.lockUnlockConfirmationEnabled {
                                guard !isExecutingDirectLockUnlock else { return }
                                isExecutingDirectLockUnlock = true
                                handleQuickActionConfirm(
                                    action: command,
                                    temperature: nil,
                                    durationMinutes: nil,
                                    completion: { _ in
                                        isExecutingDirectLockUnlock = false
                                    }
                                )
                            } else {
                                withAnimation(PopupMotion.presentSpring) {
                                    activeCommand = command
                                }
                            }
                        },
                        onOpenVehicleInfo: {
                            withAnimation(PopupMotion.presentSpring) { isVehicleInfoFloatingPresented = true }
                        },
                        onOpenMQTT: {
                            withAnimation(PopupMotion.presentSpring) { isMQTTFloatingPresented = true }
                        }
                    )
                }
                // 明确内容尺寸，减少 ScrollView 对子视图高度的错误缓存
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
            .onDisappear {
                scrollState.reset()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                locationManager.pause()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                locationManager.resume()
            }

            if isAddressFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(PopupMotion.dismissEase) { isAddressFloatingPresented = false }
                    }

                addressFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(PopupMotion.transition)
                    .zIndex(10)
            }

            if isMQTTFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(PopupMotion.dismissEase) { isMQTTFloatingPresented = false }
                    }

                mqttFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(PopupMotion.transition)
                    .zIndex(12)
            }

            if isVehicleInfoFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(PopupMotion.dismissEase) { isVehicleInfoFloatingPresented = false }
                    }

                vehicleInfoFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(PopupMotion.transition)
                    .zIndex(14)
            }

            if isNearbyBLEDevicesFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(PopupMotion.dismissEase) { isNearbyBLEDevicesFloatingPresented = false }
                    }

                nearbyBLEDevicesFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(PopupMotion.transition)
                    .zIndex(16)
            }

            // 快捷操作居中弹窗
            if let command = activeCommand {
                StatusCommandConfirmHost(
                    action: command,
                    isPresented: Binding(
                        get: { activeCommand != nil },
                        set: {
                            if !$0 {
                                activeCommand = nil
                            }
                        }
                    ),
                    onConfirm: { cmd, temp, duration, completion in
                        handleQuickActionConfirm(action: cmd, temperature: temp, durationMinutes: duration, completion: completion)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(PopupMotion.transition)
                .zIndex(20)
            }
        }
        .overlay(alignment: .bottom) {
            if let text = statusToastText {
                ToastView(text: text)
                    .padding(.bottom, 88)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { statusToastText = nil }
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddressFloatingWindow)) { _ in
            withAnimation(PopupMotion.presentSpring) { isAddressFloatingPresented = true }
        }
        .background(
            Group {
                StatusLocationSyncBridge()
                StatusControlFeedbackBridge { result in
                    handleMQTTControlResult(result)
                }
            }
        )
    }

    @ViewBuilder
    private func mqttFloatingWindow() -> some View {
        StatusMQTTFloatingHost(
            onClose: { withAnimation(PopupMotion.dismissEase) { isMQTTFloatingPresented = false } },
            onToast: { text in withAnimation { statusToastText = text } }
        )
    }

    @ViewBuilder
    private func vehicleInfoFloatingWindow() -> some View {
        StatusVehicleInfoFloatingHost(
            onOpenNearby: { withAnimation(PopupMotion.presentSpring) { isNearbyBLEDevicesFloatingPresented = true } },
            onClose: { withAnimation(PopupMotion.dismissEase) { isVehicleInfoFloatingPresented = false } },
            onToast: { text in withAnimation { statusToastText = text } }
        )
    }

    @ViewBuilder
    private func nearbyBLEDevicesFloatingWindow() -> some View {
        if let mqttStore {
            NearbyBLEDevicesPopupView(
                nearbyStore: mqttStore.nearbyBLEDevicesStore,
                initialBinding: VehicleBLEBindingStore.load(),
                onBind: { device in
                    mqttStore.bindNearbyBLEDevice(device)
                    // 绑定后保持附近设备弹窗打开，便于继续看连接/鉴权结果
                    withAnimation {
                        statusToastText = "已绑定 \(device.displayName)，正在优先连接"
                    }
                },
                onClearBinding: {
                    mqttStore.clearBLEBindingAndRefresh()
                    withAnimation { statusToastText = "已取消蓝牙绑定" }
                },
                onClose: {
                    withAnimation(PopupMotion.dismissEase) { isNearbyBLEDevicesFloatingPresented = false }
                }
            )
        }
    }

    @ViewBuilder
    private func addressFloatingWindow() -> some View {
        StatusAddressFloatingHost(isPresented: $isAddressFloatingPresented)
    }

    private func handleRefresh() {
        AppHaptics.light()
        withAnimation(PopupMotion.presentSpring) {
            refreshScale = 1.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(PopupMotion.contentEase) {
                refreshScale = 1.0
                isRefreshing = true
            }
        }

        locationManager.forceRequestCurrentLocation()
        locationManager.resume()
        let location = VehicleLocationDisplayStore.shared
        let lat = location.displayLatitudeGcj
        let lng = location.displayLongitudeGcj
        let address = location.displayAddress
        if lat != 0, lng != 0 {
            locationManager.setCarLocation(lat: lat, lng: lng, address: address.isEmpty ? nil : address)
        }

        withAnimation { statusToastText = "正在刷新车况与钥匙…" }
        mqttStore?.refreshNow(userInitiated: true) { _, message in
            withAnimation { statusToastText = message }
            isRefreshing = false
        }

        // 兜底：网络卡住时也不让转圈无限挂起
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if isRefreshing {
                isRefreshing = false
            }
        }
    }

    private func handleMQTTControlResult(_ result: VehicleControlMQTTResult?) {
        guard let result else { return }
        let matched = result.serviceCode == pendingControlServiceCode
        let elapsedText: String
        if matched, let sentAt = pendingControlSentAt {
            elapsedText = ", sent→mqtt=\(Int(Date().timeIntervalSince(sentAt) * 1000))ms"
        } else {
            elapsedText = ""
        }
        let title = matched ? "MQTT 控制回执（匹配当前命令）" : "MQTT 控制回执"
        let commandText = matched ? "command=\(pendingControlTitle ?? "--"), " : ""
        VehicleEventLogStore.shared.add(result.isSuccess ? .action : .error, title, detail: "\(commandText)\(result.displayDetail)\(elapsedText)")
        if matched {
            withAnimation {
                statusToastText = result.isSuccess
                    ? "\(pendingControlTitle ?? "命令") 回执成功"
                    : "\(pendingControlTitle ?? "命令") 回执失败"
            }
            pendingControlServiceCode = nil
            pendingControlTitle = nil
            pendingControlSentAt = nil
            pendingControlWaitID = nil
        }
    }

    private func beginControlReceiptWaitIfNeeded() {
        guard let serviceCode = pendingControlServiceCode,
              let commandTitle = pendingControlTitle else { return }
        let waitID = UUID()
        pendingControlWaitID = waitID
        VehicleEventLogStore.shared.add(.action, "等待 MQTT 控制回执", detail: "command=\(commandTitle), serviceCode=\(serviceCode), timeout=8s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard pendingControlWaitID == waitID,
                  pendingControlServiceCode == serviceCode else { return }
            VehicleEventLogStore.shared.add(.warning, "MQTT 控制回执缺失", detail: "command=\(commandTitle), serviceCode=\(serviceCode), waited=8000ms")
            pendingControlServiceCode = nil
            pendingControlTitle = nil
            pendingControlSentAt = nil
            pendingControlWaitID = nil
        }
    }

    private func controlServiceCode(for kind: VehicleCommandKind) -> String? {
        switch kind {
        case .lock, .unlock:
            return "doorLockStatus"
        case .findCar:
            return "CarSearch"
        case .acOn, .acOff, .quickCool:
            return "acStatus"
        case .openWindows, .closeWindows:
            return "windowStatus"
        case .remoteStart:
            return "RemotePowerUp"
        case .remoteStop:
            return nil
        }
    }

    private func handleQuickActionConfirm(
        action: CommandAction,
        temperature: Double?,
        durationMinutes: Int?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    ) {
        let command = action.asVehicleCommand(state: vehicleStore?.state ?? .placeholder, temperature: temperature, durationMinutes: durationMinutes, source: .quickAction)
        let supportsBLE = command.kind.supportsBLEControl
        let bleReady = mqttStore?.canUseBLEForVehicleControl == true

        enum SelectedRoute {
            case ble
            case http
        }

        let selectedRoute: SelectedRoute
        switch vehicleControlRouteMode {
        case .forceBLE:
            guard supportsBLE else {
                completion(VehicleCommandExecutionResult(
                    command: command,
                    state: .failed("当前命令不支持 BLE 强制模式"),
                    userMessage: "\(command.title) 暂不支持蓝牙控制，请改用网络控制。",
                    shouldRefresh: false,
                    refreshDelay: 0
                ))
                return
            }
            guard bleReady else {
                VehicleEventLogStore.shared.add(.warning, "快捷路由阻止", detail: "\(command.title) | mode=强制BLE | BLE 未鉴权成功")
                completion(VehicleCommandExecutionResult(
                    command: command,
                    state: .failed("强制BLE，但当前 BLE 未鉴权成功"),
                    userMessage: "蓝牙尚未就绪，请连接车辆蓝牙后重试。",
                    shouldRefresh: false,
                    refreshDelay: 0
                ))
                return
            }
            selectedRoute = .ble
        case .forceHTTP:
            selectedRoute = .http
        case .auto:
            selectedRoute = (supportsBLE && bleReady) ? .ble : .http
        }

        let routeModeText = vehicleControlRouteMode.title
        let actualRouteText = selectedRoute == .ble ? "BLE" : "HTTP"
        VehicleEventLogStore.shared.add(.action, "快捷路由选择", detail: "\(command.title) | mode=\(routeModeText) | route=\(actualRouteText)")

        let willUseBLE = selectedRoute == .ble
        let mqttReceiptEnabled = keylessSettings.settings.mqttEnabled
        pendingControlServiceCode = (willUseBLE || !mqttReceiptEnabled) ? nil : controlServiceCode(for: command.kind)
        pendingControlTitle = command.title
        pendingControlSentAt = nil

        let transport: VehicleCommandAsyncTransport
        if willUseBLE, let mqttStore {
            transport = BLEVehicleControlTransport(bleController: mqttStore)
        } else {
            transport = HTTPControlTransport(credentials: vehicleCredentials)
        }

        VehicleCommandExecutor.executeAsync(command, transport: transport, refresher: mqttStore) { result in
            DispatchQueue.main.async {
                let routePrefix = ""
                let patchedResult = VehicleCommandExecutionResult(
                    command: result.command,
                    state: result.state,
                    userMessage: result.userMessage,
                    shouldRefresh: result.shouldRefresh,
                    refreshDelay: result.refreshDelay,
                    timing: result.timing
                )

                switch patchedResult.state {
                case .sent, .completed:
                    if !willUseBLE, (command.kind == .lock || command.kind == .unlock) {
                        mqttStore?.noteAppDoorLockCommand(command.kind == .lock)
                    }
                    if !willUseBLE, mqttReceiptEnabled {
                        pendingControlSentAt = Date()
                        beginControlReceiptWaitIfNeeded()
                    }
                    withAnimation {
                        if willUseBLE {
                            statusToastText = "\(command.title) 已通过 BLE 发送"
                        } else if mqttReceiptEnabled {
                            statusToastText = "\(command.title) 已发送，等待回执"
                        } else {
                            statusToastText = "\(command.title) 已发送，正在刷新车况"
                        }
                    }
                case .failed(let reason):
                    pendingControlServiceCode = nil
                    pendingControlTitle = nil
                    pendingControlSentAt = nil
                    pendingControlWaitID = nil
                    withAnimation {
                        statusToastText = "\(command.title) 失败：\(reason)"
                    }
                case .timedOut(let reason):
                    pendingControlServiceCode = nil
                    pendingControlTitle = nil
                    pendingControlSentAt = nil
                    pendingControlWaitID = nil
                    withAnimation {
                        statusToastText = "\(command.title) 超时：\(reason)"
                    }
                case .feedbackOnly, .planned:
                    withAnimation {
                        statusToastText = patchedResult.userMessage
                    }
                }
                completion(patchedResult)
            }
        }
    }
}

struct PopupActionGridButton: View {
    let title: String
    let icon: String
    let tint: Color
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.9)))
                    }
                }
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(ResponsiveButtonStyle())
    }
}
