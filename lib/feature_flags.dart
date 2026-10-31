// lib/feature_flags.dart
//
// Switches for features that are held back from the Play Store build.
//
// SMS expense tracking reads the inbox (READ_SMS / RECEIVE_SMS), which Google
// Play only allows for default SMS apps and a few narrow exceptions. It is
// off for the Play release. To bring it back for a private build: set this to
// true AND delete the <uses-permission ... tools:node="remove"/> SMS lines in
// android/app/src/main/AndroidManifest.xml (replace with plain permissions).
const bool kEnableSmsTracking = false;
