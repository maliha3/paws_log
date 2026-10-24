import 'dart:math' as math;

/// Reads the fields of a prescription out of OCR text.
///
/// Pure text in, structured guesses out: no clock, no database, no plugins,
/// which is what lets it be tested against the wording prescriptions are
/// really written in.
///
/// Every field it produces is a guess the owner has to confirm. The parser's
/// job is not to be right — handwriting guarantees it sometimes won't be — it
/// is to be honest about when it might be wrong. So a field it cannot find is
/// left blank rather than filled with a plausible default, and a field the
/// text offers two answers for comes back low-confidence for the review
/// screen to mark. See "Prescriptions are never trusted automatically" in
/// CLAUDE.md.

/// How much to trust one parsed field.
enum Confidence {
  /// Nothing was found. The field is blank, for the owner to fill in.
  none,

  /// Something was found, but the parser would not bet on it. The review
  /// screen marks these.
  low,

  /// Found in wording prescriptions are actually written in.
  high,
}

/// One field read out of a prescription, with how much to trust it.
class ParsedField<T> {
  const ParsedField.read(this.value)
    : confidence = Confidence.high,
      assert(value != null, 'a field that was read has a value');

  const ParsedField.unsure(this.value)
    : confidence = Confidence.low,
      assert(value != null, 'an unsure field still has a value');

  const ParsedField.blank() : value = null, confidence = Confidence.none;

  final T? value;
  final Confidence confidence;

  bool get isBlank => value == null;

  /// Worth marking on the review screen.
  bool get needsCheck => confidence == Confidence.low;

  @override
  bool operator ==(Object other) =>
      other is ParsedField<T> &&
      other.value == value &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(value, confidence);

  @override
  String toString() => switch (confidence) {
    Confidence.none => 'blank',
    Confidence.low => '$value (unsure)',
    Confidence.high => '$value',
  };
}

/// One medicine the parser believes it found on the page.
class ParsedMedicine {
  const ParsedMedicine({
    required this.name,
    required this.dose,
    required this.timesPerDay,
    required this.durationDays,
    required this.sourceText,
    this.isAsNeeded = false,
    this.isOpenEnded = false,
  });

  final ParsedField<String> name;

  /// The amount per dose as written: `50 mg`, `0.1 ml`, `1 tablet`.
  final ParsedField<String> dose;

  /// 1–6. [Medicine] stores real dose times; the review screen converts.
  final ParsedField<int> timesPerDay;

  final ParsedField<int> durationDays;

  /// "prn", "as needed". There is no schedule to generate doses from, so the
  /// review screen offers to save the medicine without reminders.
  final bool isAsNeeded;

  /// "continue", "ongoing", "long term". The course has no end date, which is
  /// different from the parser failing to find one.
  final bool isOpenEnded;

  /// The lines this came from, shown beside the fields on review.
  final String sourceText;

  /// Nothing usable was found.
  bool get isEmpty =>
      name.isBlank && dose.isBlank && timesPerDay.isBlank && durationDays.isBlank;

  @override
  String toString() =>
      'ParsedMedicine(name: $name, dose: $dose, '
      'timesPerDay: $timesPerDay, durationDays: $durationDays)';
}

/// What one prescription's text yielded.
class ParsedPrescription {
  const ParsedPrescription({required this.medicines});

  final List<ParsedMedicine> medicines;

  bool get isEmpty => medicines.isEmpty;
}

/// A medicine line and the sig lines under it.
class _Block {
  _Block({required this.nameLine, required this.nameIsCertain, required this.lines});

  final String? nameLine;
  final bool nameIsCertain;
  final List<String> lines;
}

/// A frequency or duration the text claims, and whether to trust it.
class _Claim {
  const _Claim(this.value, {this.confident = true});

  final int value;
  final bool confident;
}

class PrescriptionParser {
  const PrescriptionParser._();

  static ParsedPrescription parse(String text) {
    final lines = _clean(text);
    if (lines.isEmpty) {
      return const ParsedPrescription(medicines: []);
    }
    final medicines = [for (final block in _blocks(lines)) _medicine(block)]
      ..removeWhere((medicine) => medicine.isEmpty);
    return ParsedPrescription(medicines: medicines);
  }

  // ---------------------------------------------------------------- cleaning

  /// Trimmed, non-empty lines with the characters OCR likes to produce
  /// folded onto the ones the patterns below are written in.
  static List<String> _clean(String text) => text
      .replaceAll('×', 'x') // ×
      .replaceAll(RegExp(r'[‐-―]'), '-') // ‐ – — …
      .replaceAll('½', '1/2') // ½
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();

  // ---------------------------------------------------------------- blocking

  static List<_Block> _blocks(List<String> lines) {
    final strong = <int>[];
    final weak = <int>[];
    for (var index = 0; index < lines.length; index++) {
      if (_isStrongAnchor(lines[index])) {
        strong.add(index);
      } else if (_isWeakAnchor(lines, index)) {
        weak.add(index);
      }
    }

    // A weak anchor inside a strongly-anchored page is almost always a
    // continuation line, so the two kinds are never mixed.
    final anchors = strong.isNotEmpty ? strong : weak;
    if (anchors.isEmpty) {
      // No line looks like a medicine name. Read the page as one unnamed
      // course rather than giving up: "q8h x 5 days" still says something.
      return [
        _Block(
          nameLine: null,
          nameIsCertain: false,
          lines: lines.where((line) => !_notMedicine.hasMatch(line)).toList(),
        ),
      ];
    }

    final blocks = <_Block>[];
    for (var at = 0; at < anchors.length; at++) {
      final start = anchors[at];
      final limit = at + 1 < anchors.length ? anchors[at + 1] : lines.length;
      final body = <String>[lines[start]];
      for (var index = start + 1; index < limit; index++) {
        // "Recheck in 2 weeks" under the last medicine is not its duration.
        if (_notMedicine.hasMatch(lines[index])) {
          break;
        }
        body.add(lines[index]);
      }
      blocks.add(
        _Block(
          nameLine: lines[start],
          nameIsCertain: strong.isNotEmpty,
          lines: body,
        ),
      );
    }
    return blocks;
  }

  /// A numbered line, or a line that names a drug and its strength.
  static bool _isStrongAnchor(String line) {
    if (_notMedicine.hasMatch(line)) {
      return false;
    }
    final body = line.replaceFirst(_enumeration, '');
    if (!_startsWithWord.hasMatch(body)) {
      return false;
    }
    if (_enumeration.hasMatch(line)) {
      return true;
    }
    // "Give one tablet twice daily" mentions a tablet but is an instruction,
    // not a heading.
    if (_sigStart.hasMatch(body)) {
      return false;
    }
    return _strength.hasMatch(body) || _formWord.hasMatch(body);
  }

  /// A bare drug name with its instructions on the next line.
  static bool _isWeakAnchor(List<String> lines, int index) {
    final line = lines[index];
    if (_notMedicine.hasMatch(line) || _sigStart.hasMatch(line)) {
      return false;
    }
    if (!_bareName.hasMatch(line)) {
      return false;
    }
    final next = index + 1 < lines.length ? lines[index + 1] : null;
    return next != null && _isSigLine(next);
  }

  static bool _isSigLine(String line) {
    final lowered = line.toLowerCase();
    return _frequency(lowered).isNotEmpty || _duration(lowered).isNotEmpty;
  }

  // ----------------------------------------------------------------- fields

  static ParsedMedicine _medicine(_Block block) {
    final source = block.lines.join('\n');
    final lowered = source.toLowerCase();
    return ParsedMedicine(
      name: _name(block),
      dose: _dose(lowered),
      timesPerDay: _field(_frequency(lowered), 1, 6),
      durationDays: _field(_duration(lowered), 1, 365),
      isAsNeeded: _asNeeded.hasMatch(lowered),
      isOpenEnded: _openEnded.hasMatch(lowered),
      sourceText: source,
    );
  }

  static ParsedField<String> _name(_Block block) {
    final line = block.nameLine;
    if (line == null) {
      return const ParsedField.blank();
    }

    var head = line.replaceFirst(_enumeration, '');
    final cut = [_strength, _countDose, _sigToken]
        .map((pattern) => pattern.firstMatch(head)?.start)
        .whereType<int>();
    if (cut.isNotEmpty) {
      head = head.substring(0, cut.reduce(math.min));
    }

    final words = head
        .replaceAll(_formWord, ' ')
        .replaceAll(RegExp(r"[^A-Za-z0-9 \-'./]"), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .takeWhile((word) => _wordLike.hasMatch(word))
        .take(4)
        .toList();
    final name = words.join(' ').replaceAll(RegExp(r"[\-'./]+$"), '').trim();
    if (name.length < 3) {
      return const ParsedField.blank();
    }
    // A digit in the name usually means the strength bled into it, or OCR
    // turned a letter into a number. Either way the owner should look.
    return block.nameIsCertain && _cleanName.hasMatch(name)
        ? ParsedField.read(name)
        : ParsedField.unsure(name);
  }

  /// The amount per dose.
  ///
  /// A real strength (`50 mg`, `0.1 ml`) beats a count (`1 tablet`), because
  /// the count is usually a restatement of it. Two different strengths in one
  /// block is the concentration-versus-dose trap — "0.5 mg/ml suspension,
  /// give 0.1 ml" — so the parser takes the first and flags it.
  static ParsedField<String> _dose(String lowered) {
    final strengths = _strength
        .allMatches(lowered)
        .map((match) => _amount(match.group(1)!, match.group(2)!))
        .toSet()
        .toList();
    if (strengths.isNotEmpty) {
      return strengths.length == 1
          ? ParsedField.read(strengths.single)
          : ParsedField.unsure(strengths.first);
    }

    final counts = _countDose
        .allMatches(lowered)
        .map((match) => _count(match.group(1)!, match.group(2)!))
        .toSet()
        .toList();
    if (counts.isEmpty) {
      return const ParsedField.blank();
    }
    return counts.length == 1
        ? ParsedField.read(counts.single)
        : ParsedField.unsure(counts.first);
  }

  /// Picks one number out of what the text claimed.
  ///
  /// Claims that agree collapse; claims that disagree leave the first one
  /// marked, because the parser has no way to know which line the vet meant.
  static ParsedField<int> _field(List<_Claim> claims, int low, int high) {
    final sane = claims
        .where((claim) => claim.value >= low && claim.value <= high)
        .toList();
    if (sane.isEmpty) {
      return const ParsedField.blank();
    }
    final values = sane.map((claim) => claim.value).toSet();
    final confident = values.length == 1 && sane.every((claim) => claim.confident);
    return confident
        ? ParsedField.read(sane.first.value)
        : ParsedField.unsure(sane.first.value);
  }

  // --------------------------------------------------------------- frequency

  static List<_Claim> _frequency(String lowered) {
    final claims = <_Claim>[];

    // "q8h", "every 8 hours". Only the intervals that divide a day can be
    // said in times-per-day at all; q36h cannot, so it is dropped rather
    // than rounded into a wrong schedule.
    for (final match in _everyHours.allMatches(lowered)) {
      final hours = int.parse(match.group(1) ?? match.group(2)!);
      if (hours > 0 && 24 % hours == 0) {
        claims.add(_Claim(24 ~/ hours));
      }
    }

    // "1-0-1", "1+1+1": morning-noon-night, written this way across South
    // Asia. Each non-zero slot is a dose.
    for (final match in _slots.allMatches(lowered)) {
      final slots = match
          .group(0)!
          .split(RegExp(r'[-+]'))
          .map((slot) => slot.trim())
          .where((slot) => slot.isNotEmpty);
      final doses = slots.where((slot) => slot != '0').length;
      if (doses > 0) {
        claims.add(_Claim(doses));
      }
    }

    for (final match in _timesADay.allMatches(lowered)) {
      claims.add(_Claim(_number(match.group(1)!).round()));
    }

    for (final entry in _namedFrequencies.entries) {
      if (entry.key.hasMatch(lowered)) {
        claims.add(entry.value);
      }
    }

    return claims;
  }

  // ---------------------------------------------------------------- duration

  static List<_Claim> _duration(String lowered) {
    final claims = <_Claim>[];
    for (final match in _days.allMatches(lowered)) {
      // Either "for 7 days" or a bare "7 days" matched; only one group fills.
      claims.add(_Claim(_number(match.group(1) ?? match.group(2)!).round()));
    }
    for (final match in _weeks.allMatches(lowered)) {
      claims.add(_Claim(_number(match.group(1)!).round() * 7));
    }
    for (final match in _months.allMatches(lowered)) {
      claims.add(_Claim(_number(match.group(1)!).round() * 30));
    }
    return claims;
  }

  // --------------------------------------------------------------- numbers

  static double _number(String written) {
    final word = _numberWords[written.trim()];
    if (word != null) {
      return word;
    }
    if (written.contains('/')) {
      final parts = written.split('/');
      return double.parse(parts[0]) / double.parse(parts[1]);
    }
    return double.parse(written.replaceAll(',', '.'));
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  static String _amount(String written, String unit) =>
      '${_plain(_number(written))} ${unit.toLowerCase()}';

  static String _count(String written, String unit) {
    final value = _number(written);
    final noun = _countNouns[unit.toLowerCase()] ?? unit.toLowerCase();
    return value == 1
        ? '${_plain(value)} $noun'
        : '${_plain(value)} ${noun}s';
  }

  // --------------------------------------------------------------- patterns

  static const String _units =
      r'mg/ml|mcg/ml|mg/kg|mcg|mg|iu|units?|unit|ml|g';

  static final RegExp _strength = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(' + _units + r')\b',
    caseSensitive: false,
  );

  static final RegExp _countDose = RegExp(
    r"(\d+(?:[.,]\d+)?|\d/\d|half|one|two|three|four)\s*"
    r'(tabs?|tablets?|caps?|capsules?|drops?|sachets?|puffs?|scoops?|'
    r'tsp|teaspoons?|sprays?)\b',
    caseSensitive: false,
  );

  static final RegExp _formWord = RegExp(
    r'\b(?:tabs?|tablets?|caps?|capsules?|syrups?|susp(?:ension)?|soln?|'
    r'solutions?|inj(?:ection)?|drops?|oint(?:ment)?|creams?|gels?|'
    r'sachets?|powder|paste|spot-?on|chewables?)\b',
    caseSensitive: false,
  );

  static final RegExp _enumeration = RegExp(r'^(?:\d{1,2}\s*[.)\-]|[-*])\s+');

  static final RegExp _startsWithWord = RegExp(r'^[A-Za-z]');

  /// Lines that give instructions rather than name a medicine.
  static final RegExp _sigStart = RegExp(
    r'^(?:give|gives|giving|take|takes|apply|administer|instil|instill|use|'
    r'inject|dose|dosage|sig|feed|mix|one|two|three|half|\d)\b',
    caseSensitive: false,
  );

  /// Letterhead, patient details and footers. None of these start a medicine,
  /// and a footer ends the block above it.
  static final RegExp _notMedicine = RegExp(
    r'^(?:rx\b|prescription|patient|owner|pet\b|species|breed|age\b|sex\b|'
    r'weight|date\b|dob\b|diagnosis|dx\b|signature|signed|clinic|hospital|'
    r'veterinar|dr\.?\s|doctor|recheck|re-check|review|follow.?up|'
    r'next\s+(?:visit|appointment)|refill|advice|note\b|notes\b|address|'
    r'phone|tel\b|email|reg(?:istration)?\s*no)',
    caseSensitive: false,
  );

  /// One to four words that could be a drug name on a line of their own.
  static final RegExp _bareName = RegExp(
    r"^[A-Za-z][A-Za-z\-'.]*(?: [A-Za-z][A-Za-z0-9\-'.]*){0,3}$",
  );

  static final RegExp _wordLike = RegExp(r"^[A-Za-z][A-Za-z0-9\-'./]*$");

  static final RegExp _cleanName = RegExp(r"^[A-Za-z][A-Za-z \-'.]*$");

  /// Where a drug name stops and its instructions start.
  static final RegExp _sigToken = RegExp(
    r'\b(?:once|twice|thrice|bid|b\.i\.d|tid|t\.i\.d|qid|q\.i\.d|sid|od|qd|'
    r'q\d+\s*h|prn|s\.?o\.?s|every|daily|times|for\s+\d|x\s*\d|give|take|'
    r'apply|\d+\s*(?:days?|weeks?|months?))\b',
    caseSensitive: false,
  );

  static final RegExp _everyHours = RegExp(
    r'\bq\s*(\d{1,2})\s*h(?:rs?|ours?)?\b|\bevery\s+(\d{1,2})\s*h(?:rs?|ours?)?\b',
    caseSensitive: false,
  );

  static final RegExp _slots = RegExp(r'\b[0-2](?:\s*[-+]\s*[0-2]){2,3}\b');

  static final RegExp _timesADay = RegExp(
    r'\b(\d+|one|two|three|four)\s*(?:times?|x)\s*'
    r'(?:a\s*day|daily|per\s*day|/\s*day|/d)\b',
    caseSensitive: false,
  );

  static final Map<RegExp, _Claim> _namedFrequencies = {
    RegExp(r'\b(?:once\s*(?:a\s*day|daily)|sid|q24h)\b', caseSensitive: false):
        const _Claim(1),
    // "OD" is once daily on most prescriptions and the right eye on eye
    // drops, so it is never trusted on its own.
    RegExp(r'\b(?:od|qd)\b', caseSensitive: false): const _Claim(1, confident: false),
    RegExp(r'\b(?:twice\s*(?:a\s*day|daily)|bd|bid|b\.i\.d\.?)\b', caseSensitive: false):
        const _Claim(2),
    RegExp(
      r'\b(?:three\s*times\s*(?:a\s*day|daily)|thrice|tds|tid|t\.i\.d\.?)\b',
      caseSensitive: false,
    ): const _Claim(3),
    RegExp(r'\b(?:four\s*times\s*(?:a\s*day|daily)|qds|qid|q\.i\.d\.?)\b', caseSensitive: false):
        const _Claim(4),
  };

  static final RegExp _days = RegExp(
    r'(?:for|x)\s*(\d+|one|two|three|four|five|six|seven|eight|nine|ten|'
    r'eleven|twelve|fourteen)\s*(?:d\b|days?\b)|'
    r'\b(\d+|seven|ten|fourteen)\s*(?:days?)\b',
    caseSensitive: false,
  );

  static final RegExp _weeks = RegExp(
    r'(?:for|x)?\s*(\d+|one|two|three|four|six)\s*(?:wks?\b|weeks?\b)',
    caseSensitive: false,
  );

  static final RegExp _months = RegExp(
    r'(?:for|x)?\s*(\d+|one|two|three|six)\s*(?:months?\b|mos?\b)',
    caseSensitive: false,
  );

  static final RegExp _asNeeded = RegExp(
    r'\b(?:prn|p\.r\.n\.?|as\s+(?:needed|required)|when\s+(?:needed|required)|s\.?o\.?s)\b',
    caseSensitive: false,
  );

  static final RegExp _openEnded = RegExp(
    r'\b(?:continue|continuous|ongoing|long\s*-?\s*term|life\s*-?\s*long|'
    r'lifelong|indefinite(?:ly)?|until\s+(?:further|told|advised|reviewed))\b',
    caseSensitive: false,
  );

  static const Map<String, double> _numberWords = {
    'half': 0.5,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'fourteen': 14,
  };

  static const Map<String, String> _countNouns = {
    'tab': 'tablet',
    'tabs': 'tablet',
    'tablet': 'tablet',
    'tablets': 'tablet',
    'cap': 'capsule',
    'caps': 'capsule',
    'capsule': 'capsule',
    'capsules': 'capsule',
    'drop': 'drop',
    'drops': 'drop',
    'sachet': 'sachet',
    'sachets': 'sachet',
    'puff': 'puff',
    'puffs': 'puff',
    'scoop': 'scoop',
    'scoops': 'scoop',
    'tsp': 'teaspoon',
    'teaspoon': 'teaspoon',
    'teaspoons': 'teaspoon',
    'spray': 'spray',
    'sprays': 'spray',
  };
}
