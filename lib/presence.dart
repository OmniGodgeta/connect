/// Decides when a join or leave sound should play.
///
/// The first roster after [reset] is the people already in the room, and it
/// stays quiet. Later arrivals and departures count. [selfId] never counts.
class Presence {
  final Set<String> _ids = <String>{};
  bool _primed = false;

  void reset() {
    _ids.clear();
    _primed = false;
  }

  (int joins, int leaves) take(Iterable<String> ids, String? selfId) {
    final next = <String>{
      for (final id in ids)
        if (id != selfId) id,
    };
    if (!_primed) {
      _primed = true;
      _ids
        ..clear()
        ..addAll(next);
      return (0, 0);
    }
    final joins = next.difference(_ids).length;
    final leaves = _ids.difference(next).length;
    _ids
      ..clear()
      ..addAll(next);
    return (joins, leaves);
  }
}
