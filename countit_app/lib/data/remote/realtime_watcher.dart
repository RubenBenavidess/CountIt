import 'dart:async';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/logging/app_logger.dart';

/// Rows of one table that a subscription follows: `<column> = <value>`.
class RealtimeTopic {
  const RealtimeTopic({required this.table, required this.column, required this.value});

  /// Table of the `public` schema published in Realtime (`families`, `notifications`).
  final String table;
  final String column;
  final Object value;
}

/// A live subscription opened by a [RealtimeOpener]; [close] releases it.
abstract interface class RealtimeHandle {
  Future<void> close();
}

/// Opens one subscription: [onChange] for every row change, [onStatus] for
/// every channel status (joined, error, timeout, closed).
typedef RealtimeOpener = RealtimeHandle Function(
  RealtimeTopic topic, {
  required void Function() onChange,
  required void Function(RealtimeSubscribeStatus status) onStatus,
});

/// Change signals of a Realtime table, for repositories (Cubits never see
/// Supabase). The payload is ignored on purpose: Realtime sends whole rows
/// and the RLS of the table decides which ones; the screens reload from the
/// API views, which are the contract.
abstract interface class RealtimeWatcher {
  /// Emits when a row of [topic] changes and every time the channel (re)joins:
  /// changes missed while disconnected are recovered by reloading. Cancelling
  /// the subscription closes the channel.
  Stream<void> watch(RealtimeTopic topic);
}

/// [RealtimeWatcher] over `supabase.channel(...).onPostgresChanges(...)`.
///
/// The Realtime client rejoins a channel by itself after a dropped socket
/// (each rejoin reports `subscribed` again → a reload signal). A channel that
/// fails (`channelError`, e.g. a token that expired while asleep) or times out
/// is replaced by a new one after [retryDelays] (the last delay repeats), so
/// the stream heals without the screen doing anything.
class SupabaseRealtimeWatcher implements RealtimeWatcher {
  SupabaseRealtimeWatcher(SupabaseClient client, {this.retryDelays = defaultRetryDelays})
    : _open = _supabaseOpener(client);

  /// For tests: drives the statuses without a socket.
  SupabaseRealtimeWatcher.withOpener(this._open, {this.retryDelays = defaultRetryDelays});

  static const defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final RealtimeOpener _open;
  final List<Duration> retryDelays;

  static int _sequence = 0;

  static RealtimeOpener _supabaseOpener(SupabaseClient client) => (topic, {required onChange, required onStatus}) {
    // A unique, data-free channel name: user ids never travel in topics.
    final channel = client
        .channel('${topic.table}-${_sequence++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: topic.table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: topic.column, value: topic.value),
          callback: (_) => onChange(),
        )
        .subscribe((status, _) => onStatus(status));
    return _ChannelHandle(client, channel);
  };

  @override
  Stream<void> watch(RealtimeTopic topic) {
    late final StreamController<void> controller;
    RealtimeHandle? handle;
    Object? active;
    Timer? retry;
    var failures = 0;
    var closed = false;

    void open() {
      if (closed) return;
      // Every channel reports with its own token: a late status of a
      // replaced channel never touches the current one.
      final token = Object();
      active = token;
      bool current() => !closed && identical(active, token);
      handle = _open(
        topic,
        onChange: () {
          if (current()) controller.add(null);
        },
        onStatus: (status) {
          if (!current()) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              failures = 0;
              controller.add(null);
            case RealtimeSubscribeStatus.channelError || RealtimeSubscribeStatus.timedOut:
              AppLogger.debug('realtime ${topic.table} ${status.name}; retrying');
              active = null;
              final old = handle;
              handle = null;
              if (old != null) unawaited(old.close());
              final delay = retryDelays[math.min(failures, retryDelays.length - 1)];
              failures++;
              retry?.cancel();
              retry = Timer(delay, open);
            case RealtimeSubscribeStatus.closed:
              break;
          }
        },
      );
    }

    controller = StreamController<void>(
      onListen: open,
      onCancel: () async {
        closed = true;
        retry?.cancel();
        final old = handle;
        handle = null;
        if (old != null) await old.close();
      },
    );
    return controller.stream;
  }
}

class _ChannelHandle implements RealtimeHandle {
  _ChannelHandle(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_channel);
    } catch (_) {
      // Already gone with the socket: nothing left to release.
    }
  }
}
