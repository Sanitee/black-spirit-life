import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/persistence/shared_profile_guard.dart';

Future<void> main(List<String> args) async {
  final guard = SharedProfileGuard(Directory(args[0]));
  try {
    await guard.acquire();
    stdout.writeln('held');
    if (args.length > 1 && args[1] == 'hold') await stdin.first;
    await guard.release();
  } on FileSystemException {
    stdout.writeln('locked');
    exitCode = 42;
  }
}
