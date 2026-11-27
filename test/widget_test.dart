import 'package:deer/core/helpers.dart';
import 'package:deer/core/models.dart';
import 'package:deer/core/settings.dart';
import 'package:deer/net/frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frame', () {
    test('round-trips a chat frame', () {
      final frame = Frame(
        type: typeChat,
        from: 'u_alice',
        to: 'u_bob',
        id: 'm_1',
        time: 1700000000000,
        data: {
          'message': {'id': 'm_1', 'kind': 'text', 'text': 'hello'},
        },
      );
      final encoded = frame.encodeLine();
      expect(encoded.endsWith('\n'), isTrue);
      final decoded = Frame.decode(encoded.trim());
      expect(decoded.v, protoVersion);
      expect(decoded.type, typeChat);
      expect(decoded.from, 'u_alice');
      expect(decoded.to, 'u_bob');
      expect(decoded.id, 'm_1');
      expect(decoded.time, 1700000000000);
      expect(decoded.dataMap?['message']['text'], 'hello');
    });

    test('rejects mismatched protocol versions', () {
      expect(
        () => Frame.fromJson({
          'v': protoVersion + 1,
          'type': typePing,
          'from': 'u_alice',
        }),
        throwsFormatException,
      );
    });

    test('rejects frames without a type', () {
      expect(
        () => Frame.fromJson({'v': protoVersion, 'from': 'u_alice'}),
        throwsFormatException,
      );
    });
  });

  group('helpers', () {
    test('share token parsing only accepts /t/<hex>', () {
      const token = '0123456789abcdef0123456789abcdef';
      expect(
        shareTokenFromUrl('http://192.168.1.2:42230/t/$token/photo.png'),
        token,
      );
      expect(
        shareTokenFromUrl('http://192.168.1.2:42230/t/not-a-token/photo.png'),
        isNull,
      );
      expect(shareTokenFromUrl('http://192.168.1.2:42230/health'), isNull);
    });

    test('sanitizes file names', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName('a:b*c?.txt'), 'a_b_c_.txt');
      expect(sanitizeFileName('..'), 'file');
      expect(sanitizeFileName(''), 'file');
    });

    test('truncates by runes and appends ellipsis', () {
      expect(truncateRunes('hello', 5), 'hello');
      expect(truncateRunes('hello!', 5), 'hello…');
      expect(truncateRunes('你好世界', 2), '你好…');
    });

    test('rfc3339 timestamps round-trip with milliseconds', () {
      final time = DateTime(2026, 11, 17, 8, 9, 10, 123, 456);
      final encoded = rfc3339(time);
      expect(encoded, contains('2026-11-17T08:09:10.123456'));
      final decoded = parseTime(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.millisecondsSinceEpoch, time.millisecondsSinceEpoch);
    });

    test('formatting helpers handle edge cases', () {
      expect(humanSize(0), '0 B');
      expect(humanSize(1536), '1.5 KB');
      expect(chatPreview('text', 'line\nbreak', '', false), 'line break');
      expect(chatPreview('file', '', 'a.pdf', false), '[文件] a.pdf');
      expect(chatPreview('text', 'hello', '', true), '消息已撤回');
    });

    test('new ids include a prefix and random suffix', () {
      final first = newId('m');
      final second = newId('m');
      expect(first, startsWith('m_'));
      expect(first.length, greaterThan(10));
      expect(first, isNot(second));
    });
  });

  group('Settings', () {
    test('round-trips through JSON', () {
      final defaults = Settings(downloadDir: '/downloads');
      final original = Settings(
        appearance: 'dark',
        language: 'en',
        status: Presence.busy,
        notifications: false,
        autoDownloadImages: false,
        discovery: false,
        port: 45000,
        transferPort: 45001,
        sharePort: 45002,
        downloadDir: '/downloads',
        shareDir: '/share',
        uploadDir: '/upload',
        haptics: false,
        notifyPreview: false,
      );
      final restored = Settings.fromJson(original.toJson(), defaults);
      expect(restored.appearance, 'dark');
      expect(restored.language, 'en');
      expect(restored.status, Presence.busy);
      expect(restored.notifications, isFalse);
      expect(restored.autoDownloadImages, isFalse);
      expect(restored.discovery, isFalse);
      expect(restored.port, 45000);
      expect(restored.transferPort, 45001);
      expect(restored.sharePort, 45002);
      expect(restored.shareDir, '/share');
      expect(restored.uploadDir, '/upload');
      expect(restored.haptics, isFalse);
      expect(restored.notifyPreview, isFalse);
    });

    test('fills invalid ports with defaults', () {
      final defaults = Settings(downloadDir: '/downloads');
      final restored = Settings.fromJson({
        'port': 0,
        'transferPort': 0,
        'sharePort': 0,
        'language': '',
      }, defaults);
      expect(restored.port, 42224);
      expect(restored.transferPort, 42225);
      expect(restored.sharePort, 42230);
      expect(restored.language, 'system');
    });
  });

  group('models', () {
    test('Message preview and wire JSON omit local paths', () {
      final message = Message(
        id: 'm_1',
        convId: 'u_bob',
        senderId: 'u_alice',
        kind: MessageKind.file,
        file: FileMeta(
          name: 'photo.png',
          size: 123,
          mime: 'image/png',
          path: '/private/photo.png',
          token: 't_1',
        ),
        sentAt: DateTime(2026, 1, 2, 3, 4),
      );
      expect(message.preview, '[文件] photo.png');
      final wire = message.wireJson();
      expect(wire['file'], isNot(contains('path')));
      final stored = message.toJson(includePath: true);
      expect(stored['file']['path'], '/private/photo.png');
    });

    test('Peer display name prefers alias and exposes addresses', () {
      final peer = Peer(
        id: 'u_bob',
        name: 'Bob',
        alias: 'Bobby',
        ip: '192.168.1.10',
        port: 42224,
        transferPort: 42225,
        connected: true,
        status: Presence.online,
      );
      expect(peer.displayName, 'Bobby');
      expect(peer.addr, '192.168.1.10:42224');
      expect(peer.transferAddr, '192.168.1.10:42225');
      expect(peer.available, isTrue);
    });
  });
}
