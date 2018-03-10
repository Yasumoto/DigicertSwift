import Dispatch
import Foundation

public enum DigicertError: Error {
    case responseParsingError
    case networkError(error: DigicertNetworkError)
}

public struct DigicertNetworkError: Error, Codable {
    public let code: String
    public let message: String
}

public struct DigicertNetworkErrors: Codable {
    public let errors: [DigicertNetworkError]
}

public struct DigicertSwift {
    let baseDomain = "https://www.digicert.com/services/v2/"
    let authHeader = "X-DC-DEVKEY"
    let sema = DispatchSemaphore(value: 0)
    let apiKey: String
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public enum RequestStatus: String, Codable {
        case pending, approved, rejected
    }

    public struct Request: Codable {
        public let id: Int
        public let status: RequestStatus
    }

    public struct CertificateSubmissionResponse: Codable {
        public let id: Int
        public let requests: [Request]
    }

    enum SignatureHash: String, Codable {
        case sha256, sha384, sha512
    }

    struct ServerPlatform: Codable {
        let id: Int
    }

    struct RequestOrganization: Codable {
        let id: Int
    }

    /**
     Submit a request to Digicert's API

     - parameters:
        - path: URL path to connect to (this is the API name)
        - queryParameters: Used to build the query string
        - method: Either GET or POST
        - body: sent during a POST request
        - debug: Print out request details
     */
    func submitRequest(path: String,
                       queryParameters: [String:String] = [:],
                       method: String = "GET",
                       body: Data? = nil,
                       debug: Bool = false) -> Data? {
        var response: Data? = nil
        var errorResponse: DigicertNetworkError? = nil
        var requestString = "\(baseDomain)\(path)"
        
        for (key, value) in queryParameters {
            requestString.append("&\(key)=\(value)")
        }
        
        if let requestURL = URL(string: requestString) {
            let session = URLSession(configuration: URLSessionConfiguration.default)
            var request = URLRequest(url: requestURL)
            
            request.httpMethod = method
            if let requestBody = body {
                request.httpBody = requestBody
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: authHeader)
            let task = session.dataTask(with: request) {
                if let responded = $1 as? HTTPURLResponse {
                    if responded.statusCode != 200 && responded.statusCode != 201 {
                        print("Non-200 response was: \(responded)")
                        if let data = $0 {
                            do {
                                let errors = try JSONDecoder().decode(DigicertNetworkErrors.self, from: data)
                                if let error = errors.errors.first {
                                    errorResponse = error
                                }
                            } catch {
                                print("Error decoding Digicert error: \(error)")
                            }
                        }
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
        if let responseError = errorResponse {
            print("Error: \(responseError)")
            return nil
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
    
    public struct OrderOrganization: Codable {
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
        public let organization: OrderOrganization
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
    struct Organization: Codable {
        public let id: Int
        
        private enum CodingKeys: String, CodingKey {
            case id
        }
    }
    
    struct Organizations: Codable {
        public let organizations: [Organization]
    }
    
    /**
     List all organizations associated with this account

     *TODO* Not quite ready for use yet
     
     https://www.digicert.com/services/v2/documentation/organization/organization-list
     */
    private func listOrganizations() throws -> [Organization]? {
        var orders: [Organization]? = nil
        
        if let response = submitRequest(path: "organization", debug: true) {
            do {
                orders = try JSONDecoder().decode(Organizations.self, from: response).organizations
            } catch {
                print("Could not parse organization list: \(error)")
                throw DigicertError.responseParsingError
            }
        }
        
        return orders
    }
    
}

extension DigicertSwift {
    struct WildcardCertificate: Codable {
        let common_name: String
        let csr: String
        let signature_hash: SignatureHash
        let organization_units: [String]? = nil
        let server_platform: ServerPlatform? = nil
        let profile_option: String? = nil
    }

    
    struct WildcardRequest: Codable {
        let certificate: WildcardCertificate
        let organization: RequestOrganization
        let validity_years: Int
        let custom_expiration_date: String? = nil //TODO Make this YYYY-MM-DD format
        let comments: String? = nil
        let disable_renewal_notifications: Bool? = nil
        let renewal_of_order_id: Int? = nil
        let disable_ct: Bool? = nil
    }
    
    /**
     Request a new Wildcard certificate
     
     [API Documentation](https://www.digicert.com/services/v2/documentation/order/order-ssl-wildcard)
     
     - parameters:
        - commonName: Name of the certificate
        - csr: Full Certificate Signing Request as a string
        - organizationId: Get your organization ID from the web UI
        - validityYears: Number of years for the cert to be valid
     */
    public func requestWildcard(commonName: String,
                                csr: String,
                                organizationId: Int,
                                validityYears: Int = 1,
                                debug: Bool = false) throws -> CertificateSubmissionResponse? {
        let requestOrganization = RequestOrganization(id: organizationId)
        let certificate = WildcardCertificate(common_name: commonName, csr: csr, signature_hash: .sha256)
        let request = WildcardRequest(certificate: certificate, organization: requestOrganization, validity_years: validityYears)
        if debug {
            print(request)
        }
        let body = try JSONEncoder().encode(request)
        if let response = submitRequest(path: "order/certificate/ssl_wildcard",
                                        method: "POST",
                                        body: body,
                                        debug: true) {
            do {
                return try JSONDecoder().decode(CertificateSubmissionResponse.self, from: response)
            } catch {
                print("Couldn't parse response: \(error)")
                if let response = String(bytes: response, encoding: .utf8) {
                    print("Response: \(response)")
                }
                throw DigicertError.responseParsingError
            }
        }
        return nil
    }
}

extension DigicertSwift {
    struct CloudCertificate: Codable {
        let common_name: String
        let dns_names: [String]?
        let csr: String
        let signature_hash: SignatureHash
        let organization_units: [String]? = nil
        let server_platform: ServerPlatform? = nil
        let profile_option: String? = nil
    }

    struct CloudRequest: Codable {
        let certificate: CloudCertificate
        let organization: RequestOrganization
        let validity_years: Int
        let custom_expiration_date: String? = nil //TODO Make this YYYY-MM-DD format
        let comments: String? = nil
        let disable_renewal_notifications: Bool? = nil
        let renewal_of_order_id: Int? = nil
        let disable_ct: Bool? = nil
    }

    /**
     Request a new SSL Cloud certificate (with a large list of SANs)

     [API Documentation](https://www.digicert.com/services/v2/documentation/order/order-ssl-cloud-wildcard)

     - parameters:
        - commonName: Name of the certificate
        - sans: Additional domain names to secure
        - csr: Full Certificate Signing Request as a string
        - organizationId: Get your organization ID from the web UI
        - validityYears: Number of years for the cert to be valid
     */
    public func requestCloud(commonName: String,
                             sans: [String],
                             csr: String,
                             organizationId: Int,
                             validityYears: Int = 1,
                             debug: Bool = false) throws -> CertificateSubmissionResponse? {
        let requestOrganization = RequestOrganization(id: organizationId)
        let certificate = CloudCertificate(common_name: commonName, dns_names: sans, csr: csr, signature_hash: .sha256)
        let request = CloudRequest(certificate: certificate, organization: requestOrganization, validity_years: validityYears)
        if debug {
            print(request)
        }
        let body = try JSONEncoder().encode(request)
        if let response = submitRequest(path: "order/certificate/ssl_cloud_wildcard",
                                        method: "POST",
                                        body: body,
                                        debug: true) {
            do {
                return try JSONDecoder().decode(CertificateSubmissionResponse.self, from: response)
            } catch {
                print("Couldn't parse response: \(error)")
                if let response = String(bytes: response, encoding: .utf8) {
                    print("Response: \(response)")
                }
                throw DigicertError.responseParsingError
            }
        }
        return nil
    }
}
