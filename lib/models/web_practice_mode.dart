/// Practice entry points supported by the browser experience.
enum WebPracticeMode {
  random,
  chapter,
  mistakes,
}

WebPracticeMode? webPracticeModeFromName(Object? value) {
  final name = value?.toString();
  for (final mode in WebPracticeMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}
