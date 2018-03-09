import Dispatch
import Foundation

public enum DigicertError: Error {
    case responseParsingError
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
                       body: Data? = nil,
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
            if let requestBody = body {
                request.httpBody = requestBody
                //request.setValue("\(requestBody.)", forHTTPHeaderField: "Content-Length")
            }
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
}

extension DigicertSwift {
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

    /**
     List all certificate orders

     https://www.digicert.com/services/v2/documentation/order/order-list
     */
    public func listOrders() throws -> [Order]? {
        var orders: [Order]? = nil

        if let response = submitRequest(path: "order/certificate") {
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
                print("Could not parse order list: \(error)")
                throw DigicertError.responseParsingError
            }
        }

        return orders
    }
}

extension DigicertSwift {
    enum SignatureHash: String, Codable {
        case sha256, sha384, sha512
    }

    struct ServerPlatform: Codable {
        let id: Int
    }

    struct CertificateRequest: Codable {
        let common_name: String
        let csr: String
        let organization_units: [String]?
        let server_platform: ServerPlatform?
        let signature_hash: SignatureHash
        let profile_option: String?
    }

    struct RequestOrganization: Codable {
        let id: Int
    }

    struct WildcardRequest: Codable {
        let certificate: CertificateRequest
        let organization: RequestOrganization
        let validity_years: Int
        let custom_expiration_date: String? //TODO Make this YYYY-MM-DD format
        let comments: String?
        let disable_renewal_notifications: Bool?
        let renewal_of_order_id: Int?
        let disable_ct: Bool?
    }

    public enum RequestStatus: String, Codable {
        case pending, approved, rejected
    }

    public struct Request: Codable {
        public let id: Int
        public let status: RequestStatus
    }

    public struct WildcardResponse: Codable {
        public let id: Int
        public let requests: [Request]
    }

    /**
     Request a new Wildcard certificate

     [API Documentation](https://www.digicert.com/services/v2/documentation/order/order-ssl-wildcard)

     - parameters
        - name: Title of the event
        - description: Details for the meetup
        - duration: defaults to 3 hours (10800000)
        - startTime: Starting time for event
     */
    public func requestWildcard(commonName: String,
                                csr: String,
                                duration: Int,
                                startTime: Date,
                                venue: Int) throws -> WildcardResponse? {
        let requestOrganization = RequestOrganization(id: 5)
        let certificate = CertificateRequest.init(common_name: commonName, csr: csr, organization_units: nil, server_platform: nil, signature_hash: .sha256, profile_option: nil)
        let request = WildcardRequest(certificate: certificate, organization: requestOrganization, validity_years: 1, custom_expiration_date: nil, comments: nil, disable_renewal_notifications: nil, renewal_of_order_id: nil, disable_ct: nil)
        let body = try JSONEncoder().encode(request)
        print(request)
        print(body)
        return nil/*
        if let response = submitRequest(path: "certificate/ssl_wildcard",
                                        method: "POST",
                                        body: body,
                                        debug: true) {
            do {
                return try JSONDecoder().decode(WildcardResponse.self, from: response)
            } catch {
                print("Couldn't parse response: \(error)")
                throw DigicertError.responseParsingError
            }
        }
        return nil*/
    }
}
