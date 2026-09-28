import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/view_models/billing_view_model.dart';
import 'package:pomodoist/ui/billing/widgets/billing_paywall.dart';
import 'package:pomodoist/ui/onboarding/view_models/onboarding_view_model.dart';

class LaunchOfferPaywall extends ConsumerStatefulWidget {
  const LaunchOfferPaywall({
    super.key,
    this.compact = false,
    this.onClose,
    this.showPlansWhenActive = false,
  });

  final bool compact;
  final bool showPlansWhenActive;
  final VoidCallback? onClose;

  @override
  ConsumerState<LaunchOfferPaywall> createState() => _LaunchOfferPaywallState();
}

class _LaunchOfferPaywallState extends ConsumerState<LaunchOfferPaywall> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingViewModelProvider);
    final billing = ref.watch(billingViewModelProvider);
    final now = ref.read(onboardingViewModelProvider.notifier).now();
    final serverOwned =
        ref.watch(billingChannelProvider) == BillingChannel.stripe &&
        ref.watch(billingSignedInProvider);
    final remaining = serverOwned
        ? stripeLaunchOfferRemaining(
            now: now,
            endsAt: billing.stripeLaunchOfferEndsAt,
          )
        : launchOfferRemaining(
            now: now,
            startedAt: onboarding.launchOfferStartedAt,
          );
    final offerActive =
        remaining > Duration.zero &&
        (!serverOwned || billing.stripeLaunchOfferEligible);
    return BillingPaywall(
      compact: widget.compact,
      showPlansWhenActive: widget.showPlansWhenActive,
      onClose: widget.onClose,
      launchOfferMode: offerActive,
      launchOfferTimerLabel: offerActive
          ? formatLaunchOfferRemaining(remaining)
          : null,
    );
  }
}
