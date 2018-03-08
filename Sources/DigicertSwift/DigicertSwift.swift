import Dispatch
import Foundation

public enum DigicertError: Error {
    case eventParsingError
}

public struct Page: Codable {
    public let total: Int
    public let limit: Int
    public let offset: Int
}

public struct Product: Codable {
    public let name_id: String
    public let name: String
    public let type: String
}

public struct Container: Codable {
    public let id: Int
    public let name: String
}

public struct Organization: Codable {
    public let id: Int
    public let name: String
}

public struct Certificate: Codable {
    public let common_name: String?
    public let dns_names: [String]?
    public let valid_till: String //TODO DateFormatter
    public let signature_hash: String
}

public struct Order: Codable {
    public let id: Int
    public let certificate: Certificate
    public let status: String
    public let date_created: Date
    public let organization: Organization
    public let validity_years: Int
    public let container: Container
    public let product: Product
    public let price: Float?
}

public struct Orders: Codable {
    public let orders: [Order]
    public let page: Page
}

public struct DigicertSwift {
    let baseDomain = "https://www.digicert.com/services/v2/"
    let authHeader = "X-DC-DEVKEY"
    let sema = DispatchSemaphore(value: 0)
    let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    func submitRequest(path: String,
                       parameters: [String:String] = [:],
                       method: String = "GET",
                       debug: Bool = false) -> Data? {
        var response: Data? = nil
        var requestString = "\(baseDomain)/\(path)"

        for (key, value) in parameters {
            requestString.append("&\(key)=\(value)")
        }

        if let requestURL = URL(string: requestString) {
            let session = URLSession(configuration: URLSessionConfiguration.default)
            var request = URLRequest(url: requestURL)

            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: authHeader)
            let task = session.dataTask(with: request) {
                if let responded = $1 as? HTTPURLResponse {
                    if responded.statusCode != 200 {
                        print("Non-200 response was: \(responded)")
                    }
                    if let responseError = $2 {
                        if debug {
                            print("Error: \(responseError)")
                            print("Code: \(responseError._code)")
                        }
                    }
                    if let data = $0 {
                        response = data
                    }
                }
                self.sema.signal()
            }
            task.resume()
            sema.wait()
        }
        return response
    }

    /**
     List all certificate orders

     https://www.digicert.com/services/v2/documentation/order/order-list
     */
    public func listOrders() throws -> [Order]? {
        var orders: [Order]? = nil

        if let response = submitRequest(path: "order/certificate", debug: true) {
            do {
                let decoder = JSONDecoder()
                if #available(OSX 10.12, *) {
                    decoder.dateDecodingStrategy = .iso8601
                } else {
                    print("Sorry")
                    return nil
                }
                orders = try decoder.decode(Orders.self, from: response).orders
            } catch {
                print("Could not parse events: \(error)")
                throw DigicertError.eventParsingError
            }
        }

        return orders
    }
}
