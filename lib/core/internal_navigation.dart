import 'package:flutter/material.dart';

void goToCehHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

List<Widget> cehHomeAction(BuildContext context) => [
      IconButton(
        tooltip: 'Home',
        onPressed: () => goToCehHome(context),
        icon: const Icon(Icons.home_outlined),
      ),
    ];
