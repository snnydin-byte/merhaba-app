import 'package:flutter/material.dart';

/// Warm Signal v2 is the fixed Merhaba application mark.
/// It stays recognizable even when users switch the app theme.
class WarmSignalMark extends StatelessWidget {
  const WarmSignalMark({
    super.key,
    required this.size,
    this.semanticLabel = 'Merhaba logo',
  });

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2333),
        child: Image.asset(
          'assets/brand/merhaba-warm-signal-v2.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0xFF0E0E1A),
            child: Icon(
              Icons.people_alt_rounded,
              color: Color(0xFF00BFA5),
            ),
          ),
        ),
      ),
    );
  }
}
