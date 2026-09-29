/// Which app a chat was exported from, so it can be drawn in that app's
/// colours.
enum ChatApp {
  whatsapp,
  instagram;

  static ChatApp parse(Object? name) => ChatApp.values.firstWhere(
    (a) => a.name == name,
    orElse: () => ChatApp.whatsapp,
  );
}
