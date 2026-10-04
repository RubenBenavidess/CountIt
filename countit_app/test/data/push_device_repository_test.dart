import 'package:countit_app/data/repositories/push_device_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockApiClient api;
  late SupabasePushDeviceRepository devices;

  setUp(() {
    api = MockApiClient();
    devices = SupabasePushDeviceRepository(api);
    when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => <String, dynamic>{});
  });

  test('register_push_device with token and platform (COU-176)', () async {
    await devices.register('tok', 'android');
    verify(() => api.rpc<dynamic>('register_push_device', params: {'p_token': 'tok', 'p_platform': 'android'}))
        .called(1);
  });

  test('unregister_push_device with the token (COU-178)', () async {
    await devices.unregister('tok');
    verify(() => api.rpc<dynamic>('unregister_push_device', params: {'p_token': 'tok'})).called(1);
  });
}
