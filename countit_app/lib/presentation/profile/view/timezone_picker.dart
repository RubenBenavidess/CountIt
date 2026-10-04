import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/theme/tokens.dart';
import '../../../shared/utils/dates.dart';
import '../../../shared/widgets/app_dialogs.dart';

/// Searchable IANA time-zone list with each zone's current time (COU-145).
/// America/Guayaquil (the business default) is listed first.
Future<String?> pickTimezone(BuildContext context, {required String current}) {
  return showAppBottomSheet<String>(
    context,
    title: 'Zona horaria',
    builder: (_) => _TimezoneList(current: current),
  );
}

/// IANA names known to the app (same database the backend validates against).
List<String> timezoneNames() {
  final names = tz.timeZoneDatabase.locations.keys.where((name) => name.contains('/')).toList()..sort();
  names
    ..remove(Dates.defaultTimezone)
    ..insert(0, Dates.defaultTimezone);
  return names;
}

class _TimezoneList extends StatefulWidget {
  const _TimezoneList({required this.current});

  final String current;

  @override
  State<_TimezoneList> createState() => _TimezoneListState();
}

class _TimezoneListState extends State<_TimezoneList> {
  late final List<String> _all = timezoneNames();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase().replaceAll(' ', '_');
    final matches = query.isEmpty ? _all : _all.where((name) => name.toLowerCase().contains(query)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        spacing: AppSpacing.md,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Buscar ciudad o región', prefixIcon: Icon(Icons.search)),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          Expanded(
            // ~400 zones: built lazily, one row per visible item.
            child: ListView.builder(
              itemCount: matches.length,
              itemExtent: 56,
              itemBuilder: (context, index) {
                final name = matches[index];
                final selected = name == widget.current;
                return ListTile(
                  title: Text(name.replaceAll('_', ' '), style: AppTypography.body),
                  trailing: Text(
                    Dates.time(Dates.inUserZone(DateTime.now(), name)),
                    style: AppTypography.caption.copyWith(color: AppColors.muted),
                  ),
                  leading: selected ? const Icon(Icons.check_rounded, color: AppColors.lavender) : null,
                  selected: selected,
                  onTap: () => Navigator.of(context).pop(name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
