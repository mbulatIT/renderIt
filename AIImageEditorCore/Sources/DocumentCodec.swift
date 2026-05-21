import Foundation

public enum DocumentCodec {
    public static func encode(_ document: Document) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return try enc.encode(document)
        } catch {
            throw EditorError.encoding(String(describing: error))
        }
    }

    public static func decode(_ data: Data) throws -> Document {
        let dec = JSONDecoder()
        do {
            return try dec.decode(Document.self, from: data)
        } catch {
            throw EditorError.decoding(String(describing: error))
        }
    }

    public static func load(from url: URL) throws -> Document {
        do {
            let data = try Data(contentsOf: url)
            return try decode(data)
        } catch let e as EditorError {
            throw e
        } catch {
            throw EditorError.fileIO("read \(url.path): \(error.localizedDescription)")
        }
    }

    public static func save(_ document: Document, to url: URL) throws {
        let data = try encode(document)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw EditorError.fileIO("write \(url.path): \(error.localizedDescription)")
        }
    }
}
