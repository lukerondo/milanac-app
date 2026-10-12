import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';

/// Mostra un [AsyncValue] senza far sparire i dati:
/// - appena ci sono dati li mostra, anche mentre si ricarica o se l'ultimo
///   aggiornamento è fallito (con una striscia "Connessione persa" e "Riprova");
/// - lo spinner solo al primo caricamento;
/// - l'errore con "Riprova" solo quando non c'è niente da mostrare.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.action = 'Caricamento non riuscito',
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  /// Di solito `() => ref.invalidate(provider)`.
  final VoidCallback? onRetry;
  final Widget? loading;
  final String action;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v.hasValue) {
      final child = data(v.requireValue);
      if (!v.hasError) return child;
      return Stack(
        children: [
          child,
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: _OfflineStrip(onRetry: onRetry, retrying: v.retrying),
          ),
        ],
      );
    }
    if (v.hasError && !v.isLoading) {
      return ErrorRetry(
        message: friendlyError(v.error!, action: action),
        onRetry: onRetry,
      );
    }
    return loading ?? const Center(child: CircularProgressIndicator());
  }
}

/// Messaggio d'errore centrato con il pulsante "Riprova".
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Riprova'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.onRetry, required this.retrying});
  final VoidCallback? onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: scheme.onInverseSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                retrying
                    ? 'Connessione persa: riprovo…'
                    : 'Dati non aggiornati',
                style: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.inversePrimary,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Riprova'),
              ),
          ],
        ),
      ),
    );
  }
}
