import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Privacy and grievance entry point for an authenticated ALLways partner.
/// Requests are recorded for review; the UI never claims that deletion or
/// correction has completed merely because a request was submitted.
class AccountSecurityScreen extends StatefulWidget {
  final User user;
  final String role;
  final String repository;
  final Color accent;

  const AccountSecurityScreen({
    super.key,
    required this.user,
    required this.role,
    required this.repository,
    required this.accent,
  });

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool _submitting = false;

  Future<void> _submitRequest({String initialType = 'grievance'}) async {
    final formKey = GlobalKey<FormState>();
    final details = TextEditingController();
    String requestType = initialType;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Privacy request or grievance'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: requestType,
                      decoration: const InputDecoration(labelText: 'Request type'),
                      items: const [
                        DropdownMenuItem(value: 'grievance', child: Text('Privacy grievance / complaint')),
                        DropdownMenuItem(value: 'access', child: Text('Request access to my data')),
                        DropdownMenuItem(value: 'correction', child: Text('Correct my information')),
                        DropdownMenuItem(value: 'erasure', child: Text('Request account/data erasure')),
                        DropdownMenuItem(value: 'location', child: Text('Report a location-tracking concern')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => requestType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: details,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Details',
                        hintText: 'Describe the request or issue without including passwords or OTPs.',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().length < 10) {
                          return 'Please provide at least 10 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Submission records a request for review; it does not mean the request is already completed. '
                      'Some records may need to be retained for an active transaction, safety, fraud prevention or a legal obligation.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) {
      details.dispose();
      return;
    }

    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('privacyRequests').add({
        'uid': widget.user.uid,
        'role': widget.role,
        'requestType': requestType,
        'details': details.text.trim(),
        'status': 'submitted',
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'partner_android_app',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request submitted for review. Keep its status here for updates.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request could not be submitted. Check your connection and try again.')),
        );
      }
    } finally {
      details.dispose();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openReleases() async {
    final uri = Uri.parse('https://github.com/${widget.repository}/releases');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the release page. Please try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Account Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: widget.accent),
              title: const Text('Location privacy'),
              subtitle: const Text(
                'Location is needed for dispatch only while you are on duty or completing an active job. '
                'Going off duty stops the app location stream and asks the server to clear live location.',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: widget.accent),
              title: const Text('Request account deletion'),
              subtitle: const Text(
                'Submit an account and data erasure request for review. Your account is not deleted immediately; '
                'ALLways must verify the request and check active jobs and lawful retention requirements.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _submitting ? null : () => _submitRequest(initialType: 'erasure'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.support_agent_outlined, color: widget.accent),
              title: const Text('Privacy grievance and data requests'),
              subtitle: const Text('Request access, correction, erasure, or report a privacy concern.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _submitting ? null : _submitRequest,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Signed-in account'),
              subtitle: Text(user.email ?? user.phoneNumber ?? user.uid),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.system_update_alt, color: widget.accent),
              title: const Text('App updates'),
              subtitle: const Text('Open the latest release page.'),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openReleases,
            ),
          ),
          const SizedBox(height: 18),
          const Text('My privacy requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('privacyRequests')
                .where('uid', isEqualTo: user.uid)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(child: ListTile(title: Text('Request history is temporarily unavailable.')));
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('No privacy requests yet'),
                    subtitle: Text('Requests you submit will appear here.'),
                  ),
                );
              }
              final docs = snapshot.data!.docs.toList()
                ..sort((a, b) {
                  final at = a.data()['createdAt'];
                  final bt = b.data()['createdAt'];
                  final am = at is Timestamp ? at.millisecondsSinceEpoch : 0;
                  final bm = bt is Timestamp ? bt.millisecondsSinceEpoch : 0;
                  return bm.compareTo(am);
                });
              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final type = (data['requestType'] ?? 'request').toString();
                  final status = (data['status'] ?? 'submitted').toString();
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined, color: widget.accent),
                      title: Text(type.replaceAll('_', ' ').toUpperCase()),
                      subtitle: Text('Status: $status\n${(data['details'] ?? '').toString()}'),
                      isThreeLine: true,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (_submitting)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          const Text(
            'This screen provides a request route and a practical summary; it is not a substitute for a formally reviewed privacy notice or a completed compliance assessment.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
