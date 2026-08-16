import 'package:flutter/material.dart';

import '../../app_identity.dart';
import '../../visual/visual.dart';

/// In-application identity, source, and rights information.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const noticeKey = ValueKey<String>('about-unofficial-notice');
  static const correctionsKey = ValueKey<String>('about-corrections-route');

  static const unofficialNotice =
      'This is unofficial content which contains copyrighted materials and IP '
      'from Pearl Abyss, and is not official/endorsed content.';

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Semantics(
      container: true,
      label: 'About Black Spirit Life',
      child: ListView(
        key: const ValueKey<String>('about-scroll'),
        primary: false,
        padding: const EdgeInsets.only(right: 4, bottom: 12),
        children: <Widget>[
          SectionHeader(
            title: 'About Black Spirit Life',
            meta: 'Version ${AppIdentity.applicationVersion}',
          ),
          const SizedBox(height: 14),
          AppSurface(
            role: AppSurfaceRole.card,
            tone: AppSurfaceTone.info,
            semanticLabel: 'Required unofficial content notice',
            child: SelectableText(
              unofficialNotice,
              key: noticeKey,
              style: spec.typography.body.copyWith(
                color: spec.palette.text,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AboutCard(
            title: 'Free fan project',
            body:
                'Black Spirit Life is a completely free, noncommercial, '
                'unofficial Windows companion for Black Desert life-skill '
                'planning. It has no sales, subscriptions, paid access, or '
                'commercial licensing.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            title: 'Credits and source links',
            body:
                'Pearl Abyss Fan Content Guidelines\n'
                'https://www.pearlabyss.com/en-US/legal/detail?_policyNo=42\n\n'
                'BDO Codex\nhttps://bdocodex.com/\n\n'
                'Workerman / Shrddr\n'
                'https://github.com/shrddr/workermanjs\n\n'
                'SomethingLovely historical gathering data\n'
                'https://github.com/fffam/blackdesert-somethinglovely-map\n\n'
                'Source links identify provenance; they do not imply '
                'endorsement or a blanket redistribution grant.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            title: 'Code and third-party content',
            body:
                'The Black Spirit Life source-code license covers only '
                'original project code. It does not grant rights in Pearl '
                'Abyss artwork or Black Desert assets, BDO Codex material, '
                'map-provider material, or other third-party datasets and '
                'artwork. Complete notices and asset-source records are kept '
                'with the project.',
          ),
          const SizedBox(height: 12),
          const _AboutCard(
            key: correctionsKey,
            title: 'Corrections and takedown requests',
            body:
                'When the public project repository is configured, use its '
                'Issues tab and choose "Content correction or takedown." '
                'Identify the affected file, record, or screen and the '
                'requested correction or removal. Do not post private '
                'personal information or confidential proof in a public '
                'issue.',
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return AppSurface(
      role: AppSurfaceRole.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: spec.typography.section.copyWith(
              color: spec.palette.text,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: spec.typography.body.copyWith(
              color: spec.palette.text,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
