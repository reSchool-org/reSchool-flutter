import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_font.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.privacyPolicy,
          style: appFont(context,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(context, 
                  colorScheme,
                  title: '1. ${l10n.privacyGeneral}',
                  content: l10n.privacyGeneralText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '2. ${l10n.privacyDataCollected}',
                  content: l10n.privacyDataCollectedText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '3. ${l10n.privacyPurpose}',
                  content: l10n.privacyPurposeText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '4. ${l10n.privacyStorage}',
                  content: l10n.privacyStorageText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '5. ${l10n.privacyThirdParty}',
                  content: l10n.privacyThirdPartyText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '6. ${l10n.privacyRights}',
                  content: l10n.privacyRightsText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '7. ${l10n.privacyDisclaimer}',
                  content: l10n.privacyDisclaimerText,
                ),
                _buildSection(context, 
                  colorScheme,
                  title: '8. ${l10n.privacyChanges}',
                  content: l10n.privacyChangesText,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.privacyLastUpdated,
                  style: appFont(context,
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, ColorScheme colorScheme, {required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: appFont(context,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: appFont(context,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
