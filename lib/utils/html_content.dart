import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

final eSchoolContentBase = Uri.parse('https://app.eschool.center/');

Uri? contentUri(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = Uri.tryParse(value.trim());
  if (parsed == null) return null;
  final uri = eSchoolContentBase.resolveUri(parsed);
  if (!{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

String plainTextToHtml(String text) =>
    const HtmlEscape().convert(text).replaceAll('\n', '<br>');

String htmlToPlainText(String source) {
  final fragment = parser.parseFragment(source);
  for (final node in fragment.querySelectorAll('script,style,template')) {
    node.remove();
  }
  for (final node in fragment.querySelectorAll('.ql-formula')) {
    node.text = node.attributes['data-value'] ?? node.text;
  }
  for (final node in fragment.querySelectorAll('img')) {
    final label = node.attributes['alt'];
    if (label != null) node.replaceWith(Text(label));
  }
  for (final node in fragment.querySelectorAll('br,p,div,li,tr,h1,h2,h3')) {
    node.append(Text('\n'));
  }
  return fragment.text
      .toString()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String prepareHomeworkHtml(String source) {
  final fragment = parser.parseFragment(source);
  for (final node in fragment.querySelectorAll(
    'script,style,iframe,object,embed,link,template',
  )) {
    node.remove();
  }
  for (final node in fragment.querySelectorAll('*')) {
    node.attributes.removeWhere((key, _) => key.toString().startsWith('on'));
    // картинки и ссылки обрабатываем сами, чтобы не открыть локальный файл из разметки
    node.attributes.remove('srcset');
    node.attributes.remove('background');
    node.attributes.remove('color');
    node.attributes.remove('face');
    node.attributes.remove('bgcolor');
    final style = node.attributes['style'];
    if (style != null) {
      node.attributes['style'] = style
          .split(';')
          .where(
            (part) =>
                !part.toLowerCase().contains('url(') &&
                !RegExp(
                  r'^\s*(color|background|background-color|font|font-family)\s*:',
                  caseSensitive: false,
                ).hasMatch(part),
          )
          .join(';');
    }
    if (node.localName == 'a') {
      final uri = contentUri(node.attributes['href']);
      if (uri == null) {
        node.attributes.remove('href');
      } else {
        node.attributes['href'] = uri.toString();
      }
    }
    if (node.localName == 'img') {
      final uri = contentUri(node.attributes['src']);
      if (uri == null) {
        node.remove();
      } else {
        node.attributes['src'] = uri.toString();
      }
    }
    if (node.classes.contains('ql-formula')) {
      node.attributes['data-tex'] = node.attributes['data-value'] ?? node.text;
      node.nodes.clear();
    } else if (node.classes.contains('math-tex')) {
      node.attributes['data-tex'] = _unwrapMath(node.text);
      node.nodes.clear();
    }
  }
  final expressions = RegExp(
    r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)',
  );
  void replaceMath(Node parent) {
    for (final node in parent.nodes.toList()) {
      if (node is Text) {
        final matches = expressions.allMatches(node.data).toList();
        if (matches.isEmpty) continue;
        var offset = 0;
        for (final match in matches) {
          parent.insertBefore(
            Text(node.data.substring(offset, match.start)),
            node,
          );
          final math = Element.tag('span')
            ..attributes['data-tex'] =
                match.group(1) ?? match.group(2) ?? match.group(3)!
            ..attributes['data-display'] = match.group(3) == null
                ? 'true'
                : 'false';
          parent.insertBefore(math, node);
          offset = match.end;
        }
        parent.insertBefore(Text(node.data.substring(offset)), node);
        node.remove();
      } else if (node is Element &&
          !{'code', 'pre'}.contains(node.localName) &&
          !node.attributes.containsKey('data-tex')) {
        replaceMath(node);
      }
    }
  }

  replaceMath(fragment);
  return fragment.outerHtml;
}

String _unwrapMath(String source) {
  final text = source.trim();
  for (final pair in [(r'\(', r'\)'), (r'\[', r'\]'), (r'$$', r'$$')]) {
    if (text.startsWith(pair.$1) && text.endsWith(pair.$2)) {
      return text.substring(pair.$1.length, text.length - pair.$2.length);
    }
  }
  return text;
}
