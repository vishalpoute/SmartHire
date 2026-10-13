import '../domain/job.dart';
import '../domain/job_repository.dart';

/// Fictional fixtures for local development. No live vacancies are represented.
class DemoJobRepository implements JobRepository {
  @override
  Future<List<Job>> fetchPublishedJobs() async => const [
    Job(
      id: 'fern-mobile',
      title: 'Flutter Developer',
      company: 'Fern Studio',
      location: 'Bengaluru',
      mode: WorkMode.hybrid,
      salary: '₹6–9 LPA',
      skills: ['Flutter', 'Dart', 'Firebase', 'BLoC'],
      postedDaysAgo: 1,
      description: 'Help a small product team build thoughtful mobile experiences. Own features from interface design through release, collaborate with backend engineers, and keep our Android app fast and accessible.',
    ),
    Job(
      id: 'northstar-product',
      title: 'Mobile Product Engineer',
      company: 'Northstar Labs',
      location: 'India',
      mode: WorkMode.remote,
      salary: '₹8–12 LPA',
      skills: ['Flutter', 'Dart', 'REST APIs'],
      postedDaysAgo: 2,
      description: 'Build reliable cross-platform workflows for growing teams. Work closely with design, improve reusable components, and use profiling and tests to deliver a responsive product.',
    ),
    Job(
      id: 'orbit-python',
      title: 'Junior Python Developer',
      company: 'Orbit Works',
      location: 'Pune',
      mode: WorkMode.onsite,
      salary: '₹4–7 LPA',
      skills: ['Python', 'FastAPI', 'SQL'],
      postedDaysAgo: 3,
      description: 'Develop clear, well-tested APIs and data integrations. This junior role includes mentoring, code reviews and opportunities to own small services from implementation to deployment.',
    ),
    Job(
      id: 'moss-frontend',
      title: 'Frontend Engineer',
      company: 'Moss Collective',
      location: 'Mumbai',
      mode: WorkMode.hybrid,
      salary: '₹7–10 LPA',
      skills: ['React', 'TypeScript', 'Accessibility'],
      postedDaysAgo: 4,
      description: 'Create accessible, responsive web experiences for our customer platform. Partner with designers, refine interaction details and improve the performance of everyday workflows.',
    ),
  ];
}
