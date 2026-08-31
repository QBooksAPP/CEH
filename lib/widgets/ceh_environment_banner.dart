import 'package:flutter/material.dart';

import '../core/app_environment.dart';
import '../core/ceh_theme.dart';

class CehEnvironmentBanner extends StatelessWidget {
  const CehEnvironmentBanner({
    super.key,
    required this.environment,
    required this.child,
  });

  final CehAppEnvironment environment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!environment.isStaging) return child;

    return Column(
      children: [
        Material(
          color: CehTheme.ink,
          child: SafeArea(
            bottom: false,
            child: const SizedBox(
              width: double.infinity,
              height: 30,
              child: Center(
                child: Text(
                  'STAGING',
                  key: ValueKey('ceh-staging-indicator'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
