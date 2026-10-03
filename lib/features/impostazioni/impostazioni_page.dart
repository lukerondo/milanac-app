import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/providers.dart';
import '../../core/config.dart';
import '../../core/push/device_tokens.dart';
import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../carta/carta_page.dart';
import '../privacy/privacy_page.dart';
import '../rosa/member.dart';
import '../rosa/rosa_repository.dart';

/// Pulsante ingranaggio nella barra in alto.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Impostazioni',
    icon: const Icon(Icons.settings_rounded),
    onPressed: () => Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const ImpostazioniPage())),
  );
}

/// Impostazioni: foto del profilo (usata anche nella carta) e dati anagrafici.
class ImpostazioniPage extends ConsumerWidget {
  const ImpostazioniPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final member = me == null
        ? null
        : ref
              .watch(rosaProvider)
              .value
              ?.where((m) => m.id == me.id)
              .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('IMPOSTAZIONI')),
      body: member == null
          ? const Center(child: CircularProgressIndicator())
          : _ProfileForm(key: ValueKey(member.id), member: member),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.member});
  final Member member;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.member.displayName);
  late final _gamertag = TextEditingController(text: widget.member.gamertag);
  late final _city = TextEditingController(text: widget.member.city);
  late DateTime? _birthDate = widget.member.birthDate;
  late String? _nationality = widget.member.nationality;
  late PreferredFoot? _foot = widget.member.preferredFoot;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _gamertag.dispose();
    _city.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _changePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    // La versione più recente: serve il percorso della foto vecchia da cancellare.
    final current =
        ref
            .read(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
    try {
      final bytes = await file.readAsBytes();
      await ref.read(rosaRepositoryProvider).uploadPhoto(current, bytes);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Foto aggiornata: la vedi anche sulla carta.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Caricamento non riuscito: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _text(_name);
    if (name == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inserisci il tuo nome.')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    // Parte dalla versione più recente (la foto potrebbe essere appena cambiata).
    final current =
        ref
            .read(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
    try {
      await ref
          .read(rosaRepositoryProvider)
          .saveProfile(
            current.withPersonalData(
              displayName: name,
              gamertag: _text(_gamertag),
              birthDate: _birthDate,
              city: _text(_city),
              nationality: _nationality,
              preferredFoot: _foot,
            ),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Dati salvati.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Salvataggio non riuscito: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live =
        ref
            .watch(rosaProvider)
            .value
            ?.where((m) => m.id == widget.member.id)
            .firstOrNull ??
        widget.member;
    final dates = DateFormat('d MMMM yyyy', 'it');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Center(
          child: Stack(
            children: [
              MemberAvatar(member: live, radius: 56, showNumber: false),
              Positioned(
                right: 0,
                bottom: 0,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: MilanacColors.gold,
                    foregroundColor: Colors.black,
                  ),
                  tooltip: 'Cambia foto',
                  onPressed: _uploading ? null : _changePhoto,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'La foto compare in Rosa, in chat e sulla tua carta FUT.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const _SectionTitle('DATI ANAGRAFICI'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome e cognome'),
        ),
        TextField(
          controller: _gamertag,
          decoration: const InputDecoration(labelText: 'Gamertag / ID EA'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_rounded),
          title: Text(
            _birthDate == null
                ? 'Data di nascita'
                : 'Nato il ${dates.format(_birthDate!)}',
          ),
          trailing: _birthDate == null
              ? null
              : IconButton(
                  tooltip: 'Togli la data',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _birthDate = null),
                ),
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: _birthDate ?? DateTime(now.year - 25),
              firstDate: DateTime(1940),
              lastDate: now,
              initialDatePickerMode: DatePickerMode.year,
            );
            if (d != null) setState(() => _birthDate = d);
          },
        ),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Città'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: nationalities.containsKey(_nationality)
              ? _nationality
              : null,
          decoration: const InputDecoration(labelText: 'Nazionalità'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Non indicata')),
            for (final MapEntry(:key, :value) in nationalities.entries)
              DropdownMenuItem(
                value: key,
                child: Text('${flagEmoji(key)}  $value'),
              ),
          ],
          onChanged: (v) => setState(() => _nationality = v),
        ),
        const SizedBox(height: 12),
        const Text('Piede preferito'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final f in PreferredFoot.values)
              ChoiceChip(
                label: Text(f.label),
                selected: _foot == f,
                onSelected: (on) => setState(() => _foot = on ? f : null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Questi dati li vedono solo i membri approvati del club.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Salva i dati'),
          ),
        ),
        const _SectionTitle('CARTA E APP'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.style_rounded, color: MilanacColors.gold),
          title: const Text('La mia carta'),
          subtitle: const Text('Overall, ruolo, stile di gioco, piattaforma'),
          onTap: () => showCardEditor(context, live),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.library_music_rounded),
          title: const Text('Colonna sonora'),
          onTap: () {
            Navigator.of(context).pop();
            context.go('/musica');
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy'),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
        ),
        if (!AppConfig.isDemo)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Esci'),
            onTap: () {
              Navigator.of(context).pop();
              logout(ref);
            },
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: MilanacColors.gold,
      ),
    ),
  );
}
