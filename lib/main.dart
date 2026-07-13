import 'dart:io';

import 'package:flutter/material.dart';

import 'app/lehu_app.dart';
import 'core/lehu_http_overrides.dart';

void main() {
  HttpOverrides.global = LehuHttpOverrides();
  runApp(const LehuApp());
}
