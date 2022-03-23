// This package provide a base module to make simple HTTP requests

import Foundation

// MARK: - Base

public protocol HTTPEndpoint {
    var url: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var task: HTTPTask { get }
    var headers: HTTPHeaders? { get }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public enum HTTPTask {
    case request
    case requestWithParameters(
        bodyParams: HTTPParameters?,
        encoding: HTTPParametersEncoding,
        urlParams: HTTPParameters?
    )
    case requestWithParametersAndHeaders(
        bodyParams: HTTPParameters?,
        encoding: HTTPParametersEncoding,
        urlParams: HTTPParameters?,
        headers: HTTPHeaders?
    )
}

public typealias HTTPHeaders = [String: String]

// MARK: - Parameters

public typealias HTTPParameters = [String: Any]

public enum HTTPParametersEncoderError: String, Error {
    case badURL = "Received empty or corrupted url"
    case failedToEncode = "Failed to encode the parameters"
}

public protocol HTTPParametersEncoder {
    static func encode(_ request: inout URLRequest, with params: HTTPParameters) throws
}

public struct HTTPParametersJSONEncoder: HTTPParametersEncoder {
    public static func encode(_ request: inout URLRequest, with params: HTTPParameters) throws {
        guard JSONSerialization.isValidJSONObject(params) else {
            throw HTTPParametersEncoderError.failedToEncode
        }
        let serialized = try JSONSerialization.data(withJSONObject: params)
        request.httpBody = serialized
    }

}

public struct HTTPParametersURLEncoder: HTTPParametersEncoder {
    public static func encode(_ request: inout URLRequest, with params: HTTPParameters) throws {
        guard let url = request.url else { throw HTTPParametersEncoderError.badURL }
        guard !params.isEmpty else { return }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        
        components.queryItems = []
        params.forEach { (key, value) in
            components.queryItems?.append(URLQueryItem(name: key, value: "\(value)"))
        }
        request.url = components.url
    }
    
}

// Providing concrete encode method through specified enum
public enum HTTPParametersEncoding {
    case url
    case json
    case both
    
    public func encode(
        request: inout URLRequest,
        bodyParams: HTTPParameters?,
        urlParams: HTTPParameters?
    ) throws {
        do {
            switch self {
                case .url:
                    guard let params = urlParams else { return }
                    try HTTPParametersURLEncoder.encode(&request, with: params)
                    sanitize(&request, contentType: "application/x-www-form-urlencoded")
                
                case .json:
                    guard let params = bodyParams else { return }
                    try HTTPParametersJSONEncoder.encode(&request, with: params)
                    sanitize(&request, contentType: "application/json")
                
                case .both:
                    if let bodyParams = bodyParams {
                        try HTTPParametersJSONEncoder.encode(&request, with: bodyParams)
                    }
                    if let urlParams = urlParams {
                        try HTTPParametersURLEncoder.encode(&request, with: urlParams)
                    }
            }
        } catch {
            throw error
        }
    }
    
    private func sanitize(_ request: inout URLRequest, contentType: String) {
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
    }
    
}

// MARK: - Router

public typealias HTTPRouterCompletion = (
    _ data: Data?, _ response: URLResponse?, _ error: Error?
) -> ()

public protocol HTTPRouterProtocol {
    associatedtype ConcreteEndpoint: HTTPEndpoint
    
    func resume(_ route: ConcreteEndpoint, completion: @escaping HTTPRouterCompletion)
    func cancel()
}

public class HTTPRouter<ConcreteEndpoint: HTTPEndpoint>: HTTPRouterProtocol {
    private let session: URLSession
    
    private var task: URLSessionTask?
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func resume(_ route: ConcreteEndpoint, completion: @escaping HTTPRouterCompletion) {
        var request = URLRequest(url: route.url.appendingPathComponent(route.path))
        request.httpMethod = route.method.rawValue
        
        do {
            switch route.task {
                case .request:
                    break
                
                case .requestWithParametersAndHeaders(
                    let bodyParams, let encoding, let urlParams, let headers
                ):
                    if let headers = headers {
                        headers.forEach { (key, value) in
                            request.setValue(value, forHTTPHeaderField: key)
                        }
                    }
                    fallthrough
                
                case .requestWithParameters(let bodyParams, let encoding, let urlParams):
                    try encoding.encode(
                        request: &request, bodyParams: bodyParams, urlParams: urlParams
                    )
            }
        } catch {
            return completion(nil, nil, error)
        }
        
        task = session.dataTask(with: request, completionHandler: completion)
        task?.resume()
    }
    
    public func cancel() {
        task?.cancel()
    }
}

// MARK: - Client

public typealias HTTPClientResult = Result<Any?, HTTPClientError>

public typealias HTTPClientCompletion = (HTTPClientResult) -> ()

public enum HTTPClientError: String, Error {
    case connectionError = "Internet connection not found"
    case authError = "Authentication failed"
    case requestError = "Corrupted request"
    case emptyDataError = "Data is empty"
    case unknownError = "Unknown error"
}

public enum HTTPClientQueue {
    case parallel
    case serial
}

public protocol HTTPClientProtocol {
    associatedtype ConcreteEndpoint: HTTPEndpoint
    
    func fetchSync(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        completion: @escaping HTTPClientCompletion
    )
    
    func fetchSyncAfter(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        after delayInSeconds: Double,
        completion: @escaping HTTPClientCompletion
    )
    
    func fetchAsync(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        completion: @escaping HTTPClientCompletion
    )
    
    func fetchAsyncAfter(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        after delayInSeconds: Double,
        completion: @escaping HTTPClientCompletion
    )
}

public class HTTPClient<ConcreteEndpoint: HTTPEndpoint>: HTTPClientProtocol {
    private lazy var serialQueue = DispatchQueue(label: "\(queueName).serial", qos: .background)
    
    private lazy var parallelQueue = DispatchQueue(
        label: "\(queueName).parallel", qos: .background, attributes: .concurrent
    )

    private let queueName: String
    
    private let router: HTTPRouter<ConcreteEndpoint>
    
    public init(queueName name: String, with concreteRouter: HTTPRouter<ConcreteEndpoint>) {
        queueName = name
        router = concreteRouter
    }
    
    public func fetchSync(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        completion: @escaping HTTPClientCompletion
    ) {
        selectQueue(from: queueType).sync {
            self.fetch(endpoint, completion: completion)
        }
    }
    
    public func fetchSyncAfter(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        after delayInSeconds: Double,
        completion: @escaping HTTPClientCompletion
    ) {
        selectQueue(from: queueType).sync {
            Thread.sleep(forTimeInterval: delayInSeconds)
            self.fetch(endpoint, completion: completion)
        }
    }
    
    public func fetchAsync(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        completion: @escaping HTTPClientCompletion
    ) {
        selectQueue(from: queueType).async {
            self.fetch(endpoint, completion: completion)
        }
    }
    
    public func fetchAsyncAfter(
        _ endpoint: ConcreteEndpoint,
        on queueType: HTTPClientQueue,
        after delayInSeconds: Double,
        completion: @escaping HTTPClientCompletion
    ) {
        selectQueue(from: queueType).asyncAfter(deadline: .now() + delayInSeconds) {
            self.fetch(endpoint, completion: completion)
        }
    }
    
    private func fetch(_ endpoint: ConcreteEndpoint, completion: @escaping HTTPClientCompletion) {
        router.resume(endpoint) { (data, response, error) in
            if error != nil {
                return completion(.failure(.connectionError))
            }
            guard let response = response as? HTTPURLResponse else {
                return completion(.failure(.unknownError))
            }
            
            switch self.checkStatusMiddleware(response) {
                case .failure(let error):
                    return completion(.failure(error))
                case .success(_):
                    guard let data = data else {
                        return completion(.failure(.emptyDataError))
                    }
                    return completion(.success(data))
            }
        }
    }
    
    private func checkStatusMiddleware(_ response: HTTPURLResponse) -> HTTPClientResult {
        switch response.statusCode {
            case 200...299:
                return .success(nil)
            case 401...500:
                return .failure(.authError)
            case 501...599:
                return .failure(.requestError)
            default:
                return .failure(.unknownError)
        }
    }
    
    private func selectQueue(from queueType: HTTPClientQueue) -> DispatchQueue {
        switch queueType {
            case .serial:
                return serialQueue
            case .parallel:
                return parallelQueue
        }
    }
}
