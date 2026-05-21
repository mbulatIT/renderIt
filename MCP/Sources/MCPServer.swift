import Foundation
import AIImageEditorCore

/// Minimal JSON-RPC 2.0 over stdio MCP server.
/// One JSON object per line on stdin / stdout.
final class MCPServer {
    let tools: [String: MCPTool]
    let stdin = FileHandle.standardInput
    let stdout = FileHandle.standardOutput
    let stderr = FileHandle.standardError

    init(tools: [MCPTool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func run() {
        // Read line by line.
        let buf = LineReader(handle: stdin)
        while let line = buf.next() {
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let req = try JSON.decode(data: data)
                if let response = handle(request: req) {
                    var out = try JSON.encode(response)
                    out.append(0x0A) // newline
                    try stdout.write(contentsOf: out)
                }
            } catch {
                logError("parse error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Request handling

    private func handle(request: JSONValue) -> JSONValue? {
        guard let method = request.objectValue?["method"]?.stringValue else { return nil }
        let id = request.objectValue?["id"]
        let params = request.objectValue?["params"] ?? .object([:])

        // Notifications (no id) return no response.
        if id == nil {
            // notifications/initialized etc. — ignore.
            return nil
        }

        switch method {
        case "initialize":
            return result(id: id!, .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:]),
                    "resources": .object([:]),
                ]),
                "serverInfo": .object([
                    "name": .string("aiimageeditor"),
                    "version": .string("0.1.0"),
                ]),
            ]))

        case "tools/list":
            let arr = tools.values
                .sorted { $0.name < $1.name }
                .map { t -> JSONValue in
                    .object([
                        "name": .string(t.name),
                        "description": .string(t.description),
                        "inputSchema": t.inputSchema,
                    ])
                }
            return result(id: id!, .object(["tools": .array(arr)]))

        case "tools/call":
            let name = params.objectValue?["name"]?.stringValue ?? ""
            let args = params.objectValue?["arguments"] ?? .object([:])
            guard let tool = tools[name] else {
                return result(id: id!, errorResult("unknown tool '\(name)'"))
            }
            do {
                let payload = try tool.run(args)
                return result(id: id!, payload)
            } catch let e as EditorError {
                return result(id: id!, errorResult(e.errorDescription ?? "error"))
            } catch {
                return result(id: id!, errorResult(error.localizedDescription))
            }

        case "resources/list":
            // Expose presets and bezels as resource hints.
            var resources: [JSONValue] = []
            for p in PresetCatalog.all {
                resources.append(.object([
                    "uri": .string("aiimageeditor://preset/\(p.id)"),
                    "name": .string("Preset: \(p.title)"),
                    "mimeType": .string("application/json"),
                ]))
            }
            for b in DeviceBezelCatalog.all {
                resources.append(.object([
                    "uri": .string("aiimageeditor://bezel/\(b.id)"),
                    "name": .string("Bezel: \(b.title)"),
                    "mimeType": .string("application/json"),
                ]))
            }
            return result(id: id!, .object(["resources": .array(resources)]))

        case "ping":
            return result(id: id!, .object([:]))

        default:
            return rpcError(id: id!, code: -32601, message: "method not found: \(method)")
        }
    }

    private func result(id: JSONValue, _ value: JSONValue) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": value,
        ])
    }

    private func rpcError(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object([
                "code": .integer(code),
                "message": .string(message),
            ]),
        ])
    }

    private func logError(_ text: String) {
        let line = "[mcp] \(text)\n"
        if let data = line.data(using: .utf8) {
            try? stderr.write(contentsOf: data)
        }
    }
}

/// Reads newline-delimited input synchronously from a FileHandle.
final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) { self.handle = handle }

    func next() -> String? {
        while !buffer.contains(0x0A) {
            let chunk = handle.availableData
            if chunk.isEmpty { // EOF
                if buffer.isEmpty { return nil }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                buffer.removeAll()
                return line
            }
            buffer.append(chunk)
        }
        guard let nl = buffer.firstIndex(of: 0x0A) else { return nil }
        let lineData = buffer.subdata(in: buffer.startIndex..<nl)
        buffer.removeSubrange(buffer.startIndex...nl)
        return String(data: lineData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    }
}
