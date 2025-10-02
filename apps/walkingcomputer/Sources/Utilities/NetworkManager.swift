import Foundation

// MARK: - Network Manager

class NetworkManager {
    static let shared = NetworkManager()

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0  // Start with 1 second
    private let session: URLSession

    private init() {
        // Configure session with reasonable timeouts
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0  // 30 second timeout for each request
        configuration.timeoutIntervalForResource = 60.0  // 60 second total timeout
        self.session = URLSession(configuration: configuration)

        log("Initialized with retry logic and 30s timeout", category: .network, component: "NetworkManager")
    }

    // MARK: - Retry Logic

    func performRequestWithRetry<T: Decodable>(_ request: URLRequest,
                                              responseType: T.Type) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Try the request
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    // Success - decode and return
                    return try JSONDecoder().decode(T.self, from: data)
                } else if httpResponse.statusCode >= 500 {
                    // Server error - retry
                    throw NetworkError.serverError(httpResponse.statusCode)
                } else {
                    // Client error - don't retry
                    throw NetworkError.clientError(httpResponse.statusCode)
                }

            } catch {
                lastError = error
                log("Attempt \(attempt + 1) failed: \(error)", category: .network, component: "NetworkManager")

                // Check if we should retry
                if !shouldRetry(for: error) || attempt == maxRetries - 1 {
                    throw error
                }

                // Calculate delay with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                log("Retrying in \(delay) seconds...", category: .network, component: "NetworkManager")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? NetworkError.unknown
    }

    func performRequestWithRetry(_ request: URLRequest) async throws -> Data {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Try the request
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    // Success
                    return data
                } else if httpResponse.statusCode >= 500 {
                    // Server error - retry
                    throw NetworkError.serverError(httpResponse.statusCode)
                } else {
                    // Client error - don't retry
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NetworkError.apiError(httpResponse.statusCode, errorBody)
                }

            } catch {
                lastError = error
                log("Attempt \(attempt + 1) failed: \(error)", category: .network, component: "NetworkManager")

                // Check if we should retry
                if !shouldRetry(for: error) || attempt == maxRetries - 1 {
                    throw error
                }

                // Calculate delay with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                log("Retrying in \(delay) seconds...", category: .network, component: "NetworkManager")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError ?? NetworkError.unknown
    }

    private func shouldRetry(for error: Error) -> Bool {
        let nsError = error as NSError

        // Don't retry POSIX errors (like "Message too long" - Code 40)
        if nsError.domain == NSPOSIXErrorDomain {
            return false
        }

        // Retry on network errors
        if nsError.domain == NSURLErrorDomain {
            let code = nsError.code
            // Retry on timeout, cannot connect, network lost, etc.
            return code == NSURLErrorTimedOut ||
                   code == NSURLErrorCannotConnectToHost ||
                   code == NSURLErrorNetworkConnectionLost ||
                   code == NSURLErrorNotConnectedToInternet
        }

        // Retry on server errors
        if let networkError = error as? NetworkError {
            switch networkError {
            case .serverError:
                return true
            case .clientError:
                return false
            default:
                return true
            }
        }

        return true  // Default to retry
    }

    // MARK: - HTTP Methods

    /// Perform a POST request with JSON body and return dictionary response
    func post(url: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw NetworkError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Set headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Serialize body to JSON
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Perform request with retry
        let data = try await performRequestWithRetry(request)

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse
        }

        return json
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case invalidResponse
    case serverError(Int)
    case clientError(Int)
    case apiError(Int, String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .clientError(let code):
            return "Client error: \(code)"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        case .unknown:
            return "Unknown network error"
        }
    }
}