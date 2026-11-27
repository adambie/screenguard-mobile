import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../utils.dart';

/// The server seeds builtin groups with English names; translate them only
/// while the parent has not renamed the group.
String appGroupDisplayName(AppLocalizations l, AppGroup group) {
  if (group.builtin == 'games' && group.name == 'Games') return l.groupGames;
  if (group.builtin == 'browsers' && group.name == 'Web browsers') {
    return l.groupBrowsers;
  }
  return group.name;
}

/// Today's state of [group]: blocked, time used against the adjusted limit
/// with a progress bar, or no limit.
class AppGroupTodayStatus extends StatelessWidget {
  final AppGroup group;
  final int weekday;

  const AppGroupTodayStatus({
    super.key,
    required this.group,
    required this.weekday,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final secondary = TextStyle(color: cs.onSurfaceVariant);
    final usedSeconds = group.todaySeconds;
    final used = formatMinutes(usedSeconds ~/ 60);
    final allowed = group.allowedMinutesWithAdjustment(weekday);

    if (allowed == null) {
      return Text(
        usedSeconds > 0 ? '${l.noLimit} · ${l.usedOf(used)}' : l.noLimit,
        style: secondary,
      );
    }
    if (allowed == 0) {
      return Text(
        l.blocked,
        style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
      );
    }

    final allowedSeconds = allowed * 60;
    final exhausted = usedSeconds >= allowedSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          exhausted
              ? l.usedOfLimit(used, formatMinutes(allowed))
              : '${l.usedOfLimit(used, formatMinutes(allowed))} · '
                  '${l.timeLeft(formatMinutes(((allowedSeconds - usedSeconds) / 60).ceil()))}',
          style: secondary,
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: (usedSeconds / allowedSeconds).clamp(0.0, 1.0),
          color: exhausted ? cs.error : null,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
