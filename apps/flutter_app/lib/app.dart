import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'features/jobs/data/demo_job_repository.dart';
import 'features/jobs/presentation/jobs_cubit.dart';
import 'features/jobs/presentation/job_discovery_page.dart';

class SmartHireApp extends StatelessWidget {
  const SmartHireApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SmartHire',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: BlocProvider(
      create: (_) => JobsCubit(DemoJobRepository())..load(),
      child: const JobDiscoveryPage(),
    ),
  );
}
