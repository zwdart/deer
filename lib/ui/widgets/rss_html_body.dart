import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'rss_cards.dart';

const String _imgMarker = 'dchat-img-src';

sealed class RssBlock;

/// 一段仍然适合交给 flutter_html 排版的正文。
class RssTextBlock implements RssBlock {
  final String html;

  RssTextBlock(this.html);
}

/// 单独成块的配图，交给整宽的缓存图片组件，避免原始尺寸溢出。
class RssImageBlock implements RssBlock {
  final String url;

  RssImageBlock(this.url);
}

/// 把正文里的图片拆出来单独渲染：flutter_html 3 的图片会按原始尺寸排版，
/// 宽图会溢出，这里统一改成整宽卡片，其余片段仍交给 Html 排版。
List<RssBlock> splitRssHtml(String input, {String? baseUrl}) {
  final blocks = <RssBlock>[];
  late final dom.DocumentFragment fragment;
  try {
    fragment = html_parser.parseFragment(input);
  } catch (_) {
    return [if (input.trim().isNotEmpty) RssTextBlock(input)];
  }

  for (final img in fragment.querySelectorAll('img').toList()) {
    final raw = img.attributes['src'] ??
        img.attributes['data-src'] ??
        img.attributes['data-original'] ??
        '';
    // 顶层节点的 parent 是 DocumentFragment，`parent` 只返回 Element，
    // 这里必须用 parentNode，否则正文开头的图片会被当成无父节点删掉。
    if (raw.trim().isEmpty || img.parentNode == null) {
      img.remove();
      continue;
    }
    img.replaceWith(
      dom.Element.tag(_imgMarker)..attributes['src'] = _absolute(raw, baseUrl),
    );
  }

  final buffer = <dom.Node>[];
  void flush() {
    if (buffer.isEmpty) return;
    // Node.toString() 只是调试表示（文本会带引号、元素只有开标签），
    // 必须交给 html 包的序列化器生成真正的 HTML。
    final wrapper = dom.Element.tag('div');
    wrapper.nodes.addAll(buffer);
    buffer.clear();
    final html = wrapper.innerHtml.trim();
    if (html.isEmpty) return;
    blocks.add(RssTextBlock(html));
  }

  void walk(dom.Node node) {
    if (node is dom.Element) {
      if (node.localName == _imgMarker) {
        flush();
        final url = node.attributes['src'] ?? '';
        if (url.isNotEmpty) blocks.add(RssImageBlock(url));
        return;
      }
      if (node.querySelector(_imgMarker) != null) {
        for (final child in node.nodes.toList()) {
          walk(child);
        }
        return;
      }
    }
    buffer.add(node);
  }

  for (final node in fragment.nodes.toList()) {
    walk(node);
  }
  flush();
  return blocks;
}

String _absolute(String src, String? baseUrl) {
  final uri = Uri.tryParse(src);
  if (uri == null) return src;
  if (uri.hasScheme) return src;
  final base = baseUrl == null ? null : Uri.tryParse(baseUrl);
  if (base == null || !base.hasScheme) return src;
  try {
    return base.resolveUri(uri).toString();
  } catch (_) {
    return src;
  }
}

class RssHtmlBody extends StatelessWidget {
  final String html;
  final String? baseUrl;
  final double fontSize;
  final double lineHeight;
  final bool showImages;

  const RssHtmlBody({
    super.key,
    required this.html,
    required this.fontSize,
    required this.lineHeight,
    this.baseUrl,
    this.showImages = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final blocks = splitRssHtml(html, baseUrl: baseUrl);
    if (blocks.isEmpty) {
      return Text(
        ' ',
        style: TextStyle(fontSize: fontSize, height: lineHeight, color: c.muted),
      );
    }
    final base = Style(
      fontSize: FontSize(fontSize),
      lineHeight: LineHeight(lineHeight),
      color: c.text,
      margin: Margins.zero,
      padding: HtmlPaddings.zero,
    );
    final styles = <String, Style>{
      'body': base,
      'p': base.copyWith(margin: Margins.symmetric(vertical: fontSize * 0.55)),
      'h1': base.copyWith(
        fontSize: FontSize(fontSize * 1.3),
        fontWeight: FontWeight.w700,
        margin: Margins.symmetric(vertical: fontSize * 0.6),
      ),
      'h2': base.copyWith(
        fontSize: FontSize(fontSize * 1.18),
        fontWeight: FontWeight.w700,
        margin: Margins.symmetric(vertical: fontSize * 0.55),
      ),
      'h3': base.copyWith(
        fontSize: FontSize(fontSize * 1.08),
        fontWeight: FontWeight.w600,
        margin: Margins.symmetric(vertical: fontSize * 0.5),
      ),
      'a': base.copyWith(color: c.accent),
      'li': base.copyWith(margin: Margins.symmetric(vertical: fontSize * 0.2)),
      'blockquote': base.copyWith(
        color: c.muted,
        border: Border(left: BorderSide(color: c.accent, width: 3)),
        margin: Margins.symmetric(vertical: fontSize * 0.55),
        padding: HtmlPaddings.only(left: 12),
      ),
      'pre': base.copyWith(
        fontSize: FontSize(fontSize * 0.86),
        backgroundColor: c.panel,
        padding: HtmlPaddings.all(10),
      ),
      'code': base.copyWith(fontSize: FontSize(fontSize * 0.86)),
      'img': base.copyWith(display: Display.none),
    };

    final children = <Widget>[];
    for (final block in blocks) {
      if (block is RssImageBlock) {
        if (!showImages) continue;
        children.add(Padding(
          padding: EdgeInsets.symmetric(vertical: fontSize * 0.6),
          child: DetailImage(url: block.url, radius: 12),
        ));
      } else if (block is RssTextBlock) {
        children.add(
          Html(
            data: block.html,
            style: styles,
            onLinkTap: (url, attributes, element) {
              _openLink(url ?? attributes['href']);
            },
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _openLink(String? link) {
    final value = link;
    if (value == null) return;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
