import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_routes.dart';
import 'features/auth/presentation/account_page.dart';
import 'features/jobs/data/demo_job_repository.dart';
import 'features/jobs/presentation/jobs_cubit.dart';
import 'features/jobs/presentation/job_discovery_page.dart';

class SmartHireApp extends StatelessWidget {
  const SmartHireApp({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => JobsCubit(DemoJobRepository())..load(),
    child: MaterialApp(
      title: 'SmartHire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.discover,
      routes: {
        AppRoutes.discover: (_) => const JobDiscoveryPage(),
        AppRoutes.signIn: (_) => const AccountPage(mode: AccountMode.signIn),
        AppRoutes.register: (_) =>
            const AccountPage(mode: AccountMode.register),
        AppRoutes.resetPassword: (_) =>
            const AccountPage(mode: AccountMode.resetPassword),
      },
    ),
  );
}
