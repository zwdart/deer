import 'package:xml/xml.dart';

import '../core/rss_models.dart';

class OpmlFolder {
  final String name;
  final List<String> urls;

  OpmlFolder(this.name, this.urls);
}

class OpmlImport {
  final List<FeedSource> sources;
  final List<OpmlFolder> folders;

  const OpmlImport({required this.sources, required this.folders});
}

/// OPML / CSV 订阅交换。
///
/// zebra 的导出是平铺的，文件夹结构会丢失；这里按 `<outline>` 嵌套还原收藏夹：
/// 带 `xmlUrl` 的是订阅源，不带的分组视为文件夹。
class RssExchange {
  RssExchange._();

  static const csvHeader = 'title,url,site_url,feed_type,category,folder';

  static String exportOpml(
    List<FeedSource> sources,
    List<RssFolder> folders,
    Map<int, List<FeedSource>> folderSources,
  ) {
    final buffer = StringBuffer()      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('<head><title>dchat 订阅源</title></head>')
      ..writeln('<body>');

    void outline(FeedSource source, String indent) {
      buffer.writeln(
        '$indent<outline text="${_escape(source.title)}" title="${_escape(source.title)}" '
        'type="rss" xmlUrl="${_escape(source.url)}" htmlUrl="${_escape(source.siteUrl)}"/>',
      );
    }

    final grouped = <String>{};
    for (final folder in folders) {
      final members = folderSources[folder.id] ?? const <FeedSource>[];
      if (members.isEmpty) continue;
      buffer.writeln('  <outline text="${_escape(folder.name)}" '
          'title="${_escape(folder.name)}">');
      for (final source in members) {
        outline(source, '    ');
        grouped.add(source.url);
      }
      buffer.writeln('  </outline>');
    }
    for (final source in sources) {
      if (!grouped.contains(source.url)) outline(source, '  ');
    }
    buffer
      ..writeln('</body>')
      ..writeln('</opml>');
    return buffer.toString();
  }

  static OpmlImport parseOpml(String text) {
    final sources = <FeedSource>[];
    final folders = <OpmlFolder>[];
    final seen = <String>{};

    FeedSource? toSource(XmlElement outline) {
      final url = outline.getAttribute('xmlUrl') ??
          outline.getAttribute('xmlurl') ??
          '';
      if (url.isEmpty) return null;
      final title = outline.getAttribute('title') ??
          outline.getAttribute('text') ??
          '';
      return FeedSource(
        title: title.isNotEmpty ? title : url,
        url: url,
        siteUrl: outline.getAttribute('htmlUrl') ??
            outline.getAttribute('htmlurl') ??
            '',
        feedType: url.toLowerCase().contains('atom') ? 'atom' : 'rss2',
      );
    }

    void walk(XmlElement node, OpmlFolder? folder) {
      for (final child in node.findElements('outline')) {
        final source = toSource(child);
        if (source == null) {
          final name = child.getAttribute('title') ??
              child.getAttribute('text') ??
              '';
          if (name.isEmpty) continue;
          final created = OpmlFolder(name, []);
          folders.add(created);
          walk(child, created);
          continue;
        }
        if (source.url.isEmpty || !seen.add(source.url)) continue;
        sources.add(source);
        folder?.urls.add(source.url);
      }
    }

    try {
      final document = XmlDocument.parse(text);
      for (final body in document.findAllElements('body')) {
        walk(body, null);
      }
    } catch (_) {
      // 已经解析出来的部分仍然可用
    }
    return OpmlImport(sources: sources, folders: folders);
  }

  static String exportCsv(List<FeedSource> sources,
      {Map<String, String> folderOf = const {}}) {
    final buffer = StringBuffer()..writeln(csvHeader);
    for (final s in sources) {
      buffer.writeln([
        s.title,
        s.url,
        s.siteUrl,
        s.feedType,
        s.category,
        folderOf[s.url] ?? '',
      ].map(_csvEscape).join(','));
    }
    return buffer.toString();
  }

  static List<FeedSource> parseCsv(String csv) {
    final sources = <FeedSource>[];
    final seen = <String>{};
    final lines = csv.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    var first = true;
    for (final line in lines) {
      if (first) {
        first = false;
        if (line.toLowerCase().startsWith('title,')) continue;
      }
      final fields = _parseCsvLine(line);
      if (fields.length < 2) continue;
      final url = fields[1].trim();
      if (url.isEmpty || !seen.add(url)) continue;
      sources.add(FeedSource(
        title: fields[0].trim().isEmpty ? url : fields[0].trim(),
        url: url,
        siteUrl: fields.length > 2 ? fields[2].trim() : '',
        feedType: fields.length > 3 && fields[3].trim().isNotEmpty
            ? fields[3].trim()
            : 'rss2',
        category: fields.length > 4 ? fields[4].trim() : '',
      ));
    }
    return sources;
  }

  static String _csvEscape(String value) {
    if (value.isEmpty) return '""';
    if (!RegExp('[",\n]').hasMatch(value)) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c != '"') {
          current.write(c);
        } else if (i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(c);
      }
    }
    fields.add(current.toString());
    return fields;
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
