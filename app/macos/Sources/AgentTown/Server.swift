import Foundation
import Network
import TownCore

/// The loopback HTTP server: binds 127.0.0.1 on a random port, writes the endpoint
/// file, checks the token and protocol version, and hands accepted batches over.
final class LoopbackServer: @unchecked Sendable {
    let token = EndpointFile.newToken()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "agent-town.server")
    private let onBatch: @Sendable (Batch) -> Void
    private(set) var port: Int?

    init(onBatch: @escaping @Sendable (Batch) -> Void) { self.onBatch = onBatch }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, let p = l.port?.rawValue else { return }
            self.port = Int(p)
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
            do {
                try EndpointFile(port: Int(p), token: self.token, appVersion: version).write()
                NSLog("agent-town: listening on 127.0.0.1:%d", Int(p))
            } catch {
                NSLog("agent-town: could not write the endpoint file: %@", "\(error)")
            }
        }
        listener = l
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        EndpointFile.remove()
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            switch HTTPParser.parse(buf) {
            case .incomplete where error == nil && !isComplete:
                self.receive(c, buffer: buf)
            case .complete(let req, _):
                let (status, batch) = EventEndpoint.handle(req, token: self.token)
                self.reply(c, status)
                if let batch { self.onBatch(batch) }
            default:
                self.reply(c, 400)
            }
        }
    }

    private func reply(_ c: NWConnection, _ status: Int) {
        c.send(content: HTTPParser.response(status: status), completion: .contentProcessed { _ in c.cancel() })
    }
}
