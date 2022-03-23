import XCTest
@testable import HTTPModule

final class HTTPModuleTests: XCTestCase {
    var baseURL: URL {
        URL(string: "https://google.com")!
    }
    
    func test_HTTPParametersJSONEncoder_ShouldThrow() throws {
        // Arrange
        var request = URLRequest(url: baseURL)
        
        // Act
        
        // Assert
        XCTAssertThrowsError(
            try HTTPParametersJSONEncoder.encode(
                &request,
                with: [
                    "query": NSObject()
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as! HTTPParametersEncoderError,
                HTTPParametersEncoderError.failedToEncode
            )
        }
    }
    
    func test_HTTPParametersJSONEncoder_EqualParams() throws {
        // Arrange
        var request = URLRequest(url: baseURL)
        
        let params: HTTPParameters = ["query": 1]
        
        let serialized = try? JSONSerialization.data(withJSONObject: params)
        
        // Act
        try? HTTPParametersJSONEncoder.encode(&request, with: params)
        
        // Assert
        XCTAssertEqual(request.httpBody, serialized)
    }
    
    func test_HTTPParametersJSONEncoder_NotEqualParams() throws {
        // Arrange
        var request = URLRequest(url: baseURL)
        
        let serialized = try? JSONSerialization.data(withJSONObject: ["query": 2])
        
        // Act
        try? HTTPParametersJSONEncoder.encode(&request, with: ["query": 1])
        
        // Assert
        XCTAssertNotEqual(request.httpBody, serialized)
    }
    
    func test_HTTPParametersURLEncoder_EqualParams() throws {
        // Arrange
        var request = URLRequest(url: baseURL)
        
        let params: HTTPParameters = ["query": 1]
        
        let estimatedURL = URL(string: "\(baseURL)?query=1")
        
        // Act
        try? HTTPParametersURLEncoder.encode(&request, with: params)
        
        // Assert
        XCTAssertEqual(estimatedURL, request.url)
    }
    
    func test_HTTPParametersURLEncoder_NotEqualParams() throws {
        // Arrange
        var request = URLRequest(url: baseURL)
        
        let params: HTTPParameters = ["query": 1]
        // Act
        try? HTTPParametersURLEncoder.encode(&request, with: params)
        
        // Assert
        XCTAssertNotEqual(baseURL, request.url)
    }
    
    func test_HTTPParametersEncoding_CallJSONEncoderEquals() throws {
        // Arrange
        let encoder: HTTPParametersEncoding = .json
        
        var request1 = URLRequest(url: baseURL)
        var request2 = URLRequest(url: baseURL)
        
        let params: HTTPParameters = ["query": 1]
        
        // Act
        try? HTTPParametersJSONEncoder.encode(&request1, with: params)
        try? encoder.encode(request: &request2, bodyParams: params, urlParams: nil)
        
        // Assert
        XCTAssertEqual(request1.httpBody, request2.httpBody)
    }
    
    func test_HTTPParametersEncoding_CallURLEncoderEquals() throws {
        // Arrange
        let encoder: HTTPParametersEncoding = .url
        
        var request1 = URLRequest(url: baseURL)
        var request2 = URLRequest(url: baseURL)
        
        let params: HTTPParameters = ["query": 1]
        
        // Act
        try? HTTPParametersURLEncoder.encode(&request1, with: params)
        try? encoder.encode(request: &request2, bodyParams: nil, urlParams: params)
        
        // Assert
        XCTAssertEqual(request1.httpBody, request2.httpBody)
    }
    
    func test_HTTPParametersEncoding_CallBothEncoderEquals() throws {
        // Arrange
        let encoder: HTTPParametersEncoding = .both
        
        var request1 = URLRequest(url: baseURL)
        var request2 = URLRequest(url: baseURL)
        
        let urlParams: HTTPParameters = ["query": 1]
        let bodyParams: HTTPParameters = ["data": 2]
        
        // Act
        try? HTTPParametersURLEncoder.encode(&request1, with: urlParams)
        try? HTTPParametersJSONEncoder.encode(&request1, with: bodyParams)
        try? encoder.encode(request: &request2, bodyParams: bodyParams, urlParams: urlParams)
        
        // Assert
        XCTAssertEqual(request1.httpBody, request2.httpBody)
        XCTAssertEqual(request1.url, request2.url)
    }

}
