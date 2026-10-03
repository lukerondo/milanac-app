import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/profile.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

/// Richiesta di accesso: il Direttivo sceglie squadra e ruolo, poi approva o rifiuta.
class PendingRequestTile extends ConsumerStatefulWidget {
  const PendingRequestTile({super.key, required this.member});
  final Member member;

  @override
  ConsumerState<PendingRequestTile> createState() => _PendingRequestTileState();
}

class _PendingRequestTileState extends ConsumerState<PendingRequestTile> {
  bool _busy = false;
  late Set<Team> _teams = widget.member.teams;

  static String _label(ClubRole r) =>
      r == ClubRole.direttivo ? 'Direttivo' : 'Giocatore';

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Operazione non riuscita: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _approve(ClubRole role) {
    final m = widget.member;
    _run(
      () => ref
          .read(rosaRepositoryProvider)
          .save(
            m.copyWith(role: role, joinedAt: DateTime.now(), teams: _teams),
          ),
      '${m.displayName} approvato come ${_label(role)} '
      '(${_teams.map((t) => t.label).join(' e ')}).',
    );
  }

  Future<void> _reject() async {
    final m = widget.member;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Rifiutare ${m.displayName}?'),
        content: const Text('Non potrà accedere all\'app del club.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Rifiuta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(rosaRepositoryProvider).remove(m.id),
      'Richiesta di ${m.displayName} rifiutata.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final requested = m.requestedRole;
    final other = requested == ClubRole.direttivo
        ? ClubRole.giocatore
        : ClubRole.direttivo;
    return Card(
      color: MilanacColors.surfaceHigh,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: MilanacColors.gold,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          'Chiede di entrare come ${_label(requested)}',
                          if (m.gamertag != null && m.gamertag!.isNotEmpty)
                            m.gamertag!,
                        ].join(' · '),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Squadra',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TeamsPicker(
              value: _teams,
              onChanged: (t) => setState(() => _teams = t),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy ? null : _reject,
                  child: const Text('Rifiuta'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _approve(other),
                  child: Text('Approva come ${_label(other)}'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _approve(requested),
                  child: Text('Approva come ${_label(requested)}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
