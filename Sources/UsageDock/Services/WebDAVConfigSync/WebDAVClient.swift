import Foundation

/// 极简 WebDAV 客户端:只实现配置同步需要的 MKCOL / PUT / GET / HEAD。
/// 强制 HTTPS;Basic 认证承载坚果云等服务的「第三方应用密码」。
/// 无 cookie 持久化、无缓存、不跟随重定向(避免凭证被带到别的域)。
struct WebDAVClient: Sendable {
    enum ClientError: LocalizedError {
        case notHTTPS
        case invalidURL
        case authRejected
        case notFound
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .notHTTPS:
                return L10n.text("webdav.error.not_https")
            case .invalidURL:
                return L10n.text("webdav.error.invalid_url")
            case .authRejected:
                return L10n.text("webdav.error.auth_rejected")
            case .notFound:
                return L10n.text("webdav.error.not_found")
            case .httpError(let status):
                return L10n.format("webdav.error.http_status", status)
            }
        }
    }

    let baseURL: URL
    let account: String
    let password: String

    init(baseURL: URL, account: String, password: String) throws {
        guard baseURL.scheme?.lowercased() == "https" else { throw ClientError.notHTTPS }
        self.baseURL = baseURL
        self.account = account
        self.password = password
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }

    /// remotePath 为相对路径段,如 ["tokenremain-sync", "default", "config.json"]。
    func resourceURL(_ remotePath: [String]) throws -> URL {
        var url = baseURL
        for segment in remotePath {
            guard !segment.isEmpty,
                  !segment.contains("/"),
                  segment != ".", segment != "..",
                  segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) == segment
            else { throw ClientError.invalidURL }
            url.append(path: segment)
        }
        return url
    }

    /// 测试连接:对服务器根做 PROPFIND。207/200/404 都算连通且鉴权通过
    /// (404 只是远端目录尚未创建,上传时会补建)。
    func testConnection() async throws {
        let (_, response) = try await perform(method: "PROPFIND", url: baseURL, extraHeaders: ["Depth": "0"])
        switch response.statusCode {
        case 200...299, 404:
            return
        case 401, 403:
            throw ClientError.authRejected
        default:
            throw ClientError.httpError(response.statusCode)
        }
    }

    func upload(data: Data, remotePath: [String]) async throws {
        // 逐级 MKCOL 建目录;405(已存在)与 201/200 都算成功。
        var directories: [String] = []
        for segment in remotePath.dropLast() {
            directories.append(segment)
            let (_, response) = try await perform(method: "MKCOL", url: resourceURL(directories))
            switch response.statusCode {
            case 200...299, 405:
                continue
            case 401, 403:
                throw ClientError.authRejected
            default:
                throw ClientError.httpError(response.statusCode)
            }
        }
        let (_, response) = try await perform(
            method: "PUT",
            url: resourceURL(remotePath),
            body: data,
            contentType: "application/json; charset=utf-8"
        )
        switch response.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw ClientError.authRejected
        default:
            throw ClientError.httpError(response.statusCode)
        }
    }

    func download(remotePath: [String]) async throws -> Data {
        let (data, response) = try await perform(method: "GET", url: resourceURL(remotePath))
        switch response.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ClientError.authRejected
        case 404:
            throw ClientError.notFound
        default:
            throw ClientError.httpError(response.statusCode)
        }
    }

    private func perform(
        method: String,
        url: URL,
        body: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let credentials = Data("\(account):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
