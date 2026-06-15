import Foundation
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class AdvertisingService: NSObject {
    static let shared = AdvertisingService()

    private enum Config {
        #if DEBUG
        static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
        #else
        static let interstitialAdUnitID = "ca-app-pub-8741346518071399/2001178078"
        #endif
    }

    private var didConfigureGoogleAds = false
    private var isLoadingInterstitial = false
    private var isPresentingInterstitial = false

    #if canImport(GoogleMobileAds)
    private var interstitialAd: InterstitialAd?
    #endif

    private override init() {
        super.init()
    }

    func configure() {
        configureGoogleMobileAds()
    }

    func preloadInterstitial() async {
        #if canImport(GoogleMobileAds)
        guard !isLoadingInterstitial, interstitialAd == nil else {
            return
        }
        isLoadingInterstitial = true
        defer { isLoadingInterstitial = false }
        do {
            let ad = try await InterstitialAd.load(
                with: Config.interstitialAdUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            interstitialAd = ad
        } catch {
            #if DEBUG
            print("Failed to load interstitial ad: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    @discardableResult
    func presentInterstitialIfReady() async -> Bool {
        #if canImport(GoogleMobileAds)
        guard !isPresentingInterstitial else {
            return false
        }
        if interstitialAd == nil {
            await preloadInterstitial()
        }
        guard let ad = interstitialAd else {
            return false
        }
        isPresentingInterstitial = true
        interstitialAd = nil
        ad.present(from: topViewController())
        return true
        #else
        return false
        #endif
    }

    private func configureGoogleMobileAds() {
        guard !didConfigureGoogleAds else {
            return
        }
        didConfigureGoogleAds = true

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start()
        Task {
            await preloadInterstitial()
        }
        #endif
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return topViewController(from: window?.rootViewController)
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = root as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

#if canImport(GoogleMobileAds)
extension AdvertisingService: FullScreenContentDelegate {
    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        #if DEBUG
        print("Interstitial failed to present: \(error.localizedDescription)")
        #endif
        isPresentingInterstitial = false
        Task {
            await preloadInterstitial()
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isPresentingInterstitial = false
        Task {
            await preloadInterstitial()
        }
    }
}
#endif
