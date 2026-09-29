import 'dart:math' as math;
import 'dart:typed_data';

import 'chat_groupings.dart';

/// Every grouped reply placed on a flat map, for drawing.
///
/// The fingerprints have hundreds of dimensions; the map keeps two. They are
/// the two directions along which the groups' centres differ most (principal
/// components of the centres, weighted by group size), so the groups sit as
/// far apart on the page as the data allows, and each reply lands where it
/// falls along those same two directions. With fewer than three groups there
/// is no second direction between centres, so the second axis is the one
/// along which replies vary most within their groups.
///
/// Pure Dart and deterministic, so it is unit-testable.
class GroupMap {
  const GroupMap._(this.points, this.centres);

  /// For each group, the position of each member, in the same order as
  /// [ChatGroup.members]. Both coordinates are within -1 to 1, each axis
  /// stretched so the furthest reply reaches its edge.
  final List<List<(double, double)>> points;

  /// Where each group's centre falls, in the same scale.
  final List<(double, double)> centres;

  static const GroupMap empty = GroupMap._([], []);

  static GroupMap of(List<ChatGroup> groups) {
    final sized = [
      for (final g in groups)
        if (g.members.isNotEmpty) g,
    ];
    if (sized.isEmpty || sized.length != groups.length) {
      return sized.isEmpty ? empty : of(sized);
    }
    final dims = groups.first.members.first.vector.length;
    final total = groups.fold(0, (sum, g) => sum + g.size);

    // Group centres (plain means) and the overall mean.
    final centres = <Float64List>[];
    final mean = Float64List(dims);
    for (final g in groups) {
      final c = Float64List(dims);
      for (final m in g.members) {
        for (var d = 0; d < dims; d++) {
          c[d] += m.vector[d];
        }
      }
      for (var d = 0; d < dims; d++) {
        c[d] /= g.size;
        mean[d] += c[d] * g.size / total;
      }
      centres.add(c);
    }

    // Rows whose covariance is the size-weighted spread of the centres.
    final between = [
      for (var i = 0; i < groups.length; i++)
        _scaled(_minus(centres[i], mean), math.sqrt(groups[i].size.toDouble())),
    ];
    // Rows for the spread of replies around their own group's centre.
    List<Float64List> within() => [
      for (var i = 0; i < groups.length; i++)
        for (final m in groups[i].members)
          _minus(Float64List.fromList(m.vector), centres[i]),
    ];

    final (first, firstStrength) = _component(
      groups.length > 1 ? between : within(),
      dims,
      const [],
    );
    var (second, secondStrength) = groups.length > 2
        ? _component(between, dims, [first])
        : (Float64List(dims), 0.0);
    if (secondStrength <= firstStrength * 1e-6) {
      (second, secondStrength) = _component(within(), dims, [first]);
    }

    (double, double) place(List<double> v) {
      var x = 0.0;
      var y = 0.0;
      for (var d = 0; d < dims; d++) {
        final centred = v[d] - mean[d];
        x += centred * first[d];
        y += centred * second[d];
      }
      return (x, y);
    }

    final raw = [
      for (final g in groups) [for (final m in g.members) place(m.vector)],
    ];
    final rawCentres = [for (final c in centres) place(c)];

    // Each axis stretched to fill the square, so the map uses all its room
    // whichever direction the groups happen to spread in.
    var reachX = 0.0;
    var reachY = 0.0;
    for (final group in raw) {
      for (final (x, y) in group) {
        reachX = math.max(reachX, x.abs());
        reachY = math.max(reachY, y.abs());
      }
    }
    final sx = reachX <= 0 ? 1.0 : 1 / reachX;
    final sy = reachY <= 0 ? 1.0 : 1 / reachY;
    (double, double) fit((double, double) p) =>
        (_clamp(p.$1 * sx), _clamp(p.$2 * sy));

    return GroupMap._(
      [
        for (final group in raw) [for (final p in group) fit(p)],
      ],
      [for (final c in rawCentres) fit(c)],
    );
  }

  /// The strongest direction of spread among [rows], at right angles to
  /// every one of [avoid], with its strength. Power iteration: repeatedly
  /// multiply by the rows' covariance without ever forming it.
  static (Float64List, double) _component(
    List<Float64List> rows,
    int dims,
    List<Float64List> avoid,
  ) {
    final random = math.Random(1);
    var v = Float64List.fromList([
      for (var d = 0; d < dims; d++) random.nextDouble() - 0.5,
    ]);
    _orthogonalise(v, avoid);
    _normalise(v);
    var strength = 0.0;
    for (var iteration = 0; iteration < 60; iteration++) {
      final next = Float64List(dims);
      for (final row in rows) {
        var along = 0.0;
        for (var d = 0; d < dims; d++) {
          along += row[d] * v[d];
        }
        for (var d = 0; d < dims; d++) {
          next[d] += row[d] * along;
        }
      }
      _orthogonalise(next, avoid);
      strength = _normalise(next);
      if (strength == 0) return (v, 0);
      var change = 0.0;
      for (var d = 0; d < dims; d++) {
        change += (next[d] - v[d]).abs();
      }
      v = next;
      if (change < 1e-9) break;
    }
    return (v, strength);
  }

  static void _orthogonalise(Float64List v, List<Float64List> avoid) {
    for (final a in avoid) {
      var along = 0.0;
      for (var d = 0; d < v.length; d++) {
        along += v[d] * a[d];
      }
      for (var d = 0; d < v.length; d++) {
        v[d] -= along * a[d];
      }
    }
  }

  /// Scales [v] to unit length in place, returning its length before.
  static double _normalise(Float64List v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final length = math.sqrt(sum);
    if (length == 0) return 0;
    for (var d = 0; d < v.length; d++) {
      v[d] /= length;
    }
    return length;
  }

  static Float64List _minus(List<double> a, List<double> b) =>
      Float64List.fromList([for (var d = 0; d < a.length; d++) a[d] - b[d]]);

  static Float64List _scaled(Float64List v, double by) {
    for (var d = 0; d < v.length; d++) {
      v[d] *= by;
    }
    return v;
  }

  static double _clamp(double v) => v.clamp(-1.0, 1.0);
}
