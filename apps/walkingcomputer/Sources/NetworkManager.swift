import Foundation

// MARK: - Network Manager

class NetworkManager {
    static let shared = NetworkManager()

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0  // Start with 1 second

    private init() {
        log("Initialized with retry logic", category: .network, component: "NetworkManager")
    }

    // MARK: - Retry Logic

    func performRequestWithRetry<T: Decodable>(_ request: URLRequest,
                                              responseType: T.Type) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                // Try the request
                let (data, response) = try await URLSession.shared.data(for: request)

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
                let (data, response) = try await URLSession.shared.data(for: request)

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
        // Retry on network errors
        if (error as NSError).domain == NSURLErrorDomain {
            let code = (error as NSError).code
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