import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/routing/session_gate.dart';
import '../data/api_company_repository.dart';
import '../domain/company_repository.dart';
import 'company_cubit.dart';
import 'company_editor.dart';

class CompanyPage extends StatelessWidget {
  const CompanyPage({super.key, this.repositoryFactory});
  final CompanyRepository Function(String uid)? repositoryFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Company profile')),
    body: SessionGate(
      builder: (context, user) {
        if (!user.emailVerified) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Verify your email in Manage account before editing your company.',
              ),
            ),
          );
        }
        if (repositoryFactory == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Company onboarding is being connected. Please check back soon.',
              ),
            ),
          );
        }
        return _CompanySession(
          key: ValueKey(user.uid),
          create: () => repositoryFactory!(user.uid),
        );
      },
    ),
  );
}

class _CompanySession extends StatefulWidget {
  const _CompanySession({super.key, required this.create});
  final CompanyRepository Function() create;
  @override
  State<_CompanySession> createState() => _CompanySessionState();
}

class _CompanySessionState extends State<_CompanySession> {
  late final CompanyRepository repository;
  late final CompanyCubit cubit;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    repository = widget.create();
    cubit = CompanyCubit(repository)..load();
  }

  @override
  void dispose() {
    cubit.close();
    if (repository case final ApiCompanyRepository api) {
      api.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: cubit,
    child: BlocBuilder<CompanyCubit, CompanyState>(
      builder: (context, state) {
        if (state.status == CompanyStatus.ready) loaded = true;
        if (!loaded) {
          if (state.status == CompanyStatus.failure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load your company.'),
                  FilledButton(
                    onPressed: cubit.load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return const CompanyEditor();
      },
    ),
  );
}
