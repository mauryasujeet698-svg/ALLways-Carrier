import 'package:flutter/material.dart';

class AllwaysPrivacyPolicyScreen extends StatelessWidget {
  const AllwaysPrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & Terms')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: const [
        Text('ALLways Privacy Policy', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        SizedBox(height: 6),
        Text('This in-app notice explains the main data used by ALLways partner and administration apps. The actual handling of data depends on the features you use and the permissions you grant.'),
        SizedBox(height: 18),
        Text('Information we use', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Account details such as your name, email address, phone number and account identifier; partner profile, vehicle and verification details you submit; trip, delivery, booking, fare and support records; and technical information needed to operate and secure the service.'),
        SizedBox(height: 14),
        Text('Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Location permission may be used to show nearby requests, provide navigation and share your position while you are online or completing an active trip or delivery. Turn off availability and review Android location permissions when you do not want availability-based tracking. Android may restrict location updates in the background.'),
        SizedBox(height: 14),
        Text('Notifications, calls and safety', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Notification tokens and preferences are used to deliver relevant service alerts. If you use call, support or SOS features, the information you submit may be shared with the relevant service participant or ALLways operations to handle the request. SOS in the app is not a substitute for local emergency services.'),
        SizedBox(height: 14),
        Text('How information is used and shared', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Information is used to authenticate accounts, match and manage rides or deliveries, calculate and display operational records, verify partners, respond to support requests, prevent misuse and maintain the service. Necessary details may be shared with the customer or partner involved in a transaction and with technology providers that help operate maps, hosting, notifications or image storage.'),
        SizedBox(height: 14),
        Text('Retention, security and your choices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Records may be retained for operations, dispute handling, security and legal obligations. Do not upload information you are not authorized to share. Protect your device and account credentials. For access, correction or deletion requests, contact ALLways through the in-app Help & Support option; some transaction or legal records may need to be retained.'),
        SizedBox(height: 18),
        Divider(),
        SizedBox(height: 8),
        Text('Terms of Use', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        SizedBox(height: 6),
        Text('Use the app only for its intended role and provide accurate information. Do not misuse customer or partner data, falsify trip or delivery status, bypass verification, harass other users, or submit fraudulent documents or bookings. Follow applicable laws, traffic rules and safety instructions.'),
        SizedBox(height: 10),
        Text('Availability and responsibility', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Features depend on network connectivity, device permissions, location accuracy and service availability. Check trip and delivery details before proceeding. Report errors or safety concerns through Help & Support. Features and terms may be updated as the service develops.'),
        SizedBox(height: 10),
        Text('Questions or privacy requests: use Help & Support inside the ALLways app.', style: TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
