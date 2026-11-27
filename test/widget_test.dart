import 'package:flutter_test/flutter_test.dart';
import 'package:screenguard/models.dart';

void main() {
  test('profile defaults preserve tasks on lock to false when absent', () {
    final profile = Profile.fromJson({
      'profile': {'id': 'profile-id', 'display_name': 'Test'},
      'schedules': [],
      'daily_limits': [],
      'agent_users': [],
    });

    expect(profile.preserveTasksOnLock, isFalse);
  });

  test('profile parses preserve tasks on lock when enabled', () {
    final profile = Profile.fromJson({
      'profile': {'id': 'profile-id', 'display_name': 'Test'},
      'preserve_tasks_on_lock': true,
      'schedules': [],
      'daily_limits': [],
      'agent_users': [],
    });

    expect(profile.preserveTasksOnLock, isTrue);
  });

  test('unlock reverses the current negative net adjustment', () {
    expect(unlockAdjustmentFor(-90), 90);
  });

  test('unlock is unavailable without a negative net adjustment', () {
    expect(unlockAdjustmentFor(0), 0);
    expect(unlockAdjustmentFor(30), 0);
  });

  test('apps board parses groups and applies today\'s adjustment', () {
    final board = AppsBoard.fromJson({
      'today': '2026-11-27',
      'weekday': 4,
      'apps': [],
      'groups': [
        {
          'id': 'g-games',
          'name': 'Games',
          'builtin': 'games',
          'rules': [],
          'limits': [
            {'day_of_week': 4, 'allowed_minutes': 60},
          ],
          'adjustment_today': -75,
          'today_seconds': 1200,
        },
        {
          'id': 'g-blocked',
          'name': 'Blocked',
          'builtin': 'blocked',
          'rules': [],
          'limits': [],
          'adjustment_today': 0,
          'today_seconds': 0,
        },
      ],
    });

    expect(board.weekday, 4);
    expect(board.limitableGroups.map((g) => g.id), ['g-games']);
    expect(board.limitableGroup('g-blocked'), isNull);
    final games = board.limitableGroup('g-games')!;
    expect(games.todaySeconds, 1200);
    expect(games.limitFor(4), 60);
    expect(games.limitFor(5), isNull);
    expect(games.allowedMinutesWithAdjustment(4), 0);
    expect(games.allowedMinutesWithAdjustment(5), isNull);
  });
}
