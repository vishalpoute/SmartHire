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
import 'features/company/presentation/company_page.dart';
import 'features/company/domain/company_repository.dart';
import 'features/company/data/api_company_repository.dart';
import 'features/recruiter_review/domain/recruiter_review.dart';
import 'features/recruiter_review/data/api_recruiter_review_repository.dart';
import 'features/recruiter_review/presentation/recruiter_review_page.dart';
import 'features/recruiter_jobs/domain/recruiter_job.dart';
import 'features/recruiter_jobs/data/api_recruiter_jobs_repository.dart';
import 'features/recruiter_jobs/presentation/recruiter_jobs_page.dart';
import 'features/resumes/domain/resume.dart';
import 'features/resumes/data/api_resume_repository.dart';
import 'features/resumes/presentation/resumes_page.dart';
import 'features/applications/domain/application.dart';
import 'features/applications/data/api_applications_repository.dart';
import 'features/applications/presentation/applications_page.dart';
import 'features/saved_jobs/domain/saved_job.dart';
import 'features/saved_jobs/data/api_saved_jobs_repository.dart';
import 'features/saved_jobs/presentation/saved_jobs_page.dart';
import 'features/moderation/domain/moderation.dart';
import 'features/moderation/data/api_moderation_repository.dart';
import 'features/moderation/presentation/moderation_page.dart';
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
    this.companyRepositoryFactory,
    this.reviewRepositoryFactory,
    this.recruiterJobsRepositoryFactory,
    this.resumeRepositoryFactory,
    this.resumePicker,
    this.applicationsRepositoryFactory,
    this.savedJobsRepositoryFactory,
    this.moderationRepositoryFactory,
    this.publicJobsRepository,
  });
  final PublicJobsRepository? publicJobsRepository;
  final FirebaseAvailability firebaseAvailability;
  final AuthRepository? authRepository;
  final String? initialRoute;
  final ProfileRepository Function(String uid)? profileRepositoryFactory;
  final CompanyRepository Function(String uid)? companyRepositoryFactory;
  final RecruiterReviewRepository Function(String uid)? reviewRepositoryFactory;
  final RecruiterJobsRepository Function(String uid)?
  recruiterJobsRepositoryFactory;
  final ResumeRepository Function(String uid)? resumeRepositoryFactory;
  final Future<PickedResume?> Function()? resumePicker;
  final ApplicationsRepository Function(String uid)?
  applicationsRepositoryFactory;
  final SavedJobsRepository Function(String uid)? savedJobsRepositoryFactory;
  final ModerationRepository Function(String uid)? moderationRepositoryFactory;

  ModerationRepository Function(String)? get _moderation {
    if (moderationRepositoryFactory != null) return moderationRepositoryFactory;
    const value = String.fromEnvironment('MODERATION_API_ORIGIN');
    final origin = Uri.tryParse(value);
    if (origin == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      return null;
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiModerationRepository(
        origin: origin,
        ownerUid: uid,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  SavedJobsRepository Function(String)? get _savedJobs {
    if (savedJobsRepositoryFactory != null) return savedJobsRepositoryFactory;
    const value = String.fromEnvironment('SAVED_JOBS_API_ORIGIN');
    final origin = Uri.tryParse(value);
    if (origin == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      return null;
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiSavedJobsRepository(
        origin: origin,
        ownerUid: uid,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  ApplicationsRepository Function(String)? get _applications {
    if (applicationsRepositoryFactory != null) {
      return applicationsRepositoryFactory;
    }
    const value = String.fromEnvironment('APPLICATIONS_API_ORIGIN');
    final origin = Uri.tryParse(value);
    if (origin == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      return null;
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiApplicationsRepository(
        origin: origin,
        ownerUid: uid,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  ResumeRepository Function(String)? get _resumes {
    if (resumeRepositoryFactory != null) return resumeRepositoryFactory;
    const origin = String.fromEnvironment('RESUME_API_ORIGIN');
    const storageOrigin = String.fromEnvironment('RESUME_STORAGE_ORIGIN');
    final api = Uri.tryParse(origin), storage = Uri.tryParse(storageOrigin);
    for (final uri in [api, storage]) {
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        return null;
      }
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiResumeRepository(
        origin: api!,
        storageOrigin: storage!,
        ownerUid: uid,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  RecruiterJobsRepository Function(String)? get _recruiterJobs {
    if (recruiterJobsRepositoryFactory != null) {
      return recruiterJobsRepositoryFactory;
    }
    const origin = String.fromEnvironment('RECRUITER_JOBS_API_ORIGIN');
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiRecruiterJobsRepository(
        origin: uri,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  RecruiterReviewRepository Function(String)? get _reviews {
    if (reviewRepositoryFactory != null) return reviewRepositoryFactory;
    const origin = String.fromEnvironment('REVIEW_API_ORIGIN');
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiRecruiterReviewRepository(
        origin: uri,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

  CompanyRepository Function(String)? get _companies {
    if (companyRepositoryFactory != null) return companyRepositoryFactory;
    const origin = String.fromEnvironment('COMPANY_API_ORIGIN');
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
    return (uid) {
      final session = FirebaseProfileSession(
        FirebaseAuth.instance,
        ownerUid: uid,
      );
      return ApiCompanyRepository(
        origin: uri,
        session: session.read,
        currentUid: () => session.currentUid,
      );
    };
  }

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
                  if (parts.length == 2 && parts.first == 'apply') {
                    return ApplicationsPage(
                      repositoryFactory: _applications,
                      jobId: parts.last,
                    );
                  }
                  final id = parts.length == 2 && parts.first == 'jobs'
                      ? parts.last
                      : '';
                  if (parts.length == 2 && parts.first == 'save') {
                    return SavedJobsPage(
                      repositoryFactory: _savedJobs,
                      jobId: parts.last,
                    );
                  }
                  final repository = context.read<PublicJobsRepository?>();
                  return repository == null
                      ? JobDetailsPage(jobId: id)
                      : PublicJobDetailsPage(
                          repository: repository,
                          jobId: id,
                          applicationsAvailable: _applications != null,
                          savingAvailable: _savedJobs != null,
                        );
                },
              );
            },
            routes: {
              AppRoutes.profile: (_) => const ProfilePage(),
              AppRoutes.company: (_) =>
                  CompanyPage(repositoryFactory: _companies),
              AppRoutes.recruiterReviews: (_) =>
                  RecruiterReviewPage(repositoryFactory: _reviews),
              AppRoutes.recruiterJobs: (_) =>
                  RecruiterJobsPage(repositoryFactory: _recruiterJobs),
              AppRoutes.resumes: (_) => ResumesPageView(
                repositoryFactory: _resumes,
                picker: resumePicker,
              ),
              AppRoutes.applications: (_) =>
                  ApplicationsPage(repositoryFactory: _applications),
              AppRoutes.savedJobs: (_) =>
                  SavedJobsPage(repositoryFactory: _savedJobs),
              AppRoutes.moderation: (_) =>
                  ModerationPage(repositoryFactory: _moderation),
              AppRoutes.recruiterApplications: (_) => ApplicationsPage(
                repositoryFactory: _applications,
                recruiter: true,
              ),
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
