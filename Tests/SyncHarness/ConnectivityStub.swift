import Foundation

@MainActor
final class ConnectivityService {
    static let contextLimit = 48 * 1_024
    static var instances: [ConnectivityService] = []
    var onReceive: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?
    var onActivated: (() -> Void)?
    var context: Data?
    var reliable: [Data] = []
    private let outboxURL: URL

    init(outboxURL: URL) {
        self.outboxURL = outboxURL
        Self.instances.append(self)
    }
    func start() {}
    func publish(context: Data?, reliable: [Data]) {
        self.context = context
        self.reliable = reliable
    }
    func cancelPendingTransfers() throws {
        reliable = []
        if FileManager.default.fileExists(atPath: outboxURL.path) {
            try FileManager.default.removeItem(at: outboxURL)
        }
    }
}
