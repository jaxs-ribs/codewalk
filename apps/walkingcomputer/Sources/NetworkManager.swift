import Foundation

// MARK: - Network Manager

class NetworkManager {
    static let shared = NetworkManager()

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0  // Start with 1 second
    private var lastSuccessfulResponse: String?
    private var isOffline = false

    private init() {
        print("[NetworkManager] Initialized with retry logic")
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
                    isOffline = false
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
                print("[NetworkManager] Attempt \(attempt + 1) failed: \(error)")

                // Check if we should retry
                if !shouldRetry(for: error) || attempt == maxRetries - 1 {
                    throw error
                }

                // Calculate delay with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                print("[NetworkManager] Retrying in \(delay) seconds...")

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
                    isOffline = false
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
                print("[NetworkManager] Attempt \(attempt + 1) failed: \(error)")

                // Check if it's a network error
                if (error as NSError).domain == NSURLErrorDomain {
                    isOffline = true
                }

                // Check if we should retry
                if !shouldRetry(for: error) || attempt == maxRetries - 1 {
                    throw error
                }

                // Calculate delay with exponential backoff
                let delay = baseDelay * pow(2.0, Double(attempt))
                print("[NetworkManager] Retrying in \(delay) seconds...")

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

    // MARK: - Offline Support

    func cacheResponse(_ response: String, for key: String) {
        UserDefaults.standard.set(response, forKey: "cached_\(key)")
        lastSuccessfulResponse = response
    }

    func getCachedResponse(for key: String) -> String? {
        return UserDefaults.standard.string(forKey: "cached_\(key)") ?? lastSuccessfulResponse
    }

    func getOfflineFallback(for action: String) -> String {
        switch action {
        case "conversation":
            return "I understand what you're saying. Let me think about that."
        case "write_description":
            return "I'll write the description, but I'm having network issues. Try again in a moment."
        case "write_phasing":
            return "I'll create the phasing, but the network is spotty. Give me a second."
        default:
            return "I understand. The network is a bit slow right now."
        }
    }

    var networkStatus: String {
        return isOffline ? "Offline" : "Online"
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