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
