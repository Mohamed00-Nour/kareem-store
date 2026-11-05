/// Returns the display form used when saving a locally-created entity.
///
/// Leading/trailing whitespace is removed and internal whitespace is collapsed,
/// while the user's letter casing is preserved.
String cleanEntityName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Returns the canonical form used for local duplicate checks.
String normalizeEntityName(String value) {
  return cleanEntityName(value).toLowerCase();
}

/// Stricter key for detecting customer/supplier names that only differ by
/// common Arabic spelling variants (أ/إ/آ/ا, ة/ه, ى/ي), diacritics or tatweel.
/// Used only to warn about duplicates; lookups keep [normalizeEntityName].
String partyNameKey(String value) {
  return normalizeEntityName(value)
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[آأإٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');
}

/// Keys from [partyNameKey] that appear on more than one name.
Set<String> duplicatePartyNameKeys(Iterable<String> names) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final name in names) {
    final key = partyNameKey(name);
    if (key.isEmpty) continue;
    if (!seen.add(key)) duplicates.add(key);
  }
  return duplicates;
}
