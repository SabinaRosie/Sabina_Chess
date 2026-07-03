import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../utils/app_logger.dart';

/// Service to manage Rewarded Ads using Google AdMob.
///
/// Usage:
///   await RewardAdService.initialize();          // Call once at app start
///   RewardAdService.loadAd();                     // Pre-load an ad
///   RewardAdService.showAd(onRewardEarned: () {}); // Show & handle reward
class RewardAdService {
  static RewardedAd? _rewardedAd;
  static bool _isLoading = false;

  // ── AdMob Test Ad Unit ID (Rewarded Video) ──
  // Replace with your REAL Ad Unit ID before publishing to the Play Store.
  static const String _adUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// Initialize the Mobile Ads SDK. Call this once in main.dart.
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    AppLogger.i('[RewardAd] Mobile Ads SDK initialized');
    loadAd(); // Pre-load the first ad
  }

  /// Load a rewarded ad into memory so it's ready to show instantly.
  static void loadAd() {
    if (_rewardedAd != null || _isLoading) return; // Already loaded or loading

    _isLoading = true;
    AppLogger.d('[RewardAd] Loading ad...');

    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          AppLogger.i('[RewardAd] Ad loaded successfully');
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          AppLogger.e('[RewardAd] Failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Whether a rewarded ad is ready to be shown.
  static bool get isAdReady => _rewardedAd != null;

  /// Show the rewarded ad. Calls [onRewardEarned] when the user
  /// successfully watches the full ad and earns a reward.
  static void showAd({required Function onRewardEarned}) {
    if (_rewardedAd == null) {
      AppLogger.w('[RewardAd] No ad loaded. Loading now...');
      loadAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        AppLogger.d('[RewardAd] Ad dismissed');
        ad.dispose();
        _rewardedAd = null;
        loadAd(); // Pre-load the next ad immediately
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AppLogger.e('[RewardAd] Failed to show: ${error.message}');
        ad.dispose();
        _rewardedAd = null;
        loadAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        AppLogger.i('[RewardAd] User earned reward: ${reward.amount} ${reward.type}');
        onRewardEarned();
      },
    );
  }
}
