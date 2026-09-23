import 'package:flutter/material.dart';

/// Tarjeta principal de cada pestaña, con el mismo lenguaje que Hoy: degradado
/// del color de la sección, rótulo en mayúsculas, icono en recuadro y título
/// grande. Lo importante de la pantalla va aquí.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.color,
    this.overline,
    this.title,
    this.subtitle,
    this.icon,
    this.pills = const [],
    this.trailing,
    this.children = const [],
  });

  final Color color;
  final String? overline;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> pills;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.22), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overline != null || pills.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    if (overline != null)
                      Expanded(
                        child: Text(overline!.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(letterSpacing: 1)),
                      )
                    else
                      const Spacer(),
                    for (var i = 0; i < pills.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      pills[i],
                    ],
                  ],
                ),
              ),
            if (title != null)
              Row(
                children: [
                  if (icon != null) ...[
                    IconBadge(icon: icon!, color: color),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!.toUpperCase(),
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (subtitle != null) Text(subtitle!, style: text.titleSmall),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            if (children.isNotEmpty) ...[
              if (title != null) const SizedBox(height: 14),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

/// Icono en recuadro del color de la sección.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 30});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(size * 0.4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: size, color: color),
      );
}

/// Dato corto en píldora: racha, semana, días para medir.
class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}

/// Estado vacío que invita a actuar, en vez de un texto suelto.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: muted.withOpacity(0.6)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Fila de lista con icono de tipo, título, detalle y un dato grande a la
/// derecha. Es la fila de sesiones, partidos, pesajes y combos.
class TypedTile extends StatelessWidget {
  const TypedTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.valueLabel,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? value;
  final String? valueLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value!,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
                    if (valueLabel != null) Text(valueLabel!, style: text.labelSmall),
                  ],
                ),
              ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
