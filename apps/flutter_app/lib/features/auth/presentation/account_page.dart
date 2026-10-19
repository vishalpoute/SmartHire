import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/account_validation.dart';
import '../domain/auth_repository.dart';
import 'auth_action_cubit.dart';
import 'session_cubit.dart';
import 'account_summary.dart';

enum AccountMode { signIn, register, resetPassword }

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.mode, this.repository});
  final AccountMode mode;
  final AuthRepository? repository;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _email = TextEditingController();
  AuthActionCubit? _actions;
  bool _showPassword = false;
  bool _recruiter = false;
  bool _validated = false;

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _actions = AuthActionCubit(widget.repository!);
    }
  }

  bool get _register => widget.mode == AccountMode.register;
  bool get _reset => widget.mode == AccountMode.resetPassword;
  String get _title => _register
      ? 'Start your next chapter.'
      : _reset
      ? 'Let’s get you back in.'
      : 'Welcome back.';

  @override
  void dispose() {
    _password.dispose();
    _email.dispose();
    _actions?.close();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_actions == null) {
      setState(() => _validated = true);
    } else if (_reset) {
      _actions!.resetPassword(_email.text.trim());
    } else if (_register) {
      _actions!.register(_email.text.trim(), _password.text);
    } else {
      _actions!.signIn(_email.text.trim(), _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_actions == null) {
      return _form(context, const AuthActionState(AuthActionStatus.idle));
    }
    return BlocConsumer<AuthActionCubit, AuthActionState>(
      bloc: _actions,
      listener: (context, state) {
        if (state.status == AuthActionStatus.succeeded) {
          _password.clear();
          if (!_reset) _email.clear();
        }
      },
      builder: (context, state) => BlocBuilder<SessionCubit, SessionState>(
        builder: (context, session) {
          if (session.status == SessionStatus.signedIn &&
              session.user != null &&
              !_reset) {
            return AccountSummary(
              user: session.user!,
              actions: _actions!,
              state: state,
            );
          }
          return _form(context, state);
        },
      ),
    );
  }

  Widget _form(BuildContext context, AuthActionState actionState) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          return Row(
            children: [
              if (wide)
                Expanded(
                  child: Container(
                    color: AppTheme.ink,
                    padding: const EdgeInsets.all(56),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.bubble_chart,
                            color: Color(0xFFCBE1B8),
                            size: 46,
                          ),
                          SizedBox(height: 36),
                          Text(
                            'Your skills.\nYour possibilities.',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Find work that fits where you are,\nand where you want to go.',
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.6,
                              color: Color(0xFFCBE1B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(wide ? 48 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: () {
                          if (_validated) setState(() => _validated = false);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.of(context)
                                  .pushNamedAndRemoveUntil(
                                    AppRoutes.discover,
                                    (_) => false,
                                  ),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Explore jobs'),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              _title,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _register
                                  ? 'A thoughtful next step starts here.'
                                  : _reset
                                  ? 'Enter the email you use for SmartHire.'
                                  : 'Your next opportunity is worth coming back to.',
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0EBD9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _actions == null
                                    ? 'Account preview · Firebase connection is coming next. No account will be created and no details will be sent.'
                                    : 'Secure email sign-in · Profile setup and recruiter approval are coming next.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF756336),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_register && _actions == null) ...[
                              TextFormField(
                                key: const Key('account-name'),
                                validator: AccountValidation.name,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                            TextFormField(
                              key: const Key('account-email'),
                              controller: _email,
                              validator: AccountValidation.email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: _reset
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              onFieldSubmitted: _reset
                                  ? (_) => _submit()
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                              ),
                            ),
                            if (!_reset) ...[
                              const SizedBox(height: 18),
                              TextFormField(
                                key: const Key('account-password'),
                                controller: _password,
                                obscureText: !_showPassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                validator: _register
                                    ? AccountValidation.newPassword
                                    : AccountValidation.signInPassword,
                                textInputAction: _register
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                onFieldSubmitted: _register
                                    ? null
                                    : (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: _register
                                      ? 'At least 8 characters'
                                      : null,
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (_register) ...[
                              const SizedBox(height: 18),
                              TextFormField(
                                key: const Key('account-confirm'),
                                obscureText: !_showPassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: (value) =>
                                    value != _password.text ||
                                        (value ?? '').isEmpty
                                    ? 'Passwords must match'
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                ),
                              ),
                            ],
                            if (_register && _actions == null) ...[
                              const SizedBox(height: 24),
                              const Text(
                                'I’m here to',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Find a job'),
                                    selected: !_recruiter,
                                    onSelected: (_) =>
                                        setState(() => _recruiter = false),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Hire people'),
                                    selected: _recruiter,
                                    onSelected: (_) =>
                                        setState(() => _recruiter = true),
                                  ),
                                ],
                              ),
                              if (_recruiter)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Recruiter accounts will need approval before publishing jobs.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            if (!_register && !_reset)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.pushReplacementNamed(
                                        context,
                                        AppRoutes.resetPassword,
                                      ),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                key: const Key('account-submit'),
                                onPressed:
                                    actionState.status ==
                                        AuthActionStatus.submitting
                                    ? null
                                    : _submit,
                                child: Text(
                                  actionState.status ==
                                          AuthActionStatus.submitting
                                      ? 'Please wait…'
                                      : _actions == null
                                      ? 'Check details'
                                      : _reset
                                      ? 'Request reset link'
                                      : _register
                                      ? 'Create account'
                                      : 'Sign in',
                                ),
                              ),
                            ),
                            if (!_reset &&
                                widget.repository?.supportsGoogle == true) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  key: const Key('google-sign-in'),
                                  onPressed:
                                      actionState.status ==
                                          AuthActionStatus.submitting
                                      ? null
                                      : () => _actions!.signInWithGoogle(),
                                  child: const Text('Continue with Google'),
                                ),
                              ),
                            ],
                            if (_validated)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Text(
                                  'Your details look valid. This preview does not sign you in, create an account or send a reset email.',
                                  key: Key('account-preview-result'),
                                ),
                              ),
                            if (actionState.message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  actionState.message!,
                                  key: const Key('account-action-message'),
                                ),
                              ),
                            const SizedBox(height: 18),
                            TextButton(
                              onPressed: () => Navigator.pushReplacementNamed(
                                context,
                                _register || _reset
                                    ? AppRoutes.signIn
                                    : AppRoutes.register,
                              ),
                              child: Text(
                                _register || _reset
                                    ? 'Already have an account? Sign in'
                                    : 'New to SmartHire? Create an account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
