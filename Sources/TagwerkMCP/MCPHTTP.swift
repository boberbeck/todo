import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// MCP über HTTP („Streamable HTTP“), damit auch Claude im Browser und auf dem Handy Tagwerk nutzen kann:
/// claude.ai verbindet sich über einen Tunnel (z. B. Tailscale Funnel) mit diesem Server.
/// Ohne den geheimen Schlüssel im Pfad (`/mcp/<schlüssel>`) antwortet er nur mit 404.
public struct HTTPRequest: Equatable {
    public var method: String
    public var path: String
    /// Kopfzeilen mit kleingeschriebenen Namen
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Liest eine Anfrage aus den empfangenen Bytes. `nil`, solange Kopf oder Inhalt noch unvollständig sind.
    public static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        var path = String(requestLine[1])
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        return HTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: Data(body))
    }
}

public struct HTTPResponse: Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(text.utf8))
    }

    public var reason: String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        all["Cache-Control"] = "no-store"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// Beantwortet HTTP-Anfragen mit dem MCP-Server. Ohne Netzwerk, damit es testbar bleibt.
public final class MCPHTTPHandler {
    private let server: MCPServer
    private let token: String
    private let lock = NSLock()

    public init(server: MCPServer, token: String) {
        self.server = server
        self.token = token
    }

    /// Der Pfad, unter dem Claude den Server erreicht.
    public static func path(token: String) -> String { "/mcp/\(token)" }

    public func respond(to request: HTTPRequest) -> HTTPResponse {
        var path = request.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard Self.constantTimeEqual(path, Self.path(token: token)) else {
            return .text(404, "Not Found")
        }
        switch request.method {
        case "POST":
            guard !request.body.isEmpty, (try? JSONSerialization.jsonObject(with: request.body)) != nil else {
                return .text(400, "Erwartet wird eine JSON-RPC-Nachricht.")
            }
            let line = String(decoding: request.body, as: UTF8.self)
            lock.lock()
            let answer = server.handle(line: line)
            lock.unlock()
            guard let answer else { return HTTPResponse(status: 202) }
            var headers = ["Content-Type": "application/json"]
            if line.contains("\"initialize\"") {
                headers["Mcp-Session-Id"] = UUID().uuidString
            }
            return HTTPResponse(status: 200, headers: headers, body: Data(answer.utf8))
        case "GET":
            // Kein Ereignis-Strom vom Server aus; Claude fragt nur an.
            return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE"])
        case "DELETE":
            return HTTPResponse(status: 204)
        case "OPTIONS":
            return HTTPResponse(status: 204, headers: ["Allow": "POST, DELETE"])
        default:
            return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE"])
        }
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(left.count == right.count ? 0 : 1)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            difference |= a ^ b
        }
        return difference == 0
    }
}

#if canImport(Darwin)
private let systemBind = Darwin.bind
#else
private let systemBind = Glibc.bind
#endif

/// Einfacher HTTP-Server nur auf 127.0.0.1 (von außen kommt man nur über den Tunnel heran).
public final class MCPHTTPListener {
    public enum ListenerError: Error, CustomStringConvertible {
        case socket(String)

        public var description: String {
            switch self {
            case .socket(let message): return message
            }
        }
    }

    private let handler: MCPHTTPHandler
    private let port: UInt16
    private var socketFD: Int32 = -1
    private static let maximumRequestSize = 4 * 1024 * 1024

    public init(handler: MCPHTTPHandler, port: UInt16) {
        self.handler = handler
        self.port = port
    }

    /// Öffnet den Port. Danach `run()` aufrufen.
    public func bind() throws {
        signal(SIGPIPE, SIG_IGN)
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw ListenerError.socket("Socket lässt sich nicht öffnen.") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                systemBind(fd, addr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw ListenerError.socket("Port \(port) ist belegt oder nicht erlaubt.")
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw ListenerError.socket("Port \(port) lässt sich nicht öffnen.")
        }
        socketFD = fd
    }

    /// Nimmt Verbindungen an, bis der Prozess endet. Jede Verbindung läuft für sich.
    public func run() -> Never {
        while true {
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else { continue }
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                Self.serve(client, handler: handler)
            }
        }
    }

    private static func serve(_ client: Int32, handler: MCPHTTPHandler) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var request: HTTPRequest?
        while request == nil {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            received.append(buffer, count: count)
            if received.count > maximumRequestSize {
                write(HTTPResponse.text(413, "Zu groß").serialized(), to: client)
                return
            }
            request = HTTPRequest.parse(received)
        }
        guard let request else { return }
        write(handler.respond(to: request).serialized(), to: client)
    }

    private static func write(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                #if canImport(Darwin)
                let written = Darwin.write(client, pointer, remaining)
                #else
                let written = Glibc.write(client, pointer, remaining)
                #endif
                guard written > 0 else { return }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }
}
