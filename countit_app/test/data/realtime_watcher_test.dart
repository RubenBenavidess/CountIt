import 'package:countit_app/data/remote/realtime_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Channel implements RealtimeHandle {
  _Channel(this.onChange, this.onStatus);

  final void Function() onChange;
  final void Function(RealtimeSubscribeStatus status) onStatus;
  bool closed = false;

  @override
  Future<void> close() async => closed = true;
}

const _topic = RealtimeTopic(table: 'families', column: 'user_id', value: 'u1');

void main() {
  late List<_Channel> channels;
  late SupabaseRealtimeWatcher watcher;

  setUp(() {
    channels = [];
    watcher = SupabaseRealtimeWatcher.withOpener((topic, {required onChange, required onStatus}) {
      expect(topic, same(_topic));
      final channel = _Channel(onChange, onStatus);
      channels.add(channel);
      return channel;
    }, retryDelays: const [Duration(milliseconds: 5), Duration(milliseconds: 10)]);
  });

  Future<void> settle([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('opens on listen; joining and every change signal a reload', () async {
    var signals = 0;
    final subscription = watcher.watch(_topic).listen((_) => signals++);
    expect(channels, hasLength(1));

    channels.single.onStatus(RealtimeSubscribeStatus.subscribed);
    channels.single.onChange();
    // A rejoin after a dropped socket reports «subscribed» again: reload.
    channels.single.onStatus(RealtimeSubscribeStatus.subscribed);
    await settle();
    expect(signals, 3);
    await subscription.cancel();
  });

  test('a failed channel is replaced after the backoff; the old one stays silent', () async {
    var signals = 0;
    final subscription = watcher.watch(_topic).listen((_) => signals++);
    final first = channels.single;

    first.onStatus(RealtimeSubscribeStatus.channelError);
    expect(first.closed, isTrue);
    await settle(20);
    expect(channels, hasLength(2), reason: 'reopened');

    first.onChange();
    first.onStatus(RealtimeSubscribeStatus.subscribed);
    await settle();
    expect(signals, 0, reason: 'stale channel ignored');

    channels.last.onStatus(RealtimeSubscribeStatus.timedOut);
    await settle(30);
    expect(channels, hasLength(3), reason: 'timeouts retry too');
    channels.last.onStatus(RealtimeSubscribeStatus.subscribed);
    await settle();
    expect(signals, 1);
    await subscription.cancel();
  });

  test('cancelling closes the channel and stops a pending retry', () async {
    final subscription = watcher.watch(_topic).listen((_) {});
    channels.single.onStatus(RealtimeSubscribeStatus.channelError);
    await subscription.cancel();
    await settle(30);
    expect(channels, hasLength(1), reason: 'no reconnection after cancel');

    final again = watcher.watch(_topic).listen((_) {});
    await again.cancel();
    expect(channels.last.closed, isTrue);
  });
}
