public import Alamofire

// Типы Alamofire, входящие в публичный API Gatewire.
// Переэкспортируются, чтобы клиентскому коду было достаточно `import Gatewire`.

public typealias URLConvertible = Alamofire.URLConvertible
public typealias URLRequestConvertible = Alamofire.URLRequestConvertible
public typealias HTTPMethod = Alamofire.HTTPMethod
public typealias HTTPHeaders = Alamofire.HTTPHeaders
public typealias HTTPHeader = Alamofire.HTTPHeader
public typealias MultipartFormData = Alamofire.MultipartFormData
public typealias DataDecoder = Alamofire.DataDecoder
public typealias URLEncodedFormEncoder = Alamofire.URLEncodedFormEncoder
public typealias EventMonitor = Alamofire.EventMonitor
public typealias RequestInterceptor = Alamofire.RequestInterceptor
public typealias RequestAdapter = Alamofire.RequestAdapter
public typealias RequestRetrier = Alamofire.RequestRetrier
public typealias RetryResult = Alamofire.RetryResult
public typealias Request = Alamofire.Request
public typealias Session = Alamofire.Session
public typealias AuthenticationCredential = Alamofire.AuthenticationCredential
public typealias AuthenticationError = Alamofire.AuthenticationError
