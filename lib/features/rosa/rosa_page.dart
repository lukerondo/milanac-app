import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/theme.dart';
import 'member.dart';
import 'member_editor.dart';
import 'rosa_repository.dart';

class RosaPage extends ConsumerWidget {
  const RosaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDirettivo = ref.watch(profileProvider).value?.isDirettivo ?? false;
    final rosa = ref.watch(rosaProvider);

    return rosa.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Errore nel caricamento della rosa.\n$e')),
      data: (all) {
        final active = all.where((m) => m.active).toList();
        final pending = active.where((m) => m.role == ClubRole.pending).toList();
        final direttivo = active.where((m) => m.role == ClubRole.direttivo).toList();
        final giocatori = active.where((m) => m.role == ClubRole.giocatore).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _Summary(total: direttivo.length + giocatori.length, direttivo: direttivo.length),
            if (isDirettivo && pending.isNotEmpty) ...[
              const _Header('Richieste di accesso', icon: Icons.person_add_alt_1_rounded),
              for (final m in pending) _PendingTile(member: m),
            ],
            const _Header('Direttivo', icon: Icons.star_rounded),
            for (final m in direttivo) _MemberTile(member: m, editable: isDirettivo),
            const _Header('Giocatori', icon: Icons.sports_soccer_rounded),
            if (giocatori.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nessun giocatore in rosa.', style: TextStyle(color: Colors.white54)),
              ),
            for (final m in giocatori) _MemberTile(member: m, editable: isDirettivo),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.direttivo});
  final int total;
  final int direttivo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(child: _Stat(value: '$total', label: 'Tesserati')),
            Expanded(child: _Stat(value: '$direttivo', label: 'Direttivo')),
            Expanded(child: _Stat(value: '${total - direttivo}', label: 'Giocatori')),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, color: MilanacColors.gold)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60)),
        ],
      );
}

class _Header extends StatelessWidget {
  const _Header(this.title, {required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: MilanacColors.red),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ),
          ],
        ),
      );
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.editable});
  final Member member;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = DateFormat('d MMM yyyy', 'it').format(member.joinedAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _ShirtBadge(number: member.shirtNumber, avatarUrl: member.avatarUrl),
        title: Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            if (member.gamertag != null) member.gamertag!,
            'Dal $joined',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RoleChip(member.roleLabel, highlight: member.role == ClubRole.direttivo),
            if (member.fieldPosition != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(member.fieldPosition!,
                    style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        onTap: editable ? () => showMemberEditor(context, member) : null,
      ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(rosaRepositoryProvider);
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
                const Icon(Icons.hourglass_top_rounded, color: MilanacColors.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(member.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => repo.remove(member.id),
                  child: const Text('Rifiuta'),
                ),
                FilledButton(
                  onPressed: () => repo.save(
                    member.copyWith(role: ClubRole.giocatore, joinedAt: DateTime.now()),
                  ),
                  child: const Text('Approva'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShirtBadge extends StatelessWidget {
  const _ShirtBadge({this.number, this.avatarUrl});
  final int? number;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null) {
      return CircleAvatar(radius: 22, backgroundImage: NetworkImage(avatarUrl!));
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: MilanacColors.red,
      child: Text(number?.toString() ?? '–',
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip(this.label, {required this.highlight});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: highlight ? MilanacColors.gold : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: highlight ? Colors.black : Colors.white,
            )),
      );
}
