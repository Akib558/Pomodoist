/// Exact on all supported targets, including JavaScript.
const maximumTaskOrderValue = 4503599627370496;
String formatTaskOrder(int value) => value.toString().padLeft(20, '0');

String? taskOrderBetween(String? left, String? right) {
  int? parse(String key) => key.length == 20 ? int.tryParse(key) : null;
  final a = left == null ? 0 : parse(left);
  final b = right == null ? maximumTaskOrderValue : parse(right);
  if (a == null || b == null || b - a <= 1) return null;
  return formatTaskOrder(a + ((b - a) ~/ 2));
}
