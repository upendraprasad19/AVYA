/// Result of analyzing a single user message for identity signals.
class IdentitySignals {
  const IdentitySignals({this.communicationStyle, this.preferredName});
  final String? communicationStyle; // 'hinglish' if flipped this turn
  final String? preferredName;
}

/// Cheap, on-device identity heuristics. Stateful — sticky communication
/// style avoids flipping on a single Romanized English word.
class IdentitySignalDetector {
  // Common Hindi-stem words used in casual Indian English (Hinglish).
  // Detection requires >= 2 of these for one message to count toward
  // the streak. Devanagari script alone always counts.
  static const _hinglishStems = {
    'yaar', 'bhai', 'bro', 'haan', 'nahi', 'kya', 'kaise', 'kaisa',
    'kar', 'karo', 'karna', 'mera', 'tera', 'aaj', 'kal', 'abhi',
    'main', 'mere', 'tum', 'aap', 'bata', 'batao', 'dekh', 'dekho',
    'chal', 'chalo', 'thoda', 'bahut', 'matlab', 'samajh', 'theek',
    'sahi', 'galat', 'achha', 'bura', 'dabaya', 'lagta', 'lagti',
    'khaaun', 'khana', 'pina', 'hua', 'hui', 'tha', 'thi',
  };

  static final _devanagari = RegExp(r'[\u0900-\u097F]');
  static final _wordBoundary = RegExp(r"[a-zA-Z\u0900-\u097F']+");

  static final _namePatterns = <RegExp>[
    RegExp(r"\bcall me ([A-Z][a-zA-Z]{1,19})\b"),
    RegExp(r"\bmy name is ([A-Z][a-zA-Z]{1,19})\b"),
    RegExp(r"\bi['']m ([A-Z][a-zA-Z]{1,19})\b", caseSensitive: false),
    RegExp(r"\bi am ([A-Z][a-zA-Z]{1,19})\b", caseSensitive: false),
  ];

  static const _stickyThreshold = 3;
  int _hinglishStreak = 0;

  IdentitySignals detect(String message) {
    return IdentitySignals(
      communicationStyle: _detectCommunicationStyle(message),
      preferredName: _detectPreferredName(message),
    );
  }

  String? _detectCommunicationStyle(String message) {
    final hasDevanagari = _devanagari.hasMatch(message);
    if (hasDevanagari) {
      _hinglishStreak = _stickyThreshold; // immediate flip
      return 'hinglish';
    }

    final words = _wordBoundary
        .allMatches(message.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final hits = words.where(_hinglishStems.contains).length;

    if (hits >= 2) {
      _hinglishStreak++;
      if (_hinglishStreak >= _stickyThreshold) return 'hinglish';
    } else {
      _hinglishStreak = 0;
    }
    return null;
  }

  String? _detectPreferredName(String message) {
    for (final pattern in _namePatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final name = match.group(1);
        if (name != null && name.length >= 2 && name.length <= 20) {
          return name;
        }
      }
    }
    return null;
  }

  /// For test reset only.
  void resetStreak() => _hinglishStreak = 0;
}
