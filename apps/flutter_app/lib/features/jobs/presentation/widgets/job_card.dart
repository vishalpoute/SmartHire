import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/routing/app_routes.dart';
import '../../domain/job.dart';

class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.saved,
    required this.onSave,
  });
  final Job job;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEDF1EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                job.company.substring(0, 1),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                job.company,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
            ),
            IconButton(
              tooltip: saved ? 'Unsave ${job.title}' : 'Save ${job.title}',
              onPressed: onSave,
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(job.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('${job.location} · ${job.mode.label} · Full-time'),
        const SizedBox(height: 18),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final skill in job.skills)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.canvas,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(skill, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.salary,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  '${job.postedDaysAgo}d ago · Sample',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _showDetails(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View role'),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 17),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  void _showDetails(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.jobDetails(job.id));
}
