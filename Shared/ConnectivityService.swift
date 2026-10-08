import Foundation
import WatchConnectivity

/// Transports only to the user's paired devices. Every payload is encoded Data,
/// never a Swift value bridged through an untyped WCSession dictionary.
@MainActor
final class ConnectivityService: NSObject, WCSessionDelegate {
    nonisolated static let contextLimit = 48 * 1_024
    nonisolated private static let payloadKey = "com.repflow.snapshot.v1"
    nonisolated private static let fileMarker = "com.repflow.snapshot-file.v1"
    nonisolated private static let receiveLimit = 50 * 1_024 * 1_024

    var onReceive: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?
    var onActivated: (() -> Void)?

    private var session: WCSession?
    private let outboxURL: URL

    init(outboxURL: URL) {
        self.outboxURL = outboxURL
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else {
            onStatus?("当前设备不支持配对同步，可独立使用")
            return
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        onStatus?("正在连接配对设备…")
        session.activate()
    }

    /// Used only after the user confirms clearing local and paired app data.
    func cancelPendingTransfers() throws {
        session?.outstandingUserInfoTransfers.forEach { $0.cancel() }
        session?.outstandingFileTransfers.forEach { $0.cancel() }
        if FileManager.default.fileExists(atPath: outboxURL.path) {
            try FileManager.default.removeItem(at: outboxURL)
        }
    }

    func publish(context: Data?, reliable: [Data]) {
        guard let session else {
            onStatus?("可离线使用，当前设备不支持配对同步")
            return
        }
        guard session.activationState == .activated else {
            onStatus?("等待配对连接，数据已保存在本机")
            if session.activationState == .notActivated { session.activate() }
            return
        }
        guard counterpartIsInstalled(session) else { return }

        do {
            if let context {
                try session.updateApplicationContext([Self.payloadKey: context])
            }
            for data in reliable {
                if data.count <= Self.contextLimit {
                    // A retry should not enqueue an identical packet repeatedly.
                    let alreadyQueued = session.outstandingUserInfoTransfers.contains {
                        ($0.userInfo[Self.payloadKey] as? Data) == data
                    }
                    if !alreadyQueued {
                        session.transferUserInfo([Self.payloadKey: data])
                    }
                } else {
                    // Long histories may exceed WC dictionary limits. The system
                    // transports files in the background and retains the transfer.
                    try enqueueFile(data, session: session)
                }
            }
            onStatus?(session.isReachable
                ? "已提交同步，等待配对设备接收"
                : "已加入同步队列，配对设备可用时传输")
        } catch {
            onStatus?("同步暂未成功，数据仍在本机；请稍后重试")
        }
    }

    private func counterpartIsInstalled(_ session: WCSession) -> Bool {
        #if os(iOS)
        guard session.isPaired else {
            onStatus?("尚未配对 Apple Watch，可先编辑计划")
            return false
        }
        guard session.isWatchAppInstalled else {
            onStatus?("请在配对的 Apple Watch 安装组迹")
            return false
        }
        #elseif os(watchOS)
        guard session.isCompanionAppInstalled else {
            onStatus?("独立使用中，安装 iPhone 配套 App 后可同步")
            return false
        }
        #endif
        return true
    }

    private func enqueueFile(_ data: Data, session: WCSession) throws {
        for transfer in session.outstandingFileTransfers {
            guard transfer.file.metadata?[Self.fileMarker] as? Bool == true else { continue }
            if (try? Data(contentsOf: transfer.file.fileURL)) == data { return }
        }
        try FileManager.default.createDirectory(at: outboxURL, withIntermediateDirectories: true)
        let fileURL = outboxURL.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        try data.write(to: fileURL, options: .atomic)
        session.transferFile(fileURL, metadata: [Self.fileMarker: true])
    }

    private func receive(_ data: Data) {
        guard data.count <= Self.receiveLimit else {
            onStatus?("同步数据过大，请先导出并整理训练历史")
            return
        }
        onReceive?(data)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let activated = activationState == .activated
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if activated && !failed {
                self.onActivated?()
            } else {
                self.onStatus?("配对同步尚未连接，可继续离线记录")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.payloadKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[Self.payloadKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[Self.fileMarker] as? Bool == true else { return }
        // WCSession removes the received temporary file after this callback.
        // Read it before switching to the main actor.
        guard let data = try? Data(contentsOf: file.fileURL) else {
            Task { @MainActor [weak self] in self?.onStatus?("同步文件读取失败，请重试") }
            return
        }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let failed = error != nil
        Task { @MainActor [weak self] in
            self?.onStatus?(failed ? "配对传输暂未完成，请稍后重试" : "配对传输已完成")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let fileURL = fileTransfer.file.fileURL
        let isOwnFile = fileTransfer.file.metadata?[Self.fileMarker] as? Bool == true
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isOwnFile && fileURL.deletingLastPathComponent().standardizedFileURL == self.outboxURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            self.onStatus?(failed ? "配对文件传输暂未完成，请稍后重试" : "配对传输已完成")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.onActivated?() }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.onActivated?() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.onStatus?("正在切换配对手表…") }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required when the user switches between paired Apple Watches.
        Task { @MainActor [weak self] in self?.session?.activate() }
    }
    #endif
}
