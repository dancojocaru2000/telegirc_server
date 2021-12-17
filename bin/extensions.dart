extension StringSplitLimit on String {
  List<String> splitLimit(String pattern, int limit) {
    final tokens = split(pattern);
    if (tokens.length <= limit) {
      return tokens;
    }
    final result = tokens.take(limit - 1).toList();
    result.add(tokens.skip(limit - 1).join(pattern));
    return result;
  }
}