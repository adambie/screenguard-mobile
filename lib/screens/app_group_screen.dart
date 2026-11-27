import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api_client.dart';
import '../auth_provider.dart';
import '../data_providers.dart';
import '../l10n.dart';
import '../models.dart';
import '../utils.dart';
import '../widgets/app_group_status.dart';
import '../widgets/daily_limits_editor.dart';

class AppGroupScreen extends ConsumerStatefulWidget {
  final String profileId;
  final String groupId;

  const AppGroupScreen({
    super.key,
    required this.profileId,
    required this.groupId,
  });

  @override
  ConsumerState<AppGroupScreen> createState() => _AppGroupScreenState();
}

class _AppGroupScreenState extends ConsumerState<AppGroupScreen> {
  static const _extraTimeSteps = [15, 30, 60, -15];

  bool _adjusting = false;

  void _refresh() => ref.invalidate(appsBoardProvider(widget.profileId));

  // Riverpod's `ref` throws once this widget is disposed, so writes capture
  // the container up front: the board must still refresh (and a 401 still
  // relogin) when the parent leaves the screen before the reply arrives.
  Future<void> _addExtraTime(String date, int minutes) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _adjusting = true);
    try {
      await container.read(apiClientProvider).post(
        '/profiles/${widget.profileId}/app-group-adjustments',
        {'group_id': widget.groupId, 'minutes': minutes, 'date': date},
      );
      container.invalidate(appsBoardProvider(widget.profileId));
      if (mounted) _snack(AppLocalizations.of(context).timeAdjusted);
    } on UnauthorizedException {
      container.read(authProvider.notifier).relogin();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _adjusting = false);
    }
  }

  Future<void> _saveLimits(List<DailyLimit> limits) async {
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(apiClientProvider).put(
        '/profiles/${widget.profileId}/app-group-limits/${widget.groupId}',
        {'limits': limits.map((l) => l.toJson()).toList()},
      );
      container.invalidate(appsBoardProvider(widget.profileId));
      if (mounted) _snack(AppLocalizations.of(context).limitsSaved);
    } on UnauthorizedException {
      container.read(authProvider.notifier).relogin();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final boardAsync = ref.watch(appsBoardProvider(widget.profileId));
    ref.listen(appsBoardProvider(widget.profileId), (_, state) {
      if (state.hasError && state.error is UnauthorizedException) {
        ref.read(authProvider.notifier).relogin();
      }
    });

    final titleGroup =
        boardAsync.valueOrNull?.limitableGroup(widget.groupId);

    return Scaffold(
      appBar: AppBar(
        title: Text(titleGroup != null
            ? appGroupDisplayName(l, titleGroup)
            : l.appLimits),
      ),
      // A relogin swaps the API client and reloads the board; keep showing
      // the old data so the limits editor (and its unsaved edits) survives.
      body: boardAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $e'),
              const SizedBox(height: 8),
              TextButton(onPressed: _refresh, child: Text(l.retry)),
            ],
          ),
        ),
        data: (board) {
          final group = board?.limitableGroup(widget.groupId);
          if (board == null || group == null) {
            return Center(child: Text(l.groupNotFound));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTodayCard(context, group, board),
                  const SizedBox(height: 16),
                  DailyLimitsEditor(
                    key: ValueKey(List.generate(7, group.limitFor).join(',')),
                    initialLimits: group.limits,
                    title: l.groupLimits,
                    description: l.groupLimitsDesc,
                    onSave: _saveLimits,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTodayCard(BuildContext context, AppGroup group, AppsBoard board) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final adjustment = group.adjustmentToday;
    final allowedToday = group.allowedMinutesWithAdjustment(board.weekday);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.today, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AppGroupTodayStatus(group: group, weekday: board.weekday),
            if (adjustment != 0) ...[
              const SizedBox(height: 4),
              Text(
                l.timeAdjustment(
                  '${adjustment > 0 ? '+' : '−'}${formatMinutes(adjustment.abs())}',
                ),
                style: TextStyle(
                  color: adjustment > 0 ? Colors.green : cs.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(l.extraTimeToday, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (allowedToday != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in _extraTimeSteps)
                    FilledButton.tonal(
                      // Taking time from a blocked group only builds up debt
                      // that later extra time has to cancel first.
                      onPressed: _adjusting || (minutes < 0 && allowedToday == 0)
                          ? null
                          : () => _addExtraTime(board.today, minutes),
                      child: Text(
                        '${minutes > 0 ? '+' : '−'}${formatMinutes(minutes.abs())}',
                      ),
                    ),
                ],
              )
            else
              Text(
                l.extraTimeNeedsLimit,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
