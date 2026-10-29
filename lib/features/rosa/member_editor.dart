import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import '../../core/auth/providers.dart';
import '../../core/errors.dart';
import '../../core/teams.dart';
import '../../core/theme.dart';
import 'member.dart';
import 'rosa_repository.dart';

Future<void> showMemberEditor(BuildContext context, Member member) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MemberEditor(member: member),
    );

/// Scheda di modifica di un membro (solo Direttivo).
class _MemberEditor extends ConsumerStatefulWidget {
  const _MemberEditor({required this.member});
  final Member member;

  @override
  ConsumerState<_MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends ConsumerState<_MemberEditor> {
  late final _name = TextEditingController(text: widget.member.displayName);
  late final _gamertag = TextEditingController(text: widget.member.gamertag);
  late final _number = TextEditingController(
    text: widget.member.shirtNumber?.toString(),
  );
  late ClubRole _role = widget.member.role;
  late String? _position = widget.member.fieldPosition;
  late DateTime _joinedAt = widget.member.joinedAt;
  late Set<Team> _teams = widget.member.teams;

  /// Etichette nel Direttivo (Capitano, Reclutatore...): almeno una per il Direttivo.
  late final Set<DirettivoRole> _labels = widget.member.direttivoRoles.toSet();
  bool _labelsMissing = false;
  bool _saving = false;

  bool get _wasDirettivo => widget.member.role == ClubRole.direttivo;

  @override
  void dispose() {
    _name.dispose();
    _gamertag.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save({bool active = true}) async {
    if (_role == ClubRole.direttivo && _labels.isEmpty) {
      setState(() => _labelsMissing = true);
      return;
    }
    setState(() => _saving = true);
    final gamertag = _gamertag.text.trim();
    // Gamertag e numero lasciati vuoti si cancellano davvero.
    final updated = widget.member.copyWith(
      displayName: _name.text.trim().isEmpty
          ? widget.member.displayName
          : _name.text.trim(),
      gamertag: gamertag.isEmpty ? null : gamertag,
      role: _role,
      fieldPosition: _position,
      shirtNumber: int.tryParse(_number.text.trim()),
      joinedAt: _joinedAt,
      active: active,
      teams: _teams,
      direttivoRoles: [
        if (_role == ClubRole.direttivo)
          for (final r in DirettivoRole.values)
            if (_labels.contains(r)) r,
      ],
    );
    try {
      await ref.read(rosaRepositoryProvider).save(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, action: 'Salvataggio non riuscito')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isMe = ref.watch(currentUserIdProvider) == widget.member.id;
    final promoting = !_wasDirettivo && _role == ClubRole.direttivo;
    final demoting = _wasDirettivo && _role != ClubRole.direttivo;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Modifica membro',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            // I limiti sono quelli della tabella `profiles`.
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gamertag,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Gamertag'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _position,
                    decoration: const InputDecoration(
                      labelText: 'Ruolo in campo',
                    ),
                    items: [
                      for (final p in fieldPositions)
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) => setState(() => _position = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _number,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(labelText: 'Numero'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Ruolo nel club'),
            const SizedBox(height: 8),
            SegmentedButton<ClubRole>(
              segments: const [
                ButtonSegment(
                  value: ClubRole.giocatore,
                  label: Text('Giocatore'),
                ),
                ButtonSegment(
                  value: ClubRole.direttivo,
                  label: Text('Direttivo'),
                ),
              ],
              selected: {
                _role == ClubRole.pending ? ClubRole.giocatore : _role,
              },
              onSelectionChanged: (s) => setState(() {
                _role = s.first;
                _labelsMissing = false;
              }),
            ),
            if (_role == ClubRole.direttivo) ...[
              const SizedBox(height: 12),
              Text(
                'Ruoli nel Direttivo (almeno uno)',
                style: TextStyle(fontSize: 14, color: p.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in DirettivoRole.values)
                    FilterChip(
                      label: Text(r.label),
                      selected: _labels.contains(r),
                      onSelected: (on) => setState(() {
                        on ? _labels.add(r) : _labels.remove(r);
                        _labelsMissing = false;
                      }),
                    ),
                ],
              ),
              if (_labelsMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Scegli almeno un ruolo nel Direttivo.',
                    style: TextStyle(fontSize: 14, color: p.danger),
                  ),
                ),
            ],
            if (promoting || demoting) ...[
              const SizedBox(height: 8),
              Text(
                promoting
                    ? 'Con la promozione avrà tutti i poteri del Direttivo: rosa, '
                          'formazione, risultati, presenze di tutti, regolamento e '
                          'Sala Direttivo. Lo saprà dalla Sala Direttivo.'
                    : 'Tornerà giocatore e perderà i poteri del Direttivo.',
                style: TextStyle(fontSize: 14, color: p.textMuted),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Squadra (una o entrambe)'),
            const SizedBox(height: 8),
            TeamsPicker(
              value: _teams,
              onChanged: (t) => setState(() => _teams = t),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text("Data d'ingresso"),
              subtitle: Text(DateFormat('d MMMM yyyy', 'it').format(_joinedAt)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _joinedAt,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _joinedAt = picked);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salva'),
              ),
            ),
            if (widget.member.avatarPath != null && !isMe)
              TextButton(
                onPressed: _saving ? null : _confirmRemovePhoto,
                child: const Text('Togli la foto del profilo'),
              ),
            if (!isMe) ...[
              TextButton(
                onPressed: _saving ? null : () => _confirmRemove(context),
                child: Text(
                  'Rimuovi dalla rosa',
                  style: TextStyle(color: p.danger),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _delete,
                child: Text(
                  'Elimina l\'account',
                  style: TextStyle(color: p.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rimuovere dalla rosa?'),
        content: Text(
          '${widget.member.displayName} non potrà più accedere all\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok == true) await _save(active: false);
  }

  /// Moderazione: la foto sparisce dal profilo (e dallo Storage).
  Future<void> _confirmRemovePhoto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Togliere la foto del profilo?'),
        content: Text(
          'Al posto della foto di ${widget.member.displayName} tornerà il suo '
          'volto disegnato. Potrà caricarne un\'altra dalle Impostazioni.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Togli la foto'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(rosaRepositoryProvider).removePhoto(widget.member);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Foto tolta.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'Foto non tolta'))),
      );
    }
  }

  Future<void> _delete() async {
    if (!await confirmDeleteAccount(context, widget.member) || !mounted) return;
    setState(() => _saving = true);
    final deleted = await deleteMemberAccount(context, ref, widget.member);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }
}

/// Doppia conferma prima di eliminare l'account di un membro: si spiega cosa sparisce
/// e si spunta "Ho capito" prima del pulsante.
Future<bool> confirmDeleteAccount(BuildContext context, Member member) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => _DeleteAccountDialog(member: member),
  );
  return ok ?? false;
}

/// Elimina l'account (solo Direttivo) e lo dice; false se non è riuscito.
Future<bool> deleteMemberAccount(
  BuildContext context,
  WidgetRef ref,
  Member member,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(rosaRepositoryProvider).deleteAccount(member.id);
    messenger.showSnackBar(
      SnackBar(content: Text('Account di ${member.displayName} eliminato.')),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(e, action: 'Account non eliminato')),
      ),
    );
    return false;
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.member});
  final Member member;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final name = widget.member.displayName;
    return AlertDialog(
      // Testo lungo: sui telefoni piccoli il contenuto scorre.
      scrollable: true,
      title: Text('Eliminare l\'account di $name?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'È definitivo: spariscono profilo, carta, foto, presenze e carte '
            'speciali di $name; i suoi messaggi restano senza nome. Per tornare '
            'nel club dovrà registrarsi di nuovo.\n\nSe vuoi solo tenerlo fuori '
            'per un po\', usa "Rimuovi dalla rosa".',
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Ho capito, è definitivo'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          // Rosso del tema con il testo del colore di fondo: leggibile nei due temi.
          style: FilledButton.styleFrom(
            backgroundColor: p.danger,
            foregroundColor: p.bg,
          ),
          onPressed: _understood ? () => Navigator.pop(context, true) : null,
          child: const Text('Elimina l\'account'),
        ),
      ],
    );
  }
}
