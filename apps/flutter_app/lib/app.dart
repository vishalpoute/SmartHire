import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'core/theme/app_theme.dart';
import 'core/routing/app_routes.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'features/auth/presentation/account_page.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/auth/presentation/session_cubit.dart';
import 'features/profile/presentation/profile_page.dart';
import 'features/profile/presentation/profile_edit_page.dart';
import 'features/profile/domain/profile_repository.dart';
import 'features/profile/data/firebase_profile_session.dart';
import 'features/jobs/data/demo_job_repository.dart';
import 'features/jobs/data/api_public_jobs_repository.dart';
import 'features/jobs/domain/public_jobs_repository.dart';
import 'features/jobs/presentation/public_job_pages.dart';
import 'features/jobs/presentation/jobs_cubit.dart';
import 'features/jobs/presentation/job_discovery_page.dart';
import 'features/jobs/presentation/job_details_page.dart';

class SmartHireApp extends StatelessWidget {
  const SmartHireApp({
    super.key,
    this.firebaseAvailability = FirebaseAvailability.preview,
    this.authRepository,
    this.initialRoute,
    this.profileRepositoryFactory,
    this.publicJobsRepository,
  });
  final PublicJobsRepository? publicJobsRepository;
  final FirebaseAvailability firebaseAvailability;
  final AuthRepository? authRepository;
  final String? initialRoute;
  final ProfileRepository Function(String uid)? profileRepositoryFactory;

  ProfileRepository Function(String)? get _profiles {
    if (profileRepositoryFactory != null) return profileRepositoryFactory;
    const origin = String.fromEnvironment('PROFILE_API_ORIGIN');
    final uri = Uri.tryParse(origin);
    if (firebaseAvailability != FirebaseAvailability.ready ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return (uid) => FirebaseProfileSession(
      FirebaseAuth.instance,
      ownerUid: uid,
    ).repository(uri);
  }

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider<PublicJobsRepository?>(
        create: (_) {
          if (publicJobsRepository != null) return publicJobsRepository;
          const origin = String.fromEnvironment('PUBLIC_JOBS_API_ORIGIN');
          if (origin.isEmpty) return null;
          return ApiPublicJobsRepository(origin: Uri.parse(origin));
        },
        dispose: (repository) {
          if (publicJobsRepository == null &&
              repository is ApiPublicJobsRepository) {
            repository.close();
          }
        },
        child: _buildApplication(context),
      );

  Widget _buildApplication(BuildContext context) =>
      RepositoryProvider<AuthRepository?>(
        create: (_) =>
            authRepository ??
            (firebaseAvailability == FirebaseAvailability.ready
                ? FirebaseAuthRepository(FirebaseAuth.instance)
                : null),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => JobsCubit(DemoJobRepository())..load()),
            BlocProvider(
              create: (context) =>
                  SessionCubit(context.read<AuthRepository?>()),
            ),
          ],
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
                              'Account service setup is unavailable. You can still explore jobs.',
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: child!),
                    ],
                  )
                : child!,
            initialRoute: initialRoute,
            onGenerateRoute: (settings) {
              final uri = Uri.tryParse(settings.name ?? '');
              final parts = uri?.pathSegments ?? const <String>[];
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (context) {
                  final id = parts.length == 2 && parts.first == 'jobs'
                      ? parts.last
                      : '';
                  final repository = context.read<PublicJobsRepository?>();
                  return repository == null
                      ? JobDetailsPage(jobId: id)
                      : PublicJobDetailsPage(repository: repository, jobId: id);
                },
              );
            },
            routes: {
              AppRoutes.profile: (_) => const ProfilePage(),
              AppRoutes.profileEdit: (_) =>
                  ProfileEditPage(repositoryFactory: _profiles),
              AppRoutes.discover: (context) {
                final repository = context.read<PublicJobsRepository?>();
                return repository == null
                    ? const JobDiscoveryPage()
                    : PublicJobDiscoveryPage(repository: repository);
              },
              AppRoutes.signIn: (context) => AccountPage(
                mode: AccountMode.signIn,
                repository: context.read<AuthRepository?>(),
              ),
              AppRoutes.register: (context) => AccountPage(
                mode: AccountMode.register,
                repository: context.read<AuthRepository?>(),
              ),
              AppRoutes.resetPassword: (context) => AccountPage(
                mode: AccountMode.resetPassword,
                repository: context.read<AuthRepository?>(),
              ),
            },
          ),
        ),
      );
}
