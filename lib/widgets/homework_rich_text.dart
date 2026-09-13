import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../utils/html_content.dart';
import 'content_image.dart';
import '../utils/app_font.dart';

class HomeworkRichText extends StatelessWidget {
  final String html;
  final TextStyle? textStyle;
  const HomeworkRichText(this.html, {super.key, this.textStyle});

  @override
  Widget build(BuildContext context) {
    final style = appFont(
      context,
      textStyle: Theme.of(context).textTheme.bodyLarge!.merge(textStyle),
    );
    return SelectionArea(
      child: HtmlWidget(
        prepareHomeworkHtml(html),
        baseUrl: eSchoolContentBase,
        textStyle: style,
        onTapUrl: (url) async {
          final uri = contentUri(url);
          var opened = false;
          if (uri != null) {
            try {
              opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            } catch (_) {}
          }
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.linkOpenError,
                  style: appFont(context),
                ),
              ),
            );
          }
          return true;
        },
        // html, включая code и pre, должен использовать выбранный шрифт приложения
        customStylesBuilder: (element) => {
          'font-family': '"${style.fontFamily}"',
          if (element.localName == 'table') 'border-collapse': 'collapse',
        },
        customWidgetBuilder: (element) {
          if (element.localName == 'img') {
            final uri = contentUri(element.attributes['src']);
            return uri == null
                ? const SizedBox.shrink()
                : ContentImage(uri: uri, label: element.attributes['alt']);
          }
          final tex = element.attributes['data-tex'];
          if (tex == null) return null;
          final display = element.attributes['data-display'] == 'true';
          final formula = Math.tex(
            tex,
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: style,
            onErrorFallback: (_) =>
                Text(tex, style: appFont(context, textStyle: style)),
          );
          final scrollable = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: formula,
            ),
          );
          return display ? scrollable : InlineCustomWidget(child: scrollable);
        },
      ),
    );
  }
}
