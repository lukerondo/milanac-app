import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../shared/member_photo.dart';
import '../rosa/member.dart';
import 'attendance.dart';

/// Colori degli stati delle presenze dal tema in uso: colore (testo e icona) e fondo.
/// L'assenza automatica ("non ha risposto") resta grigia.
extension AttendanceColors on AppPalette {
  Color status(AttendanceStatus? s, {bool auto = false}) => switch (s) {
    AttendanceStatus.presente => success,
    AttendanceStatus.ritardo => warning,
    AttendanceStatus.assente => auto ? textMuted : danger,
    null => textMuted,
  };

  Color statusBg(AttendanceStatus? s) => switch (s) {
    AttendanceStatus.presente => successBg,
    AttendanceStatus.ritardo => warningBg,
    AttendanceStatus.assente => dangerBg,
    null => surfaceHigh,
  };
}

/// L'icona di ogni stato: sempre insieme al colore e alla parola.
IconData statusIcon(AttendanceStatus s) => switch (s) {
  AttendanceStatus.presente => Icons.check_rounded,
  AttendanceStatus.ritardo => Icons.schedule_rounded,
  AttendanceStatus.assente => Icons.close_rounded,
};

/// Pulsante di una risposta: colore, icona e parola insieme. Con l'icona sopra la
/// parola (Home) oppure sulla stessa riga, più basso ([inline], Presenze: "Ritardo").
class AttendanceStatusButton extends StatelessWidget {
  const AttendanceStatusButton({
    super.key,
    required this.status,
    required this.selected,
    this.onPressed,
    this.inline = false,
  });
  final AttendanceStatus status;

  /// La risposta data: fondo e bordo del suo colore.
  final bool selected;
  final VoidCallback? onPressed;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onPressed != null;
    final color = enabled || selected ? p.status(status) : p.textDisabled;
    final background = selected ? p.statusBg(status) : p.surfaceHigh;
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        inline && status == AttendanceStatus.ritardo ? 'Ritardo' : status.label,
        maxLines: 1,
      ),
    );
    final icon = Icon(statusIcon(status), size: inline ? 20 : 22);
    return OutlinedButton(
      onPressed: enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, inline ? 56 : 64),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: background,
        foregroundColor: color,
        disabledBackgroundColor: background,
        disabledForegroundColor: color,
        side: BorderSide(
          color: selected
              ? p.status(status)
              : enabled
              ? p.borderStrong
              : p.border,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: bodyFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: inline
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 6),
                Flexible(child: label),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [icon, const SizedBox(height: 2), label],
            ),
    );
  }
}

/// I tre pulsanti di risposta affiancati.
class AttendanceButtons extends StatelessWidget {
  const AttendanceButtons({
    super.key,
    required this.selected,
    required this.onAnswer,
    this.inline = false,
  });

  /// La risposta già data (null = nessuna).
  final AttendanceStatus? selected;

  /// null = risposte chiuse (pulsanti spenti).
  final ValueChanged<AttendanceStatus>? onAnswer;
  final bool inline;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, s) in AttendanceStatus.values.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: AttendanceStatusButton(
            status: s,
            selected: selected == s,
            inline: inline,
            onPressed: onAnswer == null ? null : () => onAnswer!(s),
          ),
        ),
      ],
    ],
  );
}

/// Titolo di un elenco della serata ("PRESENTI · 2") nel colore del suo stato.
class AttendanceGroupLabel extends StatelessWidget {
  const AttendanceGroupLabel({
    super.key,
    required this.title,
    required this.count,
    this.status,
    this.color,
  });
  final String title;
  final int count;

  /// null = senza risposta (grigio).
  final AttendanceStatus? status;

  /// Colore diverso da quello dello stato (es. oro per ciò che va sistemato).
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    '${title.toUpperCase()} · $count',
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: color ?? context.pal.status(status),
    ),
  );
}

/// Ruolo in campo e numero di maglia ("ATT · 9"), se ci sono.
String? memberRoleLabel(Member m) {
  final parts = [
    if (m.fieldPosition != null && m.fieldPosition!.isNotEmpty)
      m.fieldPosition!,
    if (m.shirtNumber != null) '${m.shirtNumber}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Riga di un giocatore negli elenchi delle presenze: foto, nome, dettaglio
/// (orario o motivo) e a destra ruolo e numero (o quello che serve).
class AttendanceMemberRow extends StatelessWidget {
  const AttendanceMemberRow({
    super.key,
    required this.member,
    this.isMe = false,
    this.detail,
    this.detailColor,
    this.trailing,
    this.onTap,
  });
  final Member member;
  final bool isMe;
  final String? detail;
  final Color? detailColor;

  /// Di solito ruolo e numero ([memberRoleLabel]).
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              MemberAvatar(member: member, radius: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isMe ? '${member.displayName} (tu)' : member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    if (detail != null && detail!.isNotEmpty)
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: detailColor ?? p.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Testo piccolo grigio a destra di una riga (ruolo e numero).
class RowTrailingText extends StatelessWidget {
  const RowTrailingText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 14, color: context.pal.textMuted));
}
