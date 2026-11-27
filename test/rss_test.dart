import 'dart:convert';
import 'dart:typed_data';

import 'package:deer/core/rss_models.dart';
import 'package:deer/rss/rss_fetcher.dart';
import 'package:deer/rss/rss_importer.dart';
import 'package:deer/rss/rss_parser.dart';
import 'package:deer/ui/widgets/rss_html_body.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RssParser', () {
    test('reads RSS 2.0 namespaced content, creator and media thumbnail', () {
      final feed = RssParser.parse(
        '''
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>示例周刊</title>
    <link>https://example.com</link>
    <item>
      <guid isPermaLink="false">tag:example,2025:1</guid>
      <title>  一周要闻  </title>
      <link>/news/1</link>
      <dc:creator>张三</dc:creator>
      <pubDate>Tue, 25 Nov 2025 08:00:00 GMT</pubDate>
      <description>纯文本摘要</description>
      <content:encoded>&lt;p&gt;正文&lt;em&gt;重点&lt;/em&gt;&lt;/p&gt;</content:encoded>
      <media:thumbnail url="https://cdn.example.com/a.jpg"/>
    </item>
  </channel>
</rss>
''',
        feedId: 7,
        baseUrl: 'https://example.com/feed.xml',
      );
      expect(feed, isNotNull);
      expect(feed!.feedType, 'rss2');
      expect(feed.title, '示例周刊');
      expect(feed.siteUrl, 'https://example.com');
      final article = feed.articles.single;
      expect(article.feedId, 7);
      expect(article.title, '一周要闻');
      expect(article.guid, 'tag:example,2025:1');
      expect(article.link, 'https://example.com/news/1');
      expect(article.author, '张三');
      expect(article.imageUrl, 'https://cdn.example.com/a.jpg');
      expect(article.summary, '纯文本摘要');
      expect(article.content, contains('<em>重点</em>'));
      expect(article.publishedAt?.toUtc().day, 25);
    });

    test('falls back to inline images and strips tags for the summary', () {
      final feed = RssParser.parse(
        '''
<rss version="2.0"><channel><title>t</title>
<item><title>a</title><link>https://e.com/a</link>
<description>&lt;p&gt;看这里 &lt;img src="https://e.com/p.png"&gt;&lt;/p&gt;</description>
</item></channel></rss>
''',
      );
      final article = feed!.articles.single;
      expect(article.imageUrl, 'https://e.com/p.png');
      expect(article.summary, '看这里');
      expect(article.summary, isNot(contains('<')));
    });

    test('reads Atom entries with alternate link and author name', () {
      final feed = RssParser.parse(
        '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Notes</title>
  <link rel="self" href="https://blog.example.com/atom"/>
  <link href="https://blog.example.com"/>
  <entry>
    <id>urn:uuid:1</id>
    <title>Hello</title>
    <link rel="alternate" href="../posts/hello"/>
    <updated>2025-11-24T10:00:00Z</updated>
    <author><name>Liu</name></author>
    <summary>Short</summary>
    <content type="html">&lt;p&gt;Body&lt;/p&gt;</content>
  </entry>
</feed>
''',
        baseUrl: 'https://blog.example.com/feed/atom',
      );
      expect(feed!.feedType, 'atom');
      expect(feed.siteUrl, 'https://blog.example.com');
      final article = feed.articles.single;
      expect(article.link, 'https://blog.example.com/posts/hello');
      expect(article.author, 'Liu');
      expect(article.summary, 'Short');
      expect(article.content, '<p>Body</p>');
      expect(article.publishedAt?.toUtc().hour, 10);
    });

    test('reads JSON Feed 1.1 items', () {
      final feed = RssParser.parse(jsonEncode({
        'version': 'https://jsonfeed.org/version/1.1',
        'title': 'Daily',
        'home_page_url': 'https://daily.example',
        'items': [
          {
            'url': 'https://daily.example/1',
            'title': 'One',
            'content_html': '<p>Hi</p>',
            'image': 'https://daily.example/1.png',
            'date_published': '2025-11-23T00:00:00Z',
            'authors': [
              {'name': 'Wang'}
            ],
          },
          {'id': '2', 'content_text': 'Plain only'},
        ],
      }));
      expect(feed!.feedType, 'json');
      expect(feed.articles.length, 2);
      expect(feed.articles.first.title, 'One');
      expect(feed.articles.first.imageUrl, 'https://daily.example/1.png');
      expect(feed.articles.last.summary, 'Plain only');
      expect(feed.articles.last.guid, '2');
    });

    test('rejects bodies that are not feeds', () {
      expect(RssParser.parse('   '), isNull);
      expect(RssParser.parse('<html><body>nope</body></html>'), isNull);
      expect(RssParser.parse('{"items": "not a list"}')!.articles, isEmpty);
    });

    test('caps articles per feed', () {
      final items = List.generate(
        RssParser.maxArticlesPerFeed + 5,
        (i) => '<item><title>$i</title><link>https://e.com/$i</link></item>',
      ).join();
      final feed = RssParser.parse('<rss><channel><title>t</title>$items</channel></rss>');
      expect(feed!.articles.length, RssParser.maxArticlesPerFeed);
    });
  });

  group('RssFetcher decoding', () {
    test('honours the charset from the content type', () {
      final gbk = Uint8List.fromList([0xC4, 0xE3, 0xBA, 0xC3]);
      expect(RssFetcher.decodeBody(gbk, 'text/xml; charset=gbk'), '你好');
    });

    test('prefers the xml declaration over a latin-1 default', () {
      final bytes = Uint8List.fromList(utf8.encode('<?xml version="1.0" encoding="UTF-8"?><rss>中文</rss>'));
      final text = RssFetcher.decodeBody(bytes, null);
      expect(text, contains('中文'));
    });
  });

  group('RssExchange', () {
    test('exports nested folders and reads them back', () {
      final tech = FeedSource(id: 1, title: 'Tech', url: 'https://e.com/tech.xml');
      final news = FeedSource(id: 2, title: 'News', url: 'https://e.com/news.xml');
      final loose = FeedSource(id: 3, title: 'Loose', url: 'https://e.com/loose.xml');
      final folder = RssFolder(id: 10, name: '科技');
      final opml = RssExchange.exportOpml(
        [tech, news, loose],
        [folder],
        {10: [tech, news]},
      );
      expect(opml, contains('<opml version="2.0">'));
      final parsed = RssExchange.parseOpml(opml);
      expect(parsed.sources.length, 3);
      expect(parsed.folders.map((f) => f.name), containsAll(['科技']));
      expect(parsed.folders.firstWhere((f) => f.name == '科技').urls,
          containsAll(['https://e.com/tech.xml', 'https://e.com/news.xml']));
    });

    test('csv round trip keeps the folder column', () {
      final source = FeedSource(
        id: 1,
        title: 'A, B',
        url: 'https://e.com/a.xml',
        siteUrl: 'https://e.com',
        feedType: 'atom',
      );
      final csv = RssExchange.exportCsv([source], folderOf: {source.url: '阅读'});
      expect(csv, contains('"A, B"'));
      final back = RssExchange.parseCsv(csv);
      expect(back.single.title, 'A, B');
      expect(back.single.feedType, 'atom');
      expect(back.single.url, 'https://e.com/a.xml');
    });
  });

  group('splitRssHtml', () {
    test('pulls images into their own block and keeps order', () {
      final blocks = splitRssHtml(
        '<p>前面</p><p>中间 <img src="/img/a.png" alt="a"></p><p>后面</p>',
        baseUrl: 'https://e.com/post/1',
      );
      expect(blocks.length, 3);
      expect((blocks[0] as RssTextBlock).html, contains('前面'));
      expect((blocks[0] as RssTextBlock).html, contains('中间'));
      expect((blocks[1] as RssImageBlock).url, 'https://e.com/img/a.png');
      expect((blocks[2] as RssTextBlock).html, contains('后面'));
    });

    test('drops images without a usable src', () {
      final blocks = splitRssHtml('<p>hi <img src=""></p>');
      expect(blocks.whereType<RssImageBlock>(), isEmpty);
      expect((blocks.single as RssTextBlock).html, contains('hi'));
    });

    test('keeps plain summaries as one text block', () {
      final blocks = splitRssHtml('只有一段摘要');
      expect(blocks.single, isA<RssTextBlock>());
    });

    test('resolves lazy-load attributes', () {
      final blocks = splitRssHtml(
        '<img data-src="https://cdn.e.com/lazy.jpg">',
      );
      expect((blocks.single as RssImageBlock).url, 'https://cdn.e.com/lazy.jpg');
    });
  });

  group('RssArticle', () {
    test('sorts by published time and falls back to created time', () {
      final created = DateTime.utc(2025, 11, 1);
      final noDate = RssArticle(
        feedId: 1,
        title: 'a',
        createdAt: created,
      );
      final dated = RssArticle(
        feedId: 1,
        title: 'b',
        publishedAt: created.add(const Duration(days: 2)),
        createdAt: created,
      );
      expect(noDate.sortAt, created);
      expect(dated.sortAt.isAfter(created), isTrue);
      expect(dated.copyWith(isRead: true).isRead, isTrue);
      expect(dated.copyWith().title, 'b');
    });

    test('folder avatar uses the first visible character', () {
      final feed = FeedSource(id: 1, title: '  阮一峰', url: 'https://e.com');
      expect(feed.avatarText, '阮');
      expect(feed.hostName, 'e.com');
    });
  });
}
