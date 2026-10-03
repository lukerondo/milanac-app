import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/profile.dart';
import 'member.dart';
import 'rosa_repository.dart';

Future<void> showMemberEditor(BuildContext context, Member member) => showModalBottomSheet(
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
  late final _number = TextEditingController(text: widget.member.shirtNumber?.toString());
  late ClubRole _role = widget.member.role;
  late String? _position = widget.member.fieldPosition;
  late DateTime _joinedAt = widget.member.joinedAt;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _gamertag.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save({bool active = true}) async {
    setState(() => _saving = true);
    final updated = widget.member.copyWith(
      displayName: _name.text.trim().isEmpty ? widget.member.displayName : _name.text.trim(),
      gamertag: _gamertag.text.trim(),
      role: _role,
      fieldPosition: _position,
      shirtNumber: int.tryParse(_number.text),
      joinedAt: _joinedAt,
      active: active,
    );
    try {
      await ref.read(rosaRepositoryProvider).save(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Modifica membro', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 12),
            TextField(
                controller: _gamertag, decoration: const InputDecoration(labelText: 'Gamertag')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _position,
                    decoration: const InputDecoration(labelText: 'Ruolo in campo'),
                    items: [
                      for (final p in fieldPositions) DropdownMenuItem(value: p, child: Text(p)),
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
                ButtonSegment(value: ClubRole.giocatore, label: Text('Giocatore')),
                ButtonSegment(value: ClubRole.direttivo, label: Text('Direttivo')),
              ],
              selected: {_role == ClubRole.pending ? ClubRole.giocatore : _role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
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
            TextButton(
              onPressed: _saving ? null : () => _confirmRemove(context),
              child: const Text('Rimuovi dalla rosa', style: TextStyle(color: Colors.redAccent)),
            ),
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
        content: Text('${widget.member.displayName} non potrà più accedere all\'app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok == true) await _save(active: false);
  }
}
