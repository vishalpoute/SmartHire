import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_routes.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'features/auth/presentation/account_page.dart';
import 'features/jobs/data/demo_job_repository.dart';
import 'features/jobs/presentation/jobs_cubit.dart';
import 'features/jobs/presentation/job_discovery_page.dart';

class SmartHireApp extends StatelessWidget {
  const SmartHireApp({
    super.key,
    this.firebaseAvailability = FirebaseAvailability.preview,
  });
  final FirebaseAvailability firebaseAvailability;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => JobsCubit(DemoJobRepository())..load(),
    child: MaterialApp(
      title: 'SmartHire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) =>
          firebaseAvailability == FirebaseAvailability.unavailable
          ? Column(
              children: [
                const Material(
                  color: Color(0xFFF0EBD9),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Account service setup is unavailable. You can still explore sample jobs.',
                      ),
                    ),
                  ),
                ),
                Expanded(child: child!),
              ],
            )
          : child!,
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
