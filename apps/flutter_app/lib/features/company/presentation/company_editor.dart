import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/company.dart';
import 'company_cubit.dart';

class CompanyEditor extends StatefulWidget {
  const CompanyEditor({super.key});
  @override
  State<CompanyEditor> createState() => _CompanyEditorState();
}

class _CompanyEditorState extends State<CompanyEditor> {
  late final List<TextEditingController> fields;
  late List<String> saved;
  bool allowExit = false;
  bool confirming = false;
  List<String> get values => fields.map((c) => c.text).toList();
  bool get dirty => !listEquals(values, saved);

  @override
  void initState() {
    super.initState();
    final d = context.read<CompanyCubit>().state.draft;
    saved = [d.name, d.description, d.location, d.website];
    fields = saved.map((s) => TextEditingController(text: s)).toList();
    for (final c in fields) {
      c.addListener(changed);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> leave(bool didPop) async {
    if (didPop || confirming || context.read<CompanyCubit>().busy || !dirty) {
      return;
    }
    confirming = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your company edits have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    confirming = false;
    if (discard == true) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void submit() {
    final cubit = context.read<CompanyCubit>();
    cubit.edit(
      CompanyDraft(
        name: fields[0].text,
        description: fields[1].text,
        location: fields[2].text,
        website: fields[3].text,
      ),
    );
    cubit.save();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CompanyCubit, CompanyState>(
        listener: (context, state) {
          if (state.status == CompanyStatus.saved) {
            final d = state.draft;
            saved = [d.name, d.description, d.location, d.website];
            for (var i = 0; i < fields.length; i++) {
              fields[i].text = saved[i];
            }
          }
        },
        builder: (context, state) {
          final busy = context.read<CompanyCubit>().busy;
          const keys = ['name', 'description', 'location', 'website'];
          const labels = ['Company name', 'Description', 'Location', 'Website'];
          return PopScope<void>(
            canPop: allowExit || (!dirty && !busy),
            onPopInvokedWithResult: (didPop, _) => leave(didPop),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your company',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(switch (state.approval) {
                        CompanyApproval.approved => 'Approved for recruiting',
                        CompanyApproval.rejected =>
                          'Review rejected. Update your company and resubmit.',
                        CompanyApproval.pending =>
                          'Pending administrator review',
                        null => 'Create your company profile to request recruiter approval.',
                      }),
                      const SizedBox(height: 12),
                      const Text(
                        'Saving changes submits your company for review again. Publishing requires approval.',
                      ),
                      for (var i = 0; i < fields.length; i++) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: fields[i],
                          enabled: !busy,
                          minLines: i == 1 ? 3 : 1,
                          maxLines: i == 1 ? 6 : 1,
                          keyboardType: i == 3
                              ? TextInputType.url
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: labels[i],
                            errorText: state.errors[keys[i]],
                          ),
                        ),
                      ],
                      if (state.message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(state.message!),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: Text(busy ? 'Submitting…' : 'Submit for review'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
