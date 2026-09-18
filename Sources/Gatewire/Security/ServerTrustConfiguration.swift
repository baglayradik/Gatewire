public import Alamofire
public import Foundation
internal import Security

/// Проверка сертификата сервера, в том числе закрепление (pinning).
///
/// ```swift
/// let client = APIClient {
///     $0.serverTrust = .pinnedCertificates(hosts: ["api.example.com"])
/// }
/// ```
public struct ServerTrustConfiguration: Sendable {
    let makeManager: @Sendable () -> ServerTrustManager

    /// Закрепляет сертификаты для указанных хостов.
    ///
    /// - Parameters:
    ///   - certificates: Сертификаты для каждого хоста.
    ///   - allHostsMustBeEvaluated: Требовать проверку для всех хостов запросов. По умолчанию `true`:
    ///     запрос к хосту без правила завершится ошибкой.
    public static func pinnedCertificates(
        _ certificates: [String: [SecCertificate]],
        allHostsMustBeEvaluated: Bool = true
    ) -> ServerTrustConfiguration {
        let evaluators = certificates.mapValues { certificates in
            PinnedCertificatesTrustEvaluator(certificates: certificates) as any ServerTrustEvaluating
        }

        return ServerTrustConfiguration {
            ServerTrustManager(allHostsMustBeEvaluated: allHostsMustBeEvaluated, evaluators: evaluators)
        }
    }

    /// Закрепляет для указанных хостов сертификаты из бандла.
    ///
    /// Берутся все файлы `.cer`, `.crt` и `.der` бандла.
    ///
    /// - Parameters:
    ///   - hosts: Хосты, для которых закрепляются сертификаты.
    ///   - bundle: Бандл с сертификатами. По умолчанию `Bundle.main`.
    ///   - allHostsMustBeEvaluated: Требовать проверку для всех хостов запросов. По умолчанию `true`.
    public static func pinnedCertificates(
        hosts: [String],
        in bundle: Bundle = .main,
        allHostsMustBeEvaluated: Bool = true
    ) -> ServerTrustConfiguration {
        let certificates = bundle.af.certificates

        return pinnedCertificates(
            Dictionary(uniqueKeysWithValues: hosts.map { ($0, certificates) }),
            allHostsMustBeEvaluated: allHostsMustBeEvaluated
        )
    }

    /// Закрепляет публичные ключи для указанных хостов.
    ///
    /// Устойчивее к смене сертификата: ключ обычно сохраняется при перевыпуске.
    public static func pinnedPublicKeys(
        _ keys: [String: [SecKey]],
        allHostsMustBeEvaluated: Bool = true
    ) -> ServerTrustConfiguration {
        let evaluators = keys.mapValues { keys in
            PublicKeysTrustEvaluator(keys: keys) as any ServerTrustEvaluating
        }

        return ServerTrustConfiguration {
            ServerTrustManager(allHostsMustBeEvaluated: allHostsMustBeEvaluated, evaluators: evaluators)
        }
    }

    /// Закрепляет для указанных хостов публичные ключи сертификатов из бандла.
    public static func pinnedPublicKeys(
        hosts: [String],
        in bundle: Bundle = .main,
        allHostsMustBeEvaluated: Bool = true
    ) -> ServerTrustConfiguration {
        let keys = bundle.af.publicKeys

        return pinnedPublicKeys(
            Dictionary(uniqueKeysWithValues: hosts.map { ($0, keys) }),
            allHostsMustBeEvaluated: allHostsMustBeEvaluated
        )
    }

    /// Свои правила проверки сертификатов.
    public static func custom(_ manager: ServerTrustManager) -> ServerTrustConfiguration {
        ServerTrustConfiguration { manager }
    }
}
