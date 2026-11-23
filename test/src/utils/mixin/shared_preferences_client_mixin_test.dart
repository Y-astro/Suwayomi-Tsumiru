import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Count platform persistence calls without touching user preferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:tsumiru/src/constants/db_keys.dart';
import 'package:tsumiru/src/features/settings/presentation/downloads/data/delete_chapters_settings_repository.dart';
import 'package:tsumiru/src/features/settings/widgets/app_theme_mode_tile/app_theme_mode_tile.dart';
import 'package:tsumiru/src/global_providers/global_providers.dart';
import 'package:tsumiru/src/utils/crash/diagnostics.dart';
import 'package:tsumiru/src/utils/mixin/shared_preferences_client_mixin.dart';

class _CountingStore extends InMemorySharedPreferencesStore {
  _CountingStore(super.data) : super.withData();
  int writes = 0;
  int removals = 0;
  final values = <Object>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writes++;
    values.add(value);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    removals++;
    return super.remove(key);
  }
}

final _listProvider =
    NotifierProvider.autoDispose<_ListPreference, List<String>?>(
      _ListPreference.new,
    );

class _ListPreference extends Notifier<List<String>?>
    with SharedPreferenceClientMixin<List<String>> {
  @override
  List<String>? build() => initialize(DBKeys.badgeOrder);
}

class _ScalarPreference<T extends Object> extends Notifier<T?>
    with SharedPreferenceClientMixin<T> {
  _ScalarPreference(this.key);
  final DBKeys key;

  @override
  T? build() => initialize(key);
}

final _jsonProvider =
    NotifierProvider.autoDispose<_JsonPreference, ({int count})?>(
      _JsonPreference.new,
    );

class _JsonPreference extends Notifier<({int count})?>
    with SharedPreferenceClientMixin<({int count})> {
  @override
  ({int count})? build() => initialize(
    DBKeys.l10n,
    initial: (count: 0),
    toJson: (value) => {'count': value.count},
    fromJson: (value) => (count: (value as Map)['count'] as int),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CountingStore store;
  late SharedPreferences preferences;
  late ProviderContainer container;
  late List<String> diagnostics;

  Future<void> initialize(Map<String, Object> data) async {
    SharedPreferences.setMockInitialValues({});
    final previousStore = SharedPreferencesStorePlatform.instance;
    store = _CountingStore({
      for (final e in data.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = store;
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    diagnostics = [];
    setDiagnosticSink(diagnostics.add);
    addTearDown(() {
      container.dispose();
      setDiagnosticSink(null);
      SharedPreferencesStorePlatform.instance = previousStore;
    });
  }

  test(
    '1000 autoDispose recreations do not rewrite stored deletion settings',
    () async {
      await initialize({
        'localDeleteWhileReading': 2,
        'localDeleteManuallyMarkedRead': true,
        'localDeleteWithBookmark': false,
      });
      final elapsed = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        expect(
          container.read(localDeleteSettingsProvider).deleteWhileReading,
          2,
        );
        await container.pump();
      }
      elapsed.stop();
      // ignore: avoid_print
      print(
        '1000 preference recreations: ${store.writes} writes, ${elapsed.elapsedMicroseconds} us',
      );
      expect(store.writes, 0);
      expect(diagnostics, isEmpty);
    },
  );

  test(
    'missing defaults persist once; changes and removals still persist',
    () async {
      await initialize({});
      container.read(localDeleteSettingsProvider);
      await container.pump();
      expect(store.writes, 3);
      container.read(localDeleteSettingsProvider);
      await container.pump();
      expect(store.writes, 3);
      final subscription = container.listen(
        localDeleteWhileReadingProvider,
        (_, _) {},
      );
      container.read(localDeleteWhileReadingProvider.notifier).update(4);
      await container.pump();
      expect(preferences.getInt('localDeleteWhileReading'), 4);
      expect(store.writes, 4);
      container.read(localDeleteWhileReadingProvider.notifier).update(null);
      await container.pump();
      expect(preferences.containsKey('localDeleteWhileReading'), isFalse);
      expect(store.removals, 1);
      subscription.close();
    },
  );

  test(
    'enum, list and JSON storage suppress duplicates and preserve edits',
    () async {
      await initialize({
        'themeMode': ThemeMode.dark.index,
        'badgeOrder': <String>['onDevice'],
        'l10n': '{"count":3}',
      });
      final subscriptions = [
        container.listen(appThemeModeProvider, (_, _) {}),
        container.listen(_listProvider, (_, _) {}),
        container.listen(_jsonProvider, (_, _) {}),
      ];
      container.read(_listProvider.notifier).update(['onDevice']);
      container.read(_jsonProvider.notifier).update((count: 3));
      await container.pump();
      expect(store.writes, 0);
      container.read(appThemeModeProvider.notifier).update(ThemeMode.light);
      container.read(_listProvider.notifier).update(['language', 'onDevice']);
      container.read(_jsonProvider.notifier).update((count: 5));
      await container.pump();
      expect(store.writes, 3);
      expect(preferences.getInt('themeMode'), ThemeMode.light.index);
      expect(preferences.getStringList('badgeOrder'), ['language', 'onDevice']);
      expect(preferences.getString('l10n'), '{"count":5}');
      for (final subscription in subscriptions) {
        subscription.close();
      }
    },
  );

  test(
    'scalar type repairs and rapid ordered changes still reach storage',
    () async {
      await initialize({'readerPadding': 0, 'serverUrl': 'old'});
      final doubles = NotifierProvider<_ScalarPreference<double>, double?>(
        () => _ScalarPreference(DBKeys.readerPadding),
      );
      final strings = NotifierProvider<_ScalarPreference<String>, String?>(
        () => _ScalarPreference(DBKeys.serverUrl),
      );
      expect(container.read(doubles), 0.0);
      expect(container.read(strings), 'old');
      for (final value in [2.0, 3.0, 3.0, 4.0]) {
        container.read(doubles.notifier).update(value);
      }
      container.read(strings.notifier).update('new');
      container.read(strings.notifier).update(null);
      await container.pump();
      expect(store.values, [0.0, 2.0, 3.0, 4.0, 'new']);
      expect(preferences.getDouble('readerPadding'), 4.0);
      expect(preferences.containsKey('serverUrl'), isFalse);
      expect(store.removals, 1);
    },
  );
}
