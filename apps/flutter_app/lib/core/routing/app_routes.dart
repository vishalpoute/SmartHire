abstract final class AppRoutes {
  static String jobDetails(String id) => '/jobs/${Uri.encodeComponent(id)}';
  static const discover = '/';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const company = '/company';
  static const recruiterReviews = '/admin/recruiter-reviews';
  static const recruiterJobs = '/recruiter/jobs';
  static const resumes = '/resumes';
  static const applications = '/applications';
  static const recruiterApplications = '/recruiter/applications';
  static const signIn = '/sign-in';
  static const register = '/register';
  static const resetPassword = '/reset-password';
}
