import Foundation

// MARK: - Minimal toolset steered by the LLM

enum ToolAction: Codable {
    case extract(text: String) // model-selected content to speak (from spec context)
    case overwrite(artifact: String, content: String) // full replacement
    case writeDiff(artifact: String, diff: String, fallbackContent: String?) // unified diff; optional full content fallback
    case search(query: String, depth: String?)
    case copy(artifact: String)

    private enum CodingKeys: String, CodingKey {
        case op
        case artifact
        case text
        case content
        case diff
        case query
        case depth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
        case "extract":
            self = .extract(text: try container.decode(String.self, forKey: .text))
        case "overwrite":
            self = .overwrite(
                artifact: try container.decode(String.self, forKey: .artifact),
                content: try container.decode(String.self, forKey: .content)
            )
        case "write_diff":
            let artifact = try container.decode(String.self, forKey: .artifact)
            let diff = try container.decode(String.self, forKey: .diff)
            let fallback = try container.decodeIfPresent(String.self, forKey: .content)
            self = .writeDiff(artifact: artifact, diff: diff, fallbackContent: fallback)
        case "search":
            self = .search(
                query: try container.decode(String.self, forKey: .query),
                depth: try container.decodeIfPresent(String.self, forKey: .depth)
            )
        case "copy":
            self = .copy(artifact: try container.decode(String.self, forKey: .artifact))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown op: \(op)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .extract(let text):
            try container.encode("extract", forKey: .op)
            try container.encode(text, forKey: .text)
        case .overwrite(let artifact, let content):
            try container.encode("overwrite", forKey: .op)
            try container.encode(artifact, forKey: .artifact)
            try container.encode(content, forKey: .content)
        case .writeDiff(let artifact, let diff, let fallback):
            try container.encode("write_diff", forKey: .op)
            try container.encode(artifact, forKey: .artifact)
            try container.encode(diff, forKey: .diff)
            try container.encodeIfPresent(fallback, forKey: .content)
        case .search(let query, let depth):
            try container.encode("search", forKey: .op)
            try container.encode(query, forKey: .query)
            try container.encodeIfPresent(depth, forKey: .depth)
        case .copy(let artifact):
            try container.encode("copy", forKey: .op)
            try container.encode(artifact, forKey: .artifact)
        }
    }
}

