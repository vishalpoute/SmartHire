import 'package:flutter/material.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/account_validation.dart';

enum AccountMode { signIn, register, resetPassword }

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.mode});
  final AccountMode mode;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _recruiter = false;
  bool _validated = false;

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
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _validated = true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                              child: const Text(
                                'Account preview · Firebase connection is coming next. No account will be created and no details will be sent.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF756336),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_register) ...[
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
                                onPressed: _submit,
                                child: const Text('Check details'),
                              ),
                            ),
                            if (_validated)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: Text(
                                  'Your details look valid. This preview does not sign you in, create an account or send a reset email.',
                                  key: Key('account-preview-result'),
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
