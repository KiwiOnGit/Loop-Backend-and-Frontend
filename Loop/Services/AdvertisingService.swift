import Foundation

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class AdvertisingService {
    static let shared = AdvertisingService()

    private var didConfigureGoogleAds = false

    private init() {}

    func configure() {
        configureGoogleMobileAds()
    }

    private func configureGoogleMobileAds() {
        guard !didConfigureGoogleAds else {
            return
        }
        didConfigureGoogleAds = true

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start()
        #endif
    }
}
