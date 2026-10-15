/// Graphic Equalizer Channel Routing Mode.
enum EqChannelMode {
  whole(
    0,
    'Stereo (Whole)',
    'Left and Right channels share identical equalization curves.',
  ),
  dual(
    1,
    '2-Way Dual Channel',
    'Independent equalization curves for Left and Right channels.',
  );

  final int id;
  final String label;
  final String description;
  const EqChannelMode(this.id, this.label, this.description);

  static EqChannelMode fromId(int id) {
    return EqChannelMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => EqChannelMode.whole,
    );
  }
}

/// Slider movement coupling behavior (modeled after classic Windows Media Player GEQ).
enum EqSliderLinkMode {
  single(
    0,
    'Single',
    'Sliders move independently',
    'Adjusting one slider affects only that specific frequency band.',
  ),
  loose(
    1,
    'Loose Group',
    'Sliders move in a smooth bell curve',
    'Adjusting one slider smoothly moves neighboring sliders in a gentle bell curve.',
  ),
  tight(
    2,
    'Tight Group',
    'Sliders move in a wide proportional curve',
    'Adjusting one slider moves a wider group of sliders together proportionally.',
  );

  final int id;
  final String label;
  final String subtitle;
  final String description;
  const EqSliderLinkMode(this.id, this.label, this.subtitle, this.description);

  static EqSliderLinkMode fromId(int id) {
    return EqSliderLinkMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => EqSliderLinkMode.single,
    );
  }
}

/// Audiophile Graphic Equalizer DSP filter topology.
enum EqTopologyMode {
  matrixCascade(
    0,
    'Matrix Compensated',
    'Decoupled Rämö-Välimäki interaction matrix with Cytomic SVF filters and Orfanidis de-cramping (Zero inter-band ripple).',
  ),
  parallel(
    1,
    'Symmetric Parallel',
    'Constant-Q parallel filter bank eliminating cumulative phase delay for transparent transients.',
  ),
  legacy(
    2,
    'Legacy Cascade',
    'Direct uncompensated series biquads (useful for A/B testing and classic audio character).',
  );

  final int id;
  final String label;
  final String description;
  const EqTopologyMode(this.id, this.label, this.description);

  static EqTopologyMode fromId(int id) {
    return EqTopologyMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => EqTopologyMode.matrixCascade,
    );
  }
}

/// Computes updated gain values when a slider at [targetIndex] moves from its
/// old value to [newTargetDb].
///
/// Under [EqSliderLinkMode.loose] and [EqSliderLinkMode.tight], neighboring bands
/// receive proportional adjustments according to a smooth Gaussian bell curve
/// around [targetIndex], exactly like Windows Media Player's legacy Graphic Equalizer.
List<double> calculateCoupledGains({
  required List<double> currentGains,
  required int targetIndex,
  required double newTargetDb,
  required EqSliderLinkMode linkMode,
  double minDb = -12.0,
  double maxDb = 12.0,
}) {
  if (targetIndex < 0 || targetIndex >= currentGains.length) {
    return List<double>.from(currentGains);
  }

  final updated = List<double>.from(currentGains);
  final deltaDb = newTargetDb - currentGains[targetIndex];
  if (deltaDb.abs() < 1e-6) {
    return updated;
  }

  switch (linkMode) {
    case EqSliderLinkMode.single:
      updated[targetIndex] = newTargetDb.clamp(minDb, maxDb);
      break;

    case EqSliderLinkMode.loose:
      // Smooth bell curve weights: d=0: 1.0, d=1: 0.55, d=2: 0.18
      const weights = [1.0, 0.55, 0.18];
      for (int d = 0; d < weights.length; d++) {
        final w = weights[d];
        final left = targetIndex - d;
        final right = targetIndex + d;
        if (d == 0) {
          updated[targetIndex] = (currentGains[targetIndex] + deltaDb * w).clamp(minDb, maxDb);
        } else {
          if (left >= 0) {
            updated[left] = (currentGains[left] + deltaDb * w).clamp(minDb, maxDb);
          }
          if (right < currentGains.length) {
            updated[right] = (currentGains[right] + deltaDb * w).clamp(minDb, maxDb);
          }
        }
      }
      break;

    case EqSliderLinkMode.tight:
      // Broad proportional bell curve weights: d=0: 1.0, d=1: 0.78, d=2: 0.50, d=3: 0.25, d=4: 0.08
      const weights = [1.0, 0.78, 0.50, 0.25, 0.08];
      for (int d = 0; d < weights.length; d++) {
        final w = weights[d];
        final left = targetIndex - d;
        final right = targetIndex + d;
        if (d == 0) {
          updated[targetIndex] = (currentGains[targetIndex] + deltaDb * w).clamp(minDb, maxDb);
        } else {
          if (left >= 0) {
            updated[left] = (currentGains[left] + deltaDb * w).clamp(minDb, maxDb);
          }
          if (right < currentGains.length) {
            updated[right] = (currentGains[right] + deltaDb * w).clamp(minDb, maxDb);
          }
        }
      }
      break;
  }

  return updated;
}
