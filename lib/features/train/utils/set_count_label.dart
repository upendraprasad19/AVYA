/// Count labels for logged-exercise rows (OI-371). The number and its unit
/// are joined by a non-breaking space so a wrapped row never splits them.
const String kNbsp = ' ';

/// The separator between detail parts: the dot stays on the line it ends.
const String kDetailSeparator = '$kNbsp· ';

/// `1 set` / `N sets`.
String setCountLabel(int n) => '$n$kNbsp${n == 1 ? 'set' : 'sets'}';

/// `1 rep` / `N reps`.
String repCountLabel(int n) => '$n$kNbsp${n == 1 ? 'rep' : 'reps'}';
