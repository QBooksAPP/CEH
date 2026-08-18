String normalizeUsername(String value) => value.trim().toLowerCase();

bool isValidUsername(String value) =>
    RegExp(r'^[a-z0-9._-]{3,100}$').hasMatch(normalizeUsername(value));
