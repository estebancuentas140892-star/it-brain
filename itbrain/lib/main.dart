import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase and other services here
  // await Supabase.initialize(
  //   url: 'your-supabase-url',
  //   anonKey: 'your-anon-key',
  // );

  runApp(
    const ProviderScope(
      child: ITBrainApp(),
    ),
  );
}
