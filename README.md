# LEHU Client MVP

This is the Flutter MVP source package for the LEHU mobile client.

Current scope:

- Fixed top notification entry across all tabs.
- Fixed bottom tabs: Latest, Hot, Messages, Me.
- Native Latest/Hot topic lists based on local Discourse JSON fixtures.
- Native topic detail page with posts, images, reply composer, and like action payload generation.
- Profile summary page based on local fixtures.
- Messages page placeholder.
- Settings and notification entries are reserved for WebView integration.

The first implementation intentionally uses local fixtures under `assets/fixtures/` so the UI and data models can be built before WebView login, Cookie sharing, and CSRF handling are connected.

When the local Flutter toolchain works, generate platform folders inside this directory:

```bash
flutter create .
flutter pub get
flutter test
flutter run
```

If `flutter create .` asks whether to overwrite `lib/`, answer no for existing source files.
