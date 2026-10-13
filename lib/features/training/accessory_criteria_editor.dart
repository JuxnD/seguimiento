import 'package:flutter/material.dart';
import 'package:clock/clock.dart';
import '../../domain/accessory_quality_proof.dart';
import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';

class AccessoryCriteriaEditor extends StatelessWidget {
  const AccessoryCriteriaEditor(
      {super.key,
      required this.epochs,
      required this.proofs,
      required this.date,
      required this.onChanged,
      this.allowAlarmRecording = false});
  final Map<String, String> epochs, proofs;
  final DateTime date;
  final bool allowAlarmRecording;
  final Future<void> Function(String id, AccessoryQualityProof proof) onChanged;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final ladder
            in v32AccessoryLadders.where((l) => epochs.containsKey(l.id)))
          _card(context, ladder),
      ]);
  Widget _card(BuildContext context, CoreLadder ladder) {
    final identity = epochs[ladder.id]!;
    final step = int.tryParse(identity.split(':').first);
    if (step == null ||
        step < ladder.bottom ||
        step > ladder.top ||
        !RegExp(r'^\d+:\d+$').hasMatch(identity)) {
      return const Text(
          'Peldaño de origen desconocido; no acredita progresión.');
    }
    final loaded = AccessoryQualityProof.decode(proofs[ladder.id]);
    final p = loaded?.identity == identity
        ? loaded!
        : AccessoryQualityProof(identity: identity);
    Future<void> change(String field, bool? value) async {
      if (field == 'alarm' && value == true && p.alarm != null) {
        showSnack(context,
            'Esta sesión conserva una señal confirmada; no acredita una exposición sin esa señal.');
        return;
      }
      if (field == 'alarm' &&
          value == true &&
          ladder.id == 'seated_soleus' &&
          !dateOnly(clock.now()).isAfter(dateOnly(date))) {
        showSnack(context,
            'Comprueba el Aquiles a la mañana siguiente. Hoy esa evidencia sigue desconocida.');
        return;
      }
      await onChanged(
          ladder.id,
          AccessoryQualityProof(
              identity: identity,
              variantConfirmed: field == 'variant' ? value : p.variantConfirmed,
              pause2Confirmed: field == 'pause' ? value : p.pause2Confirmed,
              relaxed: field == 'relaxed' ? value : p.relaxed,
              alarmFree: field == 'alarm' ? value : p.alarmFree,
              alarm: p.alarm,
              achillesCheckedOn:
                  ladder.id == 'seated_soleus' && field == 'alarm'
                      ? dayKey(clock.now())
                      : p.achillesCheckedOn));
    }

    return AppCard(title: '${ladder.name} · peldaño $step', children: [
      Text(ladder.stepAt(step).prescription),
      if (ladder.stepAt(step).goals.isNotEmpty)
        Text(
            'Para subir: ${ladder.stepAt(step).criterion}. Dos exposiciones seguidas, al menos14días; mantenimiento no suma.'),
      TriToggle(
          label: 'Hice la variante prescrita en todas las series',
          value: p.variantConfirmed,
          onChanged: (v) => change('variant', v)),
      if (ladder.alarm != null) Text(ladder.alarm!),
      if (ladder.id == 'seated_soleus')
        const Text(
            'La comprobación del Aquiles se completa a la mañana siguiente, al revisar esta sesión.'),
      if (ladder.alarm != null &&
          (ladder.id != 'seated_soleus' ||
              dateOnly(clock.now()).isAfter(dateOnly(date))))
        TriToggle(
            label: 'Sin las señales concretas de esta guía',
            value: ladder.id == 'seated_soleus' && p.achillesCheckedOn == null
                ? null
                : p.alarmFree,
            onChanged: (v) => change('alarm', v)),
      if (allowAlarmRecording &&
          ladder.alarm != null &&
          p.alarm == null &&
          (ladder.id != 'seated_soleus' ||
              dateOnly(clock.now()).isAfter(dateOnly(date))))
        TextButton(
          child: const Text('Registrar la señal concreta de esta guía'),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                        title: const Text('Confirmar señal concreta'),
                        content: Text(
                            '${ladder.alarm}\nSe guardará al guardar la sesión. Cancelar la edición no registra nada.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancelar')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Confirmar'))
                        ]));
            if (confirmed != true) return;
            await onChanged(
                ladder.id,
                AccessoryQualityProof(
                    identity: identity,
                    variantConfirmed: p.variantConfirmed,
                    pause2Confirmed: p.pause2Confirmed,
                    relaxed: p.relaxed,
                    alarmFree: false,
                    alarm: AccessoryQualityProof.alarmsByLadder[ladder.id],
                    achillesCheckedOn: ladder.id == 'seated_soleus'
                        ? dayKey(clock.now())
                        : p.achillesCheckedOn));
          },
        ),
      if (ladder.stepAt(step).pauseSec == 2)
        TriToggle(
            label: 'Pausa de2s en cada repetición',
            value: p.pause2Confirmed,
            onChanged: (v) => change('pause', v)),
      if (ladder.stepAt(step).relaxed)
        TriToggle(
            label: 'Técnica relajada en todas las repeticiones',
            value: p.relaxed,
            onChanged: (v) => change('relaxed', v)),
    ]);
  }
}
