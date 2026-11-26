import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../core/database.dart';
import '../core/helpers.dart';
import '../core/i18n.dart';
import '../core/image_utils.dart';
import '../core/models.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../core/state_store.dart';
import '../net/frame.dart';
import '../net/peer_node.dart';
import '../net/share_server.dart';
import '../net/transfer_client.dart';
import '../net/transfer_server.dart';
import '../services/mobile_bridge.dart';
import '../services/notification_service.dart';

class ChatController extends ChangeNotifier {
  final AppPaths paths;

  late Settings settings;
  late Profile profile;
  late MessageDatabase db;
  late SettingsStore settingsStore;
  late StateStore stateStore;

  TransferServer? transfer;
  ShareServer? share;
  PeerNode? node;

  final Map<String, Peer> peers = {};
  final Map<String, Conversation> convs = {};
  final Map<String, List<Message>> msgs = {};
  Map<String, List<Frame>> outbox = {};

  final Map<String, DownloadState> downloads = {};
  final Map<String, SendProgress> sends = {};
  final Map<String, String> sendTokenMap = {};
  final Map<String, TypingState> typing = {};
  final Map<String, DateTime> lastRead = {};

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);

  String activeConvId = '';
  bool appVisible = true;
  bool ready = false;
  bool shareExplicit = false;
  String version = '1.0.0';
  List<String> localIps = [];
  StoreStats? dbStats;

  void Function(String convId)? onOpenConversation;

  Timer? _stateTimer;
  Timer? _toastTimer;
  final Map<String, Timer> _msgTimers = {};
  final Map<String, Timer> _typingTimers = {};
  bool _disposed = false;
  bool _startingTransfer = false;
  bool _shuttingDown = false;

  ChatController(this.paths);

  bool get running => ready;

  @override
  void dispose() {
    _disposed = true;
    _stateTimer?.cancel();
    _toastTimer?.cancel();
    for (final t in _msgTimers.values) {
      t.cancel();
    }
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    toastNotifier.dispose();
    super.dispose();
  }

  Future<void> init() async {
    await L10n.instance.load();
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.isEmpty ? version : info.version;
    } catch (_) {}

    settingsStore = SettingsStore(paths.settingsPath);
    final deviceName = await MobileBridge.deviceLabel();
    final defaultName = (deviceName != null &&
            deviceName.trim().isNotEmpty &&
            deviceName.trim().toLowerCase() != 'localhost')
        ? deviceName.trim()
        : L10n.instance.tr('ui.my_zchat');
    final defaults = Settings(
      downloadDir: paths.downloadDir,
      screenshotDir: paths.picturesDir,
      screenshotIncludeShortcut: '',
      screenshotExcludeShortcut: '',
    );
    settings = await settingsStore.load(defaults);
    L10n.instance.language = settings.language;

    stateStore = StateStore(paths.statePath);
    final fallback = Profile(
      id: '',
      name: defaultName,
      status: settings.status,
    );
    final st = await stateStore.load(fallback);
    profile = st.profile;
    if (profile.id.isEmpty) {
      profile = Profile(
        id: newId('u'),
        name: defaultName,
        status: settings.status,
      );
    }
    if (profile.name.trim().isEmpty) profile.name = defaultName;
    if (profile.status == Presence.offline) profile.status = settings.status;
    settings.status = profile.status;
    for (final c in st.conversations) {
      convs[c.id] = c;
      msgs.putIfAbsent(c.id, () => []);
    }
    st.peers.forEach((id, peer) {
      peer.connected = false;
      peers[id] = peer;
    });
    outbox = st.outbox;

    db = MessageDatabase(paths.databasePath);
    await db.open();
    for (final c in convs.values.toList()) {
      try {
        final list = await db.loadMessages(c.id);
        for (final m in list) {
          m.mine = m.senderId == profile.id;
        }
        msgs[c.id] = list;
        if (list.isNotEmpty) c.last = list.last;
      } catch (_) {
        msgs.putIfAbsent(c.id, () => []);
      }
    }

    transfer = TransferServer(paths.transfersPath);
    await transfer!.loadRegistry();
    transfer!.onProgress = _onTransferProgress;
    transfer!.onError = _setToast;
    try {
      await transfer!.start(settings.transferPort);
    } catch (e) {
      _setToast(L10n.instance.tr('ui.file_transfer_service_is_not_running') + e.toString());
    }

    share = ShareServer(paths.httpTransfersPath);
    await share!.loadTransfers();
    share!.onProgress = _onShareProgress;
    share!.onError = _setToast;
    final validShare = await _validDir(settings.shareDir);
    final validUpload = await _validDir(settings.uploadDir);
    share!.dir = validShare;
    share!.uploadDir = validUpload;

    localIps = await _localIps();
    await _startNode();

    if (settings.shareOnStart &&
        (settings.shareDir.isNotEmpty || settings.uploadDir.isNotEmpty)) {
      await startShare(announce: false, quiet: true);
    }

    rebuildSendTokens();
    if (activeConvId.isEmpty) {
      final ordered = orderedConversations();
      if (ordered.isNotEmpty) activeConvId = ordered.first.id;
    }

    NotificationService.instance.onSelect = (convId) {
      if (convs.containsKey(convId)) {
        openConversation(convId);
        onOpenConversation?.call(convId);
      }
    };
    await NotificationService.instance.init();

    ready = true;
    await saveSettings();
    _scheduleStateSave();
    await refreshDbStats();
    _bump();
  }

  Future<void> _startNode() async {
    final tp = (transfer != null && transfer!.running) ? transfer!.port : 0;
    final n = PeerNode(
      profile: profile,
      version: version,
      port: settings.port,
      transferPort: tp,
      discoveryEnabled: settings.discovery,
    );
    n.onPeer = _applyPeer;
    n.onConnect = (peer) {
      _applyPeer(peer);
      flushOutbox(peer.id);
    };
    n.onDisconnect = (id) {
      final peer = peers[id];
      if (peer != null) {
        peer.connected = false;
        _scheduleStateSave();
        _bump();
      }
    };
    n.onFrame = _handleFrame;
    n.onError = (message) {
      _setToast(message);
      _bump();
    };
    node = n;
    try {
      await n.start();
      localIps = await _localIps();
      settings.port = n.port;
    } catch (e) {
      _setToast(e.toString().replaceFirst('Bad state: ', ''));
      if (n.port == 0) settings.port = settings.port;
    }
  }

  Future<void> restartNetwork() async {
    final n = node;
    node = null;
    await n?.stop();
    if (transfer != null && transfer!.running) {
      await transfer!.stop();
      try {
        await transfer!.start(settings.transferPort);
      } catch (e) {
        _setToast(L10n.instance.tr('ui.file_transfer_service_is_not_running') + e.toString());
      }
    }
    await _startNode();
    for (final peer in peers.values) {
      peer.connected = false;
    }
    await saveSettings();
    _bump();
  }

  Future<List<String>> _localIps() async {
    final out = <String>[];
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in list) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) out.add(a.address);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<String> _validDir(String path) async {
    if (path.isEmpty) return '';
    try {
      final stat = await Directory(path).stat();
      if (stat.type == FileSystemEntityType.directory) return path;
    } catch (_) {}
    return '';
  }

  void _bump() {
    if (!_disposed) notifyListeners();
  }

  void _setToast(String message) {
    if (_disposed) return;
    final text = message.trim();
    if (text.isEmpty) return;
    toastNotifier.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (toastNotifier.value == text) toastNotifier.value = null;
    });
  }

  bool hapticIfEnabled() {
    if (!settings.haptics) return false;
    HapticFeedback.lightImpact();
    return true;
  }

  // ---------------------------------------------------------------------
  // Persistence

  void _scheduleStateSave() {
    if (_disposed || _shuttingDown) return;
    if (_stateTimer?.isActive ?? false) return;
    _stateTimer = Timer(const Duration(milliseconds: 300), () {
      _saveStateNow();
    });
  }

  Future<void> _saveStateNow() async {
    if (_disposed) return;
    try {
      await stateStore.save(AppState(
        profile: profile,
        conversations: convs.values.toList(),
        peers: peers,
        outbox: outbox,
      ));
    } catch (_) {}
  }

  void _scheduleMessageSave(String convId) {
    if (_disposed || _shuttingDown) return;
    final existing = _msgTimers[convId];
    if (existing?.isActive ?? false) return;
    _msgTimers[convId] = Timer(const Duration(milliseconds: 300), () async {
      _msgTimers.remove(convId);
      await _saveMessagesNow(convId);
    });
  }

  Future<void> _saveMessagesNow(String convId) async {
    if (_disposed) return;
    try {
      await db.saveMessages(convId, msgs[convId] ?? []);
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    try {
      await settingsStore.save(settings);
    } catch (_) {}
  }

  Future<void> flushSaves() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    for (final entry in _msgTimers.entries.toList()) {
      entry.value.cancel();
    }
    _msgTimers.clear();
    await _saveStateNow();
    for (final id in msgs.keys.toList()) {
      await _saveMessagesNow(id);
    }
  }

  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    settings.status = profile.status;
    await saveSettings();
    await flushSaves();
    await node?.stop();
    node = null;
    await share?.stop();
    await transfer?.stop();
    await db.close();
    await MobileBridge.releaseMulticast();
  }

  Future<void> refreshDbStats() async {
    try {
      dbStats = await db.stats();
      _bump();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Peers and conversations

  void _applyPeer(Peer incoming) {
    final existing = peers[incoming.id];
    final merged = Peer(
      id: incoming.id,
      name: incoming.name.isEmpty && existing != null
          ? existing.name
          : incoming.name,
      signature: incoming.signature,
      avatar:
          incoming.avatar.isEmpty && existing != null ? existing.avatar : incoming.avatar,
      status: incoming.status,
      ip: incoming.ip.isEmpty && existing != null ? existing.ip : incoming.ip,
      port: incoming.port == 0 && existing != null ? existing.port : incoming.port,
      transferPort: incoming.transferPort == 0 && existing != null
          ? existing.transferPort
          : incoming.transferPort,
      version: incoming.version,
      platform: incoming.platform,
      lastSeen: incoming.lastSeen ?? DateTime.now(),
      connected: incoming.connected,
      alias: existing?.alias ?? '',
      manual: existing?.manual ?? false,
    );
    peers[merged.id] = merged;
    if (node != null) node!.rememberPeer(merged);
    _scheduleStateSave();
    _bump();
  }

  Peer peer(String id) => peers[id] ?? Peer(id: id);

  String peerName(String id) {
    if (id == profile.id) return profile.name;
    final peer = peers[id];
    if (peer != null) return peer.displayName;
    return L10n.instance.tr('device.unknown_device');
  }

  String conversationTitle(Conversation c) {
    if (c.kind == ConvKind.group) {
      return c.title.isEmpty ? L10n.instance.tr('chat.group') : c.title;
    }
    final peer = peers[c.peerId];
    return peer?.displayName ??
        (c.title.isEmpty ? L10n.instance.tr('device.unknown_device') : c.title);
  }

  Conversation? conversation(String id) => convs[id];

  List<Conversation> orderedConversations() {
    final list = convs.values.toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) return byTime;
      return conversationTitle(a)
          .toLowerCase()
          .compareTo(conversationTitle(b).toLowerCase());
    });
    return list;
  }

  List<Peer> sortedPeers() {
    final list = peers.values.toList();
    list.sort((a, b) {
      if (a.connected != b.connected) return a.connected ? -1 : 1;
      final aa = presenceAvailable(a.status);
      final bb = presenceAvailable(b.status);
      if (aa != bb) return aa ? -1 : 1;
      return a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  int get totalUnread => convs.values
      .where((c) => !c.muted)
      .fold(0, (sum, c) => sum + c.unread);

  Conversation ensureDirect(Peer peer) {
    var c = convs[peer.id];
    if (c != null && c.kind == ConvKind.direct) return c;
    c = Conversation(
      id: peer.id,
      kind: ConvKind.direct,
      peerId: peer.id,
      title: peer.name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    convs[c.id] = c;
    msgs.putIfAbsent(c.id, () => []);
    peers[peer.id] = peer;
    _scheduleStateSave();
    return c;
  }

  Conversation ensurePeerConversation(String peerId) {
    final existing = convs[peerId];
    if (existing != null) return existing;
    return ensureDirect(peer(peerId));
  }

  void openConversation(String id) {
    final c = convs[id];
    if (c == null) return;
    if (activeConvId.isNotEmpty && activeConvId != id) {
      stopTyping(activeConvId);
    }
    activeConvId = id;
    c.unread = 0;
    NotificationService.instance.cancel(c.id);
    _markActiveRead();
    queueActiveImages();
    _scheduleStateSave();
    _bump();
  }

  void leaveConversation() {
    if (activeConvId.isNotEmpty) stopTyping(activeConvId);
    activeConvId = '';
    _bump();
  }

  void setAppVisible(bool visible) {
    appVisible = visible;
    if (visible) {
      _markActiveRead();
      queueActiveImages();
    }
    _bump();
  }

  bool get activeVisible => appVisible && activeConvId.isNotEmpty;

  void _markActiveRead() {
    final c = convs[activeConvId];
    if (c == null) return;
    if (c.unread != 0) {
      c.unread = 0;
      _scheduleStateSave();
      _bump();
    }
    if (c.kind != ConvKind.direct) return;
    final last = lastRead[c.id];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 1)) {
      return;
    }
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 1)) {
      return;
    }
    final list = msgs[c.id] ?? [];
    DateTime? at;
    for (var i = list.length - 1; i >= 0; i--) {
      if (!list[i].mine) {
        at = list[i].sentAt;
        break;
      }
    }
    if (at == null) return;
    lastRead[c.id] = DateTime.now();
    sendFrame(
      c.peerId,
      newFrame(profile.id, typeRead, {
        'convId': c.id,
        'time': at.millisecondsSinceEpoch,
      }),
    );
  }

  // ---------------------------------------------------------------------
  // Incoming frames

  void _handleFrame(String peerId, Frame f) {
    final data = f.dataMap;
    if (data == null) return;
    try {
      switch (f.type) {
        case typeChat:
          final raw = data['message'];
          if (raw is Map) {
            receiveMessage(
              peerId,
              Message.fromJson(Map<String, dynamic>.from(raw)),
            );
          }
          break;
        case typeAck:
          receiveAck(asString(data['messageId']));
          break;
        case typeRead:
          receiveRead(peerId, data);
          break;
        case typeTyping:
          receiveTyping(peerId, data);
          break;
        case typeRecall:
          receiveRecall(peerId, asString(data['messageId']));
          break;
        case typeGroup:
          receiveGroup(peerId, data);
          break;
      }
    } catch (_) {}
  }

  bool _hasMessage(String convId, String messageId) {
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id == messageId) return true;
    }
    return false;
  }

  void receiveMessage(String from, Message m) {
    m.mine = false;
    if (m.senderId.isEmpty) m.senderId = from;
    if (m.id.isEmpty) m.id = newId('m');
    from = m.senderId;
    var peer = peers[from];
    if (peer == null) {
      final known = node?.peer(from);
      if (known != null) {
        peer = known;
        peers[from] = peer;
      } else {
        peer = Peer(
          id: from,
          name: m.senderName,
          status: Presence.online,
          connected: true,
          lastSeen: DateTime.now(),
        );
        peers[from] = peer;
      }
    }
    if (m.file != null) m.file!.path = '';
    var c = convs[m.convId];
    if (m.convId.startsWith('g_')) {
      if (c == null || c.kind != ConvKind.group) return;
    } else if (c == null || c.kind != ConvKind.direct) {
      c = ensureDirect(peer);
      m.convId = c.id;
    }
    if (m.senderName.isEmpty) m.senderName = peerName(m.senderId);
    if (m.kind != MessageKind.system) m.delivered = true;

    if (_hasMessage(c.id, m.id)) {
      sendFrame(
        from,
        newFrame(profile.id, typeAck, {
          'messageId': m.id,
          'time': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      return;
    }

    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.last = m;
    _scheduleMessageSave(c.id);
    _scheduleStateSave();

    sendFrame(
      from,
      newFrame(profile.id, typeAck, {
        'messageId': m.id,
        'time': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    if (activeConvId == c.id && activeVisible) {
      _markActiveRead();
      hapticIfEnabled();
    } else {
      if (!c.muted) c.unread++;
      _notifyMessage(c, m);
    }
    if (activeConvId == c.id) {
      _bump();
    } else {
      _bump();
    }
    if (m.kind == MessageKind.image && settings.autoDownloadImages) {
      autoDownloadImage(c.id, m.id);
    }
    if (m.kind == MessageKind.system) return;
  }

  void receiveAck(String messageId) {
    if (messageId.isEmpty) return;
    for (final entry in msgs.entries) {
      for (final m in entry.value) {
        if (m.id != messageId) continue;
        m.delivered = true;
        if (m.status != 'read') m.status = 'delivered';
        _scheduleMessageSave(entry.key);
        _bump();
        return;
      }
    }
  }

  void receiveRead(String from, Map<String, dynamic> data) {
    var convId = asString(data['convId']);
    if (!convId.startsWith('g_')) {
      if (convs.containsKey(from)) convId = from;
    }
    final list = msgs[convId];
    if (list == null || list.isEmpty) return;
    final time = asInt(data['time']);
    if (time <= 0) return;
    final at = DateTime.fromMillisecondsSinceEpoch(time);
    var changed = false;
    for (final m in list) {
      if (m.mine && !m.sentAt.isAfter(at)) {
        m.read = true;
        m.delivered = true;
        m.status = 'read';
        changed = true;
      }
    }
    if (changed) {
      _scheduleMessageSave(convId);
      if (activeConvId == convId) _bump();
    }
  }

  void receiveTyping(String from, Map<String, dynamic> data) {
    var convId = asString(data['convId']);
    if (!convId.startsWith('g_')) convId = from;
    final key = '$convId\x00$from';
    final on = asBool(data['on']);
    if (!on) {
      typing.remove(key);
      _typingTimers.remove(key)?.cancel();
      if (activeConvId == convId) _bump();
      return;
    }
    typing[key] = TypingState(convId, from, DateTime.now());
    _typingTimers.remove(key)?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 4), () {
      _typingTimers.remove(key);
      final st = typing[key];
      if (st != null &&
          DateTime.now().difference(st.updatedAt) >=
              const Duration(seconds: 3)) {
        typing.remove(key);
        if (activeConvId == convId) _bump();
      }
    });
    if (activeConvId == convId) _bump();
  }

  List<String> typingNames(Conversation c) {
    final out = <String>[];
    for (final st in typing.values) {
      if (st.convId != c.id || st.peerId == profile.id) continue;
      out.add(peerName(st.peerId));
    }
    return out;
  }

  void receiveRecall(String from, String messageId) {
    if (messageId.isEmpty) return;
    for (final entry in msgs.entries) {
      for (final m in entry.value) {
        if (m.id != messageId) continue;
        if (m.senderId != from && m.senderId != profile.id) return;
        m.recalled = true;
        forgetMessageFiles([m]);
        _scheduleMessageSave(entry.key);
        _bump();
        return;
      }
    }
  }

  void _notifyMessage(Conversation c, Message m) {
    if (!settings.notifications || c.muted) return;
    var title = peerName(m.senderId);
    if (c.kind == ConvKind.group) {
      title = '${conversationTitle(c)} · $title';
    }
    final body = settings.notifyPreview
        ? L10n.instance.tr(m.preview)
        : L10n.instance.tr('chat.new_message');
    NotificationService.instance.show(
      convId: c.id,
      title: title,
      body: body,
    );
  }

  // ---------------------------------------------------------------------
  // Outgoing messages

  Future<void> sendText(String text) async {
    final c = convs[activeConvId];
    if (c == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final m = Message(
      id: newId('m'),
      convId: c.id,
      senderId: profile.id,
      senderName: profile.name,
      kind: MessageKind.text,
      text: trimmed,
      sentAt: DateTime.now(),
      status: 'sent',
      mine: true,
    );
    addLocalMessage(c, m);
    c.draft = '';
    sendTyping(false);
  }

  void sendTextTo(String convId, String text) {
    final c = convs[convId];
    if (c == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    addLocalMessage(
      c,
      Message(
        id: newId('m'),
        convId: c.id,
        senderId: profile.id,
        senderName: profile.name,
        kind: MessageKind.text,
        text: trimmed,
        sentAt: DateTime.now(),
        status: 'sent',
        mine: true,
      ),
    );
  }

  void addLocalMessage(Conversation c, Message m) {
    m.mine = true;
    m.convId = c.id;
    if (m.senderName.isEmpty) m.senderName = profile.name;
    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.draft = '';
    c.last = m;
    _scheduleMessageSave(c.id);
    _scheduleStateSave();
    dispatchMessage(c, m);
    if (activeConvId == c.id) {
      _markActiveRead();
    }
    _bump();
  }

  void dispatchMessage(Conversation c, Message m) {
    final wire = m.wireJson();
    final f = newFrame(profile.id, typeChat, {'message': wire});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) deliver(id, f);
      }
    } else if (c.peerId.isNotEmpty) {
      deliver(c.peerId, f);
    }
  }

  void deliver(String peerId, Frame f) {
    if (peerId.isEmpty || peerId == profile.id) return;
    final n = node;
    if (n != null && n.send(peerId, f)) return;
    queueFrame(peerId, f);
  }

  void sendFrame(String peerId, Frame f) {
    if (peerId.isEmpty || peerId == profile.id) return;
    node?.send(peerId, f);
  }

  void queueFrame(String peerId, Frame f) {
    final list = outbox.putIfAbsent(peerId, () => []);
    if (list.length >= 300) list.removeAt(0);
    list.add(f);
    _scheduleStateSave();
  }

  void flushOutbox(String peerId) {
    final n = node;
    if (n == null) return;
    final list = outbox[peerId];
    if (list == null || list.isEmpty) return;
    final rest = <Frame>[];
    for (final f in list) {
      if (!n.send(peerId, f)) rest.add(f);
    }
    if (rest.isEmpty) {
      outbox.remove(peerId);
    } else {
      outbox[peerId] = rest;
    }
    _scheduleStateSave();
  }

  void sendTyping(bool on) {
    final c = convs[activeConvId];
    if (c == null) return;
    if (on) {
      final now = DateTime.now();
      final last = _lastTypingAt;
      if (last != null &&
          now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
      _lastTypingAt = now;
    }
    final f = newFrame(profile.id, typeTyping, {'convId': c.id, 'on': on});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) sendFrame(id, f);
      }
    } else {
      sendFrame(c.peerId, f);
    }
  }

  DateTime? _lastTypingAt;

  void stopTyping(String convId) {
    final c = convs[convId];
    if (c == null) return;
    final f = newFrame(profile.id, typeTyping, {'convId': c.id, 'on': false});
    if (c.kind == ConvKind.group) {
      for (final id in c.members) {
        if (id != profile.id) sendFrame(id, f);
      }
    } else {
      sendFrame(c.peerId, f);
    }
  }

  void setDraft(String convId, String text) {
    final c = convs[convId];
    if (c == null || c.draft == text) return;
    c.draft = text;
    _scheduleStateSave();
  }

  // ---------------------------------------------------------------------
  // Message actions

  Message? message(String convId, String messageId) {
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  void recallMessage(String convId, String messageId) {
    final c = convs[convId];
    if (c == null) return;
    for (final m in msgs[convId] ?? const <Message>[]) {
      if (m.id != messageId || !m.mine) continue;
      if (DateTime.now().difference(m.sentAt) > const Duration(minutes: 2)) {
        _setToast(L10n.instance.tr('chat.messages_older_than_2_minutes_cannot_be_unsent'));
        return;
      }
      m.recalled = true;
      forgetMessageFiles([m]);
      _scheduleMessageSave(convId);
      final f = newFrame(profile.id, typeRecall, {'messageId': messageId});
      if (c.kind == ConvKind.group) {
        for (final id in c.members) {
          if (id != profile.id) deliver(id, f);
        }
      } else {
        deliver(c.peerId, f);
      }
      _bump();
      return;
    }
  }

  void deleteMessage(String convId, String messageId) {
    final list = msgs[convId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    forgetMessageFiles([list[idx]]);
    list.removeAt(idx);
    final c = convs[convId];
    if (c != null) c.last = list.isEmpty ? null : list.last;
    _scheduleMessageSave(convId);
    _bump();
  }

  void clearHistory(String convId) {
    if (!msgs.containsKey(convId)) return;
    forgetMessageFiles(msgs[convId] ?? const []);
    msgs[convId] = [];
    final c = convs[convId];
    if (c != null) {
      c.last = null;
      c.unread = 0;
    }
    _scheduleMessageSave(convId);
    db.deleteConversation(convId).then((_) => refreshDbStats());
    _bump();
  }

  void clearAllHistory() {
    for (final list in msgs.values) {
      forgetMessageFiles(list);
    }
    for (final id in msgs.keys.toList()) {
      msgs[id] = [];
    }
    for (final c in convs.values) {
      c.unread = 0;
      c.last = null;
    }
    db.clearAll().then((_) => refreshDbStats());
    _scheduleStateSave();
    _setToast(L10n.instance.tr('chat.chat_history_cleared'));
    _bump();
  }

  void deleteConversation(String convId) {
    final c = convs[convId];
    if (c == null) return;
    if (c.kind == ConvKind.group) {
      leaveGroup(c);
      return;
    }
    forgetMessageFiles(msgs[convId] ?? const []);
    convs.remove(convId);
    msgs.remove(convId);
    if (activeConvId == convId) activeConvId = '';
    db.deleteConversation(convId).then((_) => refreshDbStats());
    _scheduleStateSave();
    _bump();
  }

  void togglePinned(String convId) {
    final c = convs[convId];
    if (c == null) return;
    c.pinned = !c.pinned;
    _scheduleStateSave();
    _bump();
  }

  void toggleMuted(String convId) {
    final c = convs[convId];
    if (c == null) return;
    c.muted = !c.muted;
    _scheduleStateSave();
    _bump();
  }

  // ---------------------------------------------------------------------
  // Groups

  Conversation createGroup(String name, List<String> picked) {
    var title = name.trim();
    if (title.isEmpty) title = L10n.instance.tr('chat.unnamed_group');
    final members = <String>[profile.id];
    final seen = <String>{profile.id};
    for (final id in picked) {
      if (id.isEmpty || !seen.add(id)) continue;
      members.add(id);
    }
    final now = DateTime.now();
    final g = Group(
      id: newId('g'),
      name: title,
      owner: profile.id,
      members: members,
      createdAt: now,
      updatedAt: now,
    );
    final c = g.conversation()..updatedAt = now;
    convs[c.id] = c;
    msgs[c.id] = [];
    appendSystem(c, L10n.instance.tr('chat.you_created_group') + title + L10n.instance.tr('ui.item'));
    sendGroupAction(g, groupInvite, '');
    _scheduleStateSave();
    openConversation(c.id);
    return c;
  }

  Group groupForConv(Conversation c) => Group(
        id: c.id,
        name: conversationTitle(c),
        owner: c.owner,
        members: List<String>.from(c.members),
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
      );

  void sendGroupAction(Group g, String action, String intro) {
    final f = newFrame(profile.id, typeGroup, {
      'action': action,
      'group': g.toJson(),
      if (intro.isNotEmpty) 'intro': intro,
    });
    for (final id in g.members) {
      if (id != profile.id) deliver(id, f);
    }
  }

  void receiveGroup(String from, Map<String, dynamic> data) {
    final raw = data['group'];
    if (raw is! Map) return;
    final g = Group.fromJson(Map<String, dynamic>.from(raw));
    if (g.id.isEmpty || !g.id.startsWith('g_')) return;
    final action = asString(data['action']);
    final intro = asString(data['intro']);
    switch (action) {
      case groupInvite:
        receiveInvite(from, g, intro);
        break;
      case groupUpdate:
        receiveGroupUpdate(from, g);
        break;
      case groupLeave:
        receiveGroupLeave(g, from);
        break;
      case groupDisband:
        final c = convs[g.id];
        if (c != null) {
          forgetMessageFiles(msgs[g.id] ?? const []);
          convs.remove(g.id);
          msgs.remove(g.id);
          if (activeConvId == g.id) activeConvId = '';
          db.deleteConversation(g.id).then((_) => refreshDbStats());
          _scheduleStateSave();
          _setToast(
              L10n.instance.tr('chat.group_2') + c.title + L10n.instance.tr('ui.was_dissolved'));
          _bump();
        }
        break;
    }
  }

  void receiveInvite(String from, Group g, String intro) {
    if (!g.hasMember(profile.id)) return;
    final existing = convs[g.id];
    if (existing != null) {
      applyGroup(existing, g);
      _scheduleStateSave();
      _bump();
      return;
    }
    final c = g.conversation();
    if (c.title.isEmpty) c.title = L10n.instance.tr('chat.group');
    c.updatedAt = DateTime.now();
    convs[c.id] = c;
    msgs[c.id] = [];
    var text = peerName(from) + L10n.instance.tr('chat.invited_you_fragment');
    if (intro.isNotEmpty) text += L10n.instance.tr('ui.item_3') + intro;
    appendSystem(c, text);
    c.unread = 1;
    _scheduleStateSave();
    if (settings.notifications) {
      NotificationService.instance.show(
        convId: c.id,
        title: peerName(from) + L10n.instance.tr('chat.invited_you_fragment'),
        body: c.title,
      );
    }
    _bump();
  }

  void receiveGroupUpdate(String from, Group g) {
    var c = convs[g.id];
    if (c == null) {
      if (!g.hasMember(profile.id)) return;
      c = g.conversation();
      convs[g.id] = c;
      msgs[g.id] = [];
      appendSystem(
          c, L10n.instance.tr('chat.you_joined_group') + conversationTitle(c) + L10n.instance.tr('ui.item'));
    } else {
      if (!g.hasMember(profile.id)) {
        forgetMessageFiles(msgs[g.id] ?? const []);
        convs.remove(g.id);
        msgs.remove(g.id);
        if (activeConvId == g.id) activeConvId = '';
        db.deleteConversation(g.id).then((_) => refreshDbStats());
        _setToast(
            L10n.instance.tr('chat.you_were_removed_from_group') + c.title + L10n.instance.tr('ui.item'));
        _scheduleStateSave();
        _bump();
        return;
      }
      applyGroup(c, g);
    }
    _scheduleStateSave();
    _bump();
  }

  void receiveGroupLeave(Group g, String from) {
    final c = convs[g.id];
    if (c == null) return;
    final before = c.members.length;
    c.members.remove(from);
    if (c.members.length == before) return;
    c.updatedAt = DateTime.now();
    appendSystem(c, peerName(from) + L10n.instance.tr('chat.left_group_fragment'));
    _scheduleStateSave();
    _bump();
  }

  void applyGroup(Conversation c, Group g) {
    c.title = g.name;
    c.owner = g.owner;
    c.members = List<String>.from(g.members);
    c.updatedAt = DateTime.now();
  }

  void renameGroup(String convId, String name) {
    final c = convs[convId];
    final title = name.trim();
    if (c == null || title.isEmpty || title == c.title) return;
    c.title = title;
    c.updatedAt = DateTime.now();
    appendSystem(c, L10n.instance.tr('chat.group_renamed_to') + title + L10n.instance.tr('ui.item'));
    sendGroupAction(groupForConv(c), groupUpdate, '');
    _scheduleStateSave();
    _bump();
  }

  void addGroupMembers(String convId, List<String> ids) {
    final c = convs[convId];
    if (c == null) return;
    final seen = c.members.toSet();
    var added = 0;
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) continue;
      c.members.add(id);
      added++;
    }
    if (added == 0) return;
    c.updatedAt = DateTime.now();
    appendSystem(c, L10n.instance.tr('chat.added_fragment') + added.toString() + L10n.instance.tr('chat.members_fragment'));
    sendGroupAction(groupForConv(c), groupUpdate, '');
    _scheduleStateSave();
    _bump();
  }

  void removeGroupMember(String convId, String id) {
    final c = convs[convId];
    if (c == null || id == profile.id) return;
    c.members.remove(id);
    c.updatedAt = DateTime.now();
    appendSystem(c, peerName(id) + L10n.instance.tr('chat.was_removed_fragment'));
    sendGroupAction(groupForConv(c), groupUpdate, '');
    _scheduleStateSave();
    _bump();
  }

  void leaveGroup(Conversation c) {
    final g = groupForConv(c);
    final f = newFrame(profile.id, typeGroup, {
      'action': groupLeave,
      'group': g.toJson(),
    });
    for (final id in c.members) {
      if (id != profile.id) deliver(id, f);
    }
    forgetMessageFiles(msgs[c.id] ?? const []);
    convs.remove(c.id);
    msgs.remove(c.id);
    if (activeConvId == c.id) activeConvId = '';
    db.deleteConversation(c.id).then((_) => refreshDbStats());
    _scheduleStateSave();
    _setToast(L10n.instance.tr('chat.you_left_group') + c.title + L10n.instance.tr('ui.item'));
    _bump();
  }

  void disbandGroup(Conversation c) {
    final g = groupForConv(c);
    final f = newFrame(profile.id, typeGroup, {
      'action': groupDisband,
      'group': g.toJson(),
    });
    for (final id in c.members) {
      if (id != profile.id) deliver(id, f);
    }
    forgetMessageFiles(msgs[c.id] ?? const []);
    convs.remove(c.id);
    msgs.remove(c.id);
    if (activeConvId == c.id) activeConvId = '';
    db.deleteConversation(c.id).then((_) => refreshDbStats());
    _scheduleStateSave();
    _setToast(L10n.instance.tr('chat.group_2') + c.title + L10n.instance.tr('ui.was_dissolved'));
    _bump();
  }

  void appendSystem(Conversation c, String text) {
    final m = Message(
      id: newId('m'),
      convId: c.id,
      senderId: profile.id,
      senderName: profile.name,
      kind: MessageKind.system,
      text: text,
      sentAt: DateTime.now(),
    );
    msgs.putIfAbsent(c.id, () => []).add(m);
    c.updatedAt = m.sentAt;
    c.last = m;
    _scheduleMessageSave(c.id);
  }

  List<Peer> groupMembers(Conversation c) {
    final out = <Peer>[];
    for (final id in c.members) {
      if (id == profile.id) {
        out.add(profile.asPeer('', 0, 0));
        continue;
      }
      final peer = peers[id];
      if (peer != null) {
        out.add(peer);
      } else {
        out.add(Peer(
          id: id,
          name: L10n.instance.tr('chat.unknown_member'),
          status: Presence.offline,
        ));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Files

  Future<bool> ensureTransfer() async {
    if (transfer != null && transfer!.running) return true;
    if (_startingTransfer) {
      while (_startingTransfer) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return transfer != null && transfer!.running;
    }
    _startingTransfer = true;
    try {
      transfer ??= TransferServer(paths.transfersPath);
      transfer!.onProgress = _onTransferProgress;
      transfer!.onError = _setToast;
      await transfer!.loadRegistry();
      await transfer!.start(settings.transferPort);
      return transfer!.running;
    } catch (_) {
      return false;
    } finally {
      _startingTransfer = false;
    }
  }

  Future<bool> ensureShareServer() async {
    final s = share;
    if (s == null) return false;
    if (s.running) return true;
    s.dir = await _validDir(settings.shareDir);
    s.uploadDir = '';
    shareExplicit = false;
    try {
      await s.start(settings.sharePort);
      _setToast(L10n.instance.tr('share.file_sharing_is_on'));
      return true;
    } catch (e) {
      _setToast(L10n.instance.tr('share.could_not_start_file_sharing') + e.toString());
      return false;
    }
  }

  Future<void> startShare({bool announce = true, bool quiet = false}) async {
    final s = share;
    if (s == null) return;
    final shareDir = await _validDir(settings.shareDir);
    final uploadDir = await _validDir(settings.uploadDir);
    if (settings.shareDir.isNotEmpty && shareDir.isEmpty) {
      _setToast(L10n.instance.tr('share.shared_folder_does_not_exist'));
      return;
    }
    if (settings.uploadDir.isNotEmpty && uploadDir.isEmpty) {
      _setToast(L10n.instance.tr('share.upload_folder_does_not_exist'));
      return;
    }
    s.dir = shareDir;
    s.uploadDir = uploadDir;
    try {
      await s.start(settings.sharePort);
    } catch (e) {
      shareExplicit = false;
      _setToast(L10n.instance.tr('share.could_not_start_file_sharing') + e.toString());
      return;
    }
    shareExplicit = true;
    if (announce) {
      settings.shareOnStart = true;
      await saveSettings();
      if (!quiet) _setToast(L10n.instance.tr('share.file_sharing_is_on'));
    }
    _bump();
  }

  Future<void> stopShare() async {
    await share?.stop();
    share?.uploadDir = '';
    shareExplicit = false;
    settings.shareOnStart = false;
    await saveSettings();
    _bump();
  }

  bool get shareRunning => share?.running ?? false;
  int get sharePortActual => share?.port ?? 0;

  List<String> shareUrls() {
    final s = share;
    if (s == null || !s.running) return [];
    return s.urls(localIps);
  }

  String shareUrl() {
    final urls = shareUrls();
    return urls.isEmpty ? '' : urls.first;
  }

  Future<void> sendClipboardImage() async {
    var data = await MobileBridge.clipboardImage();
    if (data == null || data.isEmpty) {
      _setToast(L10n.instance.tr('image.no_image_in_the_clipboard'));
      return;
    }
    final dir = Directory(p.join(paths.cacheDir, 'pasted'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${newId('img')}.png'));
    await file.writeAsBytes(data, flush: true);
    await sendFiles([file.path]);
  }

  Future<int> sendFiles(List<String> files) async {
    final c = convs[activeConvId];
    if (c == null) {
      _setToast(L10n.instance.tr('chat.open_a_chat_first'));
      return 0;
    }
    if (files.isEmpty) return 0;
    final tcpReady = await ensureTransfer();
    final httpReady = await ensureShareServer();
    if (!tcpReady && !httpReady) {
      _setToast(L10n.instance.tr('ui.file_transfer_service_is_not_running_cannot_send_file'));
      return 0;
    }
    var added = 0;
    for (final path in files) {
      try {
        final stat = await File(path).stat();
        if (stat.type != FileSystemEntityType.file) continue;
      } catch (_) {
        continue;
      }
      FileMeta? file;
      if (tcpReady) {
        try {
          final tr = await transfer!.add(path);
          file = FileMeta(
            name: tr.name,
            size: tr.size,
            mime: tr.mime,
            token: tr.token,
            path: path,
          );
        } catch (_) {}
      }
      if (httpReady) {
        try {
          final st = await share!.addTransfer(path);
          if (file == null) {
            file = FileMeta(
              name: st.name,
              size: st.size,
              mime: st.mime,
              path: path,
            );
          } else {
            file.url = share!.transferUrl(
              share!.primaryHost(localIps),
              st,
              localIps,
            );
          }
        } catch (_) {}
      }
      if (file == null) continue;
      var kind = MessageKind.file;
      if (file.mime.toLowerCase().startsWith('image/')) {
        kind = MessageKind.image;
        try {
          final bytes = await File(path).readAsBytes();
          final dims = await imageDimensions(bytes);
          if (dims != null) {
            file.width = dims.$1;
            file.height = dims.$2;
          }
        } catch (_) {}
      }
      final m = Message(
        id: newId('m'),
        convId: c.id,
        senderId: profile.id,
        senderName: profile.name,
        kind: kind,
        file: file,
        sentAt: DateTime.now(),
        status: 'sent',
        mine: true,
      );
      if (file.token.isNotEmpty) sendTokenMap[file.token] = m.id;
      final shareToken = shareTokenFromUrl(file.url);
      if (shareToken != null) sendTokenMap[shareToken] = m.id;
      sends[m.id] = SendProgress(total: file.size);
      addLocalMessage(c, m);
      added++;
    }
    if (added == 0) {
      _setToast(L10n.instance.tr('ui.no_files_to_send'));
    }
    return added;
  }

  void _onTransferProgress(String token, int sent, int total, String? error) {
    _applySendProgress(token, 'TCP', sent, total, error);
  }

  void _onShareProgress(String token, int sent, int total, String? error) {
    _applySendProgress(token, 'HTTP', sent, total, error);
  }

  void _applySendProgress(
    String token,
    String transport,
    int sent,
    int total,
    String? error,
  ) {
    final msgId = sendTokenMap[token];
    if (msgId == null) return;
    final st = sends.putIfAbsent(msgId, () => SendProgress());
    final now = DateTime.now();
    if (error != null) {
      st.sent = sent;
      st.total = total;
      st.error = _transferErrorText(error);
      st.working = false;
      st.done = false;
      st.speed = 0;
      st.transport = transport;
      st.lastAt = DateTime.fromMillisecondsSinceEpoch(0);
      st.lastSent = sent;
      _bump();
      return;
    }
    final resumed = st.error.isNotEmpty || (st.lastSent > 0 && sent < st.lastSent);
    if (st.lastAt.millisecondsSinceEpoch == 0 || resumed) {
      st.lastAt = now;
      st.lastSent = sent;
      st.speed = 0;
    } else if (sent > st.lastSent) {
      var dt = now.difference(st.lastAt).inMicroseconds / 1e6;
      if (dt < 0.001) dt = 0.001;
      final inst = (sent - st.lastSent) / dt;
      st.speed = st.speed == 0 ? inst : st.speed * 0.7 + inst * 0.3;
      st.lastAt = now;
      st.lastSent = sent;
    }
    st.sent = sent;
    st.total = total;
    st.error = '';
    st.transport = transport;
    st.working = total > 0 && sent < total;
    st.done = sent >= total;
    if (st.done) {
      st.working = false;
      st.speed = 0;
    }
    _bump();
  }

  void rebuildSendTokens() {
    sendTokenMap.clear();
    for (final list in msgs.values) {
      for (final m in list) {
        if (!m.mine || m.file == null) continue;
        if (m.file!.token.isNotEmpty) sendTokenMap[m.file!.token] = m.id;
        final tok = shareTokenFromUrl(m.file!.url);
        if (tok != null) sendTokenMap[tok] = m.id;
      }
    }
  }

  String _transferErrorText(String codeOrMessage) {
    switch (codeOrMessage) {
      case 'bad_request':
        return L10n.instance.tr('ui.bad_request');
      case 'not_found':
        return L10n.instance.tr('ui.file_is_gone_or_the_sender_restarted');
      case 'file_missing':
        return L10n.instance.tr('ui.file_was_moved_or_deleted');
      case 'bad_offset':
        return L10n.instance.tr('ui.invalid_resume_position');
      case 'file_changed':
        return L10n.instance.tr('ui.file_changed');
      case 'io_error':
        return L10n.instance.tr('ui.could_not_read_file');
      case 'checksum_mismatch':
        return L10n.instance.tr('ui.incomplete_receive');
      case 'too_large':
        return L10n.instance.tr('ui.file_too_large');
      case 'busy':
        return L10n.instance.tr('ui.sender_busy');
      default:
        return codeOrMessage;
    }
  }

  void _downloadError(String convId, String msgId, String message) {
    final st = downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
    st.working = false;
    st.error = message;
    st.updatedAt = DateTime.now();
    downloads[msgId] = st;
    _bump();
  }

  void _downloadProgress(String convId, String msgId, int done, int total) {
    final st = downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
    st.working = true;
    st.error = '';
    st.total = total;
    st.value = total > 0 ? (done / total).clamp(0.0, 1.0) : 0;
    st.updatedAt = DateTime.now();
    downloads[msgId] = st;
    _bump();
  }

  void autoDownloadImage(String convId, String msgId) {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return;
    if (m.file!.path.isNotEmpty) return;
    if (m.file!.url.isEmpty && m.file!.token.isEmpty) return;
    final ext = p.extension(sanitizeFileName(m.file!.name));
    final dest = p.join(
      paths.imagesCacheDir,
      '${sha256Hex(m.id)}${ext.isEmpty ? '.img' : ext}',
    );
    downloadTo(convId, msgId, dest, true);
  }

  void queueActiveImages() {
    if (!settings.autoDownloadImages) return;
    final c = convs[activeConvId];
    if (c == null) return;
    for (final m in msgs[c.id] ?? const <Message>[]) {
      if (m.kind == MessageKind.image &&
          m.file != null &&
          m.file!.path.isEmpty &&
          (m.file!.url.isNotEmpty || m.file!.token.isNotEmpty)) {
        autoDownloadImage(c.id, m.id);
      }
    }
  }

  Future<void> downloadMessage(String convId, String msgId) async {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return;
    if (m.file!.path.isNotEmpty && await File(m.file!.path).exists()) {
      _setToast(L10n.instance.tr('ui.downloaded_2'));
      return;
    }
    final name = sanitizeFileName(m.file!.name);
    final dest = await uniquePath(paths.downloadDir, name);
    await downloadTo(convId, msgId, dest, false);
  }

  Future<void> downloadMessageTo(
    String convId,
    String msgId,
    String dest,
  ) async {
    await downloadTo(convId, msgId, dest, false);
  }

  Future<void> downloadTo(
    String convId,
    String msgId,
    String dest,
    bool imageOnly,
  ) async {
    final m = message(convId, msgId);
    if (m == null || m.file == null) return;
    final existing = downloads[msgId];
    if (existing != null && existing.working) return;
    final file = m.file!;
    final st = DownloadState(
      convId: convId,
      messageId: msgId,
      total: file.size,
      working: true,
    );
    downloads[msgId] = st;
    _bump();
    final peer = peers[m.senderId];
    final addr = peer?.transferAddr ?? '';
    if (file.token.isNotEmpty && addr.isNotEmpty) {
      await _downloadSocket(convId, msgId, m, addr, dest, imageOnly);
      return;
    }
    if (file.url.isNotEmpty) {
      await _downloadHttp(convId, msgId, m, file.url, dest, imageOnly);
      return;
    }
    _downloadError(
      convId,
      msgId,
      L10n.instance.tr('ui.cannot_download_sender_is_offline_or_does_not_support_file_transfer'),
    );
  }

  String _partPath(String msgId) =>
      p.join(paths.transfersCacheDir, '${sha256Hex(msgId)}.part');

  Future<void> _downloadSocket(
    String convId,
    String msgId,
    Message m,
    String addr,
    String dest,
    bool imageOnly,
  ) async {
    final fallback = m.file!.url;
    final part = _partPath(msgId);
    RandomAccessFile? raf;
    try {
      await Directory(p.dirname(part)).create(recursive: true);
      var offset = 0;
      final partFile = File(part);
      if (await partFile.exists()) offset = await partFile.length();
      final want = m.file!.size;
      if (want > 0 && offset > want) {
        await partFile.delete();
        offset = 0;
      }
      if (want > 0 && offset == want) {
        await _completeTransfer(convId, msgId, part, dest, offset, imageOnly);
        return;
      }
      raf = await partFile.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final result = await TransferClient.download(
        addr: addr,
        token: m.file!.token,
        offset: offset,
        onData: (chunk) async {
          await raf!.writeFrom(chunk);
        },
        onProgress: (done, total) {
          _downloadProgress(convId, msgId, done, total);
        },
      );
      await raf.flush();
      await raf.close();
      raf = null;
      await _completeTransfer(
        convId,
        msgId,
        part,
        dest,
        result.done,
        imageOnly,
      );
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      if (fallback.isNotEmpty) {
        try {
          final uri = Uri.parse(fallback);
          final host = peer(m.senderId).ip;
          final url = host.isEmpty ? fallback : uri.replace(host: host).toString();
          await _downloadHttp(convId, msgId, m, url, dest, imageOnly);
          return;
        } catch (_) {}
      }
      _downloadError(convId, msgId, _downloadErrorText(e));
    }
  }

  Future<void> _downloadHttp(
    String convId,
    String msgId,
    Message m,
    String url,
    String dest,
    bool imageOnly,
  ) async {
    final want = m.file!.size;
    final part = '$dest.part';
    HttpClient? client;
    RandomAccessFile? raf;
    try {
      await Directory(p.dirname(part)).create(recursive: true);
      var offset = 0;
      final partFile = File(part);
      if (await partFile.exists()) offset = await partFile.length();
      if (want > 0 && offset > want) {
        await partFile.delete();
        offset = 0;
      }
      if (want > 0 && offset == want) {
        await _completeTransfer(convId, msgId, part, dest, offset, imageOnly);
        return;
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(url));
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.partialContent) {
      } else if (response.statusCode == HttpStatus.ok) {
        offset = 0;
        try {
          await partFile.delete();
        } catch (_) {}
      } else if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        if (want > 0 && offset == want) {
          await _completeTransfer(convId, msgId, part, dest, offset, imageOnly);
          return;
        }
        throw StateError('HTTP ${response.statusCode}');
      } else if (response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.gone) {
        throw StateError('HTTP ${response.statusCode}');
      } else {
        throw StateError('HTTP ${response.statusCode}');
      }
      var total = want;
      if (total <= 0 && response.contentLength > 0) {
        total = offset + response.contentLength;
      }
      final st =
          downloads[msgId] ?? DownloadState(convId: convId, messageId: msgId);
      st.total = total;
      st.working = true;
      st.error = '';
      st.transport = 'HTTP';
      st.value = total > 0 ? offset / total : 0;
      downloads[msgId] = st;
      _bump();
      raf = await partFile.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var done = offset;
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in response) {
        await raf.writeFrom(chunk);
        done += chunk.length;
        final now = DateTime.now();
        if (now.difference(last) >= const Duration(milliseconds: 150) ||
            (total > 0 && done >= total)) {
          last = now;
          _downloadProgress(convId, msgId, done, total);
        }
      }
      await raf.flush();
      await raf.close();
      raf = null;
      if (want > 0 && done != want) {
        try {
          await partFile.delete();
        } catch (_) {}
        throw StateError(
          L10n.instance.tr('share.size_mismatch_recv') +
              done.toString() +
              L10n.instance.tr('comma_expected') +
              want.toString(),
        );
      }
      await _completeTransfer(convId, msgId, part, dest, done, imageOnly);
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      _downloadError(convId, msgId, _downloadErrorText(e));
    } finally {
      client?.close(force: true);
    }
  }

  String _downloadErrorText(Object error) {
    if (error is TransferError) {
      return _transferErrorText(error.code.isEmpty ? error.message : error.code);
    }
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('HTTP 404') || text.contains('HTTP 410')) {
      return L10n.instance.tr('ui.the_file_is_gone_or_has_expired');
    }
    if (text.contains('connection closed') ||
        text.contains('Connection reset') ||
        text.contains('Broken pipe')) {
      return L10n.instance.tr('device.connection_lost');
    }
    return text;
  }

  Future<void> _completeTransfer(
    String convId,
    String msgId,
    String part,
    String dest,
    int done,
    bool imageOnly,
  ) async {
    try {
      final finalPath = await uniquePath(p.dirname(dest), p.basename(dest));
      await Directory(p.dirname(finalPath)).create(recursive: true);
      await moveFile(part, finalPath);
      final m = message(convId, msgId);
      if (m != null && m.file != null) {
        m.file!.path = finalPath;
      }
      downloads.remove(msgId);
      _scheduleMessageSave(convId);
      if (!imageOnly) {
        _setToast(L10n.instance.tr('image.saved_to') + finalPath);
      }
      _bump();
    } catch (e) {
      _downloadError(convId, msgId, e.toString());
    }
  }

  void forgetMessageFiles(List<Message> messages) {
    final tcpTokens = <String>[];
    for (final m in messages) {
      final f = m.file;
      if (f == null) continue;
      sends.remove(m.id);
      downloads.remove(m.id);
      if (f.token.isNotEmpty) {
        tcpTokens.add(f.token);
        sendTokenMap.remove(f.token);
      }
      final tok = shareTokenFromUrl(f.url);
      if (tok != null) {
        sendTokenMap.remove(tok);
        share?.removeTransfer(tok);
      }
    }
    if (tcpTokens.isNotEmpty) transfer?.removeMany(tcpTokens);
  }

  // ---------------------------------------------------------------------
  // Profile, settings, network

  Future<void> updateProfile({
    String? name,
    String? signature,
    String? avatar,
    Presence? status,
  }) async {
    if (name != null) profile.name = name.trim();
    if (profile.name.isEmpty) {
      profile.name = L10n.instance.tr('ui.my_zchat');
    }
    if (signature != null) profile.signature = signature.trim();
    if (avatar != null) profile.avatar = avatar;
    if (status != null) {
      profile.status = status;
      settings.status = status;
    }
    node?.setProfile(profile);
    await saveSettings();
    _scheduleStateSave();
    _bump();
  }

  Future<void> setAvatarBytes(List<int> bytes) async {
    final png = await makeAvatarPng(Uint8List.fromList(bytes));
    if (png == null) {
      _setToast(L10n.instance.tr('image.could_not_read_image_2'));
      return;
    }
    await updateProfile(avatar: base64Encode(png));
  }

  Future<void> clearAvatar() => updateProfile(avatar: '');

  Future<void> setStatus(Presence status) async {
    profile.status = status;
    settings.status = status;
    node?.setStatus(status);
    await saveSettings();
    _scheduleStateSave();
    _bump();
  }

  Future<void> setAppearance(String appearance) async {
    settings.appearance = appearance;
    await saveSettings();
    _bump();
  }

  Future<void> setLanguage(String language) async {
    settings.language = language;
    L10n.instance.language = language;
    await saveSettings();
    _bump();
  }

  Future<void> setNotifications(bool value) async {
    settings.notifications = value;
    await saveSettings();
    _bump();
  }

  Future<void> setAutoDownloadImages(bool value) async {
    settings.autoDownloadImages = value;
    await saveSettings();
    if (value) queueActiveImages();
    _bump();
  }

  Future<void> setHaptics(bool value) async {
    settings.haptics = value;
    await saveSettings();
  }

  Future<void> setKeepAwake(bool value) async {
    settings.keepAwake = value;
    await saveSettings();
    _bump();
  }

  Future<void> setScreenshotEnabled(bool value) async {
    settings.screenshotEnabled = value;
    await saveSettings();
    _bump();
  }

  Future<void> setNotifyPreview(bool value) async {
    settings.notifyPreview = value;
    await saveSettings();
  }

  Future<void> setDiscovery(bool enabled) async {
    settings.discovery = enabled;
    await saveSettings();
    await restartNetwork();
  }

  Future<void> setDownloadDir(String dir) async {
    settings.downloadDir = dir;
    await saveSettings();
    _bump();
  }

  Future<void> setCloseToTray(bool value) async {
    settings.closeToTray = value;
    await saveSettings();
    _bump();
  }

  Future<void> setShareOnStart(bool value) async {
    if (value) {
      await startShare();
    } else {
      settings.shareOnStart = false;
      if (shareRunning) await stopShare();
      await saveSettings();
      _bump();
    }
  }

  String get dataDir => paths.dataDir;

  Future<void> vacuumDatabase() async {
    try {
      await db.vacuum();
      await refreshDbStats();
      _setToast(L10n.instance.tr('ui.database_compacted'));
    } catch (e) {
      _setToast(L10n.instance.tr('ui.could_not_compact_database') + e.toString());
    }
  }

  Future<void> setShareDirs(String shareDir, String uploadDir) async {
    settings.shareDir = shareDir;
    settings.uploadDir = uploadDir;
    final s = share;
    if (s != null) {
      s.dir = await _validDir(shareDir);
      if (s.running) {
        s.uploadDir = await _validDir(uploadDir);
      }
    }
    await saveSettings();
    _bump();
  }

  Future<void> setSharePort(int port) async {
    settings.sharePort = port;
    if (share != null && share!.running) {
      final wasExplicit = shareExplicit;
      await share!.stop();
      try {
        await share!.start(port);
        shareExplicit = wasExplicit;
      } catch (e) {
        _setToast(L10n.instance.tr('share.could_not_start_file_sharing') + e.toString());
      }
    }
    await saveSettings();
    _bump();
  }

  Future<void> setSettings(void Function(Settings s) mutate) async {
    mutate(settings);
    await saveSettings();
    _bump();
  }

  Future<Peer> manualConnect(String addr) async {
    final n = node;
    if (n == null) throw StateError('网络尚未启动');
    final peer = await n.connectAddress(addr);
    peer.manual = true;
    _applyPeer(peer);
    final saved = peers[peer.id];
    if (saved != null) saved.manual = true;
    ensureDirect(peer);
    _scheduleStateSave();
    _bump();
    return peer;
  }

  Future<Peer> connectPeer(String peerId) async {
    final existing = peers[peerId];
    if (existing == null) throw StateError('未知设备');
    if (existing.connected) return existing;
    final n = node;
    if (n == null) throw StateError('网络尚未启动');
    final peer = await n.connectAddress(existing.addr);
    _applyPeer(peer);
    return peer;
  }

  void setAlias(String peerId, String alias) {
    final peer = peers[peerId];
    if (peer == null) return;
    peer.alias = alias.trim();
    node?.rememberPeer(peer);
    _scheduleStateSave();
    _bump();
  }

  void removePeer(String peerId) {
    peers.remove(peerId);
    _scheduleStateSave();
    _bump();
  }

  Map<String, dynamic>? shareTokenForMessage(Message m) {
    final token = m.file?.token;
    if (token != null && token.isNotEmpty) {
      final peer = peers[m.senderId];
      return {
        'kind': 'tcp',
        'token': token,
        'addr': peer?.transferAddr ?? '',
      };
    }
    final shareToken = shareTokenFromUrl(m.file?.url ?? '');
    if (shareToken != null) {
      return {
        'kind': 'http',
        'token': shareToken,
        'url': m.file?.url ?? '',
      };
    }
    return null;
  }

  String shareLinkForMessage(Message m) {
    if (!m.mine || m.file == null) return '';
    final file = m.file!;
    if (file.url.isNotEmpty) return file.url;
    if (file.token.isEmpty || share == null || !share!.running) return '';
    final tr = share!.transferFor(file.token);
    if (tr == null) return '';
    return share!.transferUrl(share!.primaryHost(localIps), tr, localIps);
  }

  static int progressPercent(int sent, int total) {
    if (total <= 0) return 100;
    return math.min(100, math.max(0, (sent * 100 / total).round()));
  }
}
