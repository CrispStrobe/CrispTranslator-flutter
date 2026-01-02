// lib/models/app_settings.dart
class AppSettings {
  // Performance settings
  int beamSize;
  bool useBeamSearch;
  double repetitionPenalty;
  int noRepeatNgramSize;
  int maxLength;
  
  // UI settings
  bool showAlignments;
  bool verboseLogging;
  
  // Processing settings
  bool preserveFormatting;
  
  AppSettings({
    this.beamSize = 4,
    this.useBeamSearch = true,
    this.repetitionPenalty = 1.2,
    this.noRepeatNgramSize = 3,
    this.maxLength = 256,
    this.showAlignments = true,
    this.verboseLogging = false,
    this.preserveFormatting = true,
  });
  
  factory AppSettings.speed() => AppSettings(
    beamSize: 1,
    repetitionPenalty: 1.0,
    useBeamSearch: false,
    maxLength: 128,
  );
  
  factory AppSettings.quality() => AppSettings(
    beamSize: 4,
    useBeamSearch: true,
    repetitionPenalty: 1.2,
    maxLength: 256,
  );
  
  factory AppSettings.balanced() => AppSettings(
    beamSize: 2,
    useBeamSearch: true,
    repetitionPenalty: 1.1,
    maxLength: 200,
  );
}