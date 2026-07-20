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
                            withAnimation(PopupMotion.contentEase) { isVehicleInfoFloatingPresented = true }
                        },
                        onOpenMQTT: {
                            withAnimation(PopupMotion.contentEase) { isMQTTFloatingPresented = true }
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
                StatusControlFeedbackBridge(
                    onMQTTControlResult: { result in
                        handleMQTTControlResult(result)
                    },
                    onStateConfirmation: { confirmation in
                        handleControlStateConfirmation(confirmation)
                    }
                )
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
                    // 连接后保持附近设备弹窗打开，便于继续看连接/鉴权结果
                    withAnimation {
                        statusToastText = "正在连接 \(device.displayName)"
                    }
                },
                onClearBinding: {
                    mqttStore.clearBLEBindingAndRefresh()
                    withAnimation { statusToastText = "已清除旧绑定记录" }
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
        // 一点就切沙漏；刷新完成后再变回箭头。
        isRefreshing = true
        refreshScale = 1.0

        locationManager.forceRequestCurrentLocation()
        locationManager.resume()
        let location = VehicleLocationDisplayStore.shared
        let lat = location.displayLatitudeGcj
        let lng = location.displayLongitudeGcj
        let address = location.displayAddress
        if lat != 0, lng != 0 {
            locationManager.setCarLocation(lat: lat, lng: lng, address: address.isEmpty ? nil : address)
        }

        statusToastText = "正在刷新车况与钥匙…"
        mqttStore?.refreshNow(userInitiated: true) { _, message in
            statusToastText = message
            isRefreshing = false
            refreshScale = 1.0
        }

        // 兜底：网络卡住时也不让沙漏无限挂起
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if isRefreshing {
                isRefreshing = false
                refreshScale = 1.0
            }
        }
    }

    /// `/vehicle/control` 若下发，仅作为官方协议的附加诊断，不影响普通控制成功判定。
    private func handleMQTTControlResult(_ result: VehicleControlMQTTResult?) {
        guard let result else { return }
        withAnimation {
            statusToastText = result.isSuccess ? "收到附加 Control 回执" : "收到 Control 回执异常"
        }
    }

    /// 普通锁/窗/空调的主确认：MQTT app/status 或 HTTP 全量车况命中期望态。
    private func handleControlStateConfirmation(_ confirmation: VehicleControlStateConfirmation?) {
        guard let confirmation else { return }
        withAnimation {
            if confirmation.isConfirmed {
                statusToastText = "\(confirmation.commandTitle) 已由\(confirmation.source.title)确认"
            } else {
                statusToastText = "\(confirmation.commandTitle) 状态暂未确认"
            }
        }
    }

    private func handleQuickActionConfirm(
        action: CommandAction,
        temperature: Double?,
        durationMinutes: Int?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    ) {
        // 空调设温：用「发令前本地状态温度」作基线；弹窗若已改温，temperature 会不同并走 setTemperature。
        let state = vehicleStore?.state ?? .placeholder
        let command = action.asVehicleCommand(
            state: state,
            temperature: temperature,
            durationMinutes: durationMinutes,
            baselineTemperature: action == .acToggle ? state.acTemperature : nil,
            source: .quickAction
        )
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
        // 自动模式回退 HTTP 是正常默认路径，最终“请求已下发/状态确认”已携带足够证据；
        // 强制模式或自动选中 BLE 仍记录，便于核对实际传输通道。
        if vehicleControlRouteMode != .auto || selectedRoute == .ble {
            VehicleEventLogStore.shared.add(
                .action,
                "快捷路由选择",
                detail: "\(command.title) | mode=\(routeModeText) | route=\(actualRouteText)"
            )
        }

        let willUseBLE = selectedRoute == .ble

        let transport: VehicleCommandAsyncTransport
        if willUseBLE, let mqttStore {
            transport = BLEVehicleControlTransport(bleController: mqttStore)
        } else {
            transport = HTTPControlTransport(credentials: vehicleCredentials)
        }

        VehicleCommandExecutor.executeAsync(command, transport: transport, refresher: mqttStore) { result in
            DispatchQueue.main.async {
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
                    // 官方普通锁/窗确认来自 MQTT status 或 HTTP 车况；Control PB 不再作为必经等待项。
                    withAnimation {
                        statusToastText = willUseBLE
                            ? "\(command.title) 已通过 BLE 发送"
                            : "\(command.title) 已发送，等待车况确认"
                    }
                case .failed(let reason):
                    withAnimation {
                        statusToastText = "\(command.title) 失败：\(reason)"
                    }
                case .timedOut(let reason):
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
