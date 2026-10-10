import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Account settings shared in behaviour across ALLways partner/admin apps.
/// Account deletion is submitted as a request; it is not falsely presented as
/// completed until the server-side deletion workflow has processed it.
class AccountSecurityScreen extends StatefulWidget {
  final User user;
  final String role;
  final String profileCollection;
  final String repository;
  final Color accent;
  const AccountSecurityScreen({
    super.key,
    required this.user,
    required this.role,
    required this.profileCollection,
    required this.repository,
    required this.accent,
  });

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _requestingDeletion = false;

  Future<void> _checkForUpdates() async {
    final uri = Uri.parse('https://github.com/${widget.repository}/releases');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the updates page. Please try again later.')),
      );
    }
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Privacy Policy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                SizedBox(height: 12),
                Text('ALLways uses account and profile information to provide partner/admin access and operate the services you use.'),
                SizedBox(height: 10),
                Text('Location information may be processed while a partner is online or handling an active delivery or ride, where required for dispatch and tracking.'),
                SizedBox(height: 10),
                Text('Operational records, support requests and transaction records may be retained where needed for safety, dispute resolution, legal obligations or platform operations.'),
                SizedBox(height: 10),
                Text('Access to account information should be limited to authorised personnel and service providers needed to operate ALLways. Do not enter another person’s personal information unless you are authorised to do so.'),
                SizedBox(height: 10),
                Text('You can submit an account deletion request from Account & Security. Some records may need to be retained where required by law or to resolve active transactions. A request is not complete until ALLways confirms processing.'),
                SizedBox(height: 10),
                Text('This in-app notice is a summary and does not replace a formally published, legally reviewed ALLways privacy policy.'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'This submits a deletion request for review. It will not instantly erase your account or records. '
          'Any active ride, delivery, payment or dispute must be handled before deletion can be completed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _requestingDeletion = true);
    try {
      await FirebaseFirestore.instance.collection('accountDeletionRequests').add({
        'uid': widget.user.uid,
        'email': widget.user.email ?? '',
        'role': widget.role,
        'profileCollection': widget.profileCollection,
        'status': 'requested',
        'requestedAt': FieldValue.serverTimestamp(),
        'source': 'android_app',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deletion request submitted. Your account remains active until processing is confirmed.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit the request. Please contact ALLways support.')),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingDeletion = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & Security')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: ListTile(
          leading: Icon(Icons.system_update_alt, color: widget.accent),
          title: const Text('Check for updates'),
          subtitle: const Text('Open the latest release page. The app also checks for updates automatically.'),
          trailing: const Icon(Icons.open_in_new),
          onTap: _checkForUpdates,
        )),
        Card(child: ListTile(
          leading: Icon(Icons.privacy_tip_outlined, color: widget.accent),
          title: const Text('Privacy Policy'),
          subtitle: const Text('How account and operational information is handled'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showPrivacyPolicy,
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.email_outlined),
          title: const Text('Signed-in account'),
          subtitle: Text(widget.user.email ?? widget.user.phoneNumber ?? widget.user.uid),
        )),
        const SizedBox(height: 18),
        const Text('Delete Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('You can request deletion of your account. The request must be processed securely and may be delayed while active work or legally required records are resolved.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _requestingDeletion ? null : _requestDeletion,
          icon: _requestingDeletion
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.delete_forever_outlined, color: Colors.red),
          label: Text(_requestingDeletion ? 'Submitting request…' : 'Request account deletion'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    ),
  );
}
