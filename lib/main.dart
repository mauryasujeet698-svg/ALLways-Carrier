import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const purple=Color(0xFF5B1ACF);
const ivory=Color(0xFFF8F6F0);

@pragma('vm:entry-point')
Future<void> _background(RemoteMessage message) async { await Firebase.initializeApp(); }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await GoogleSignIn.instance.initialize();
  FirebaseMessaging.onBackgroundMessage(_background);
  runApp(const AllwaysCarrierApp());
}

class AllwaysCarrierApp extends StatelessWidget {
  const AllwaysCarrierApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'ALLways Carrier',
    theme:ThemeData(
      useMaterial3:true,
      colorScheme:ColorScheme.fromSeed(seedColor:purple),
      scaffoldBackgroundColor:ivory,
      textTheme:GoogleFonts.poppinsTextTheme(),
      cardTheme:const CardThemeData(color:Colors.white,elevation:0,margin:EdgeInsets.zero),
    ),
    home:const AuthGate(),
  );
}

class AuthGate extends StatelessWidget{
 const AuthGate({super.key});
 @override Widget build(BuildContext context)=>StreamBuilder<User?>(stream:FirebaseAuth.instance.authStateChanges(),builder:(context,s){
  if(s.data==null)return const CarrierLoginPage();
  return FutureBuilder<DocumentSnapshot<Map<String,dynamic>>>(future:FirebaseFirestore.instance.collection('ridePartners').doc(s.data!.uid).get(),builder:(context,a){
   if(!a.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));
   if(!a.data!.exists)return PartnerRegistrationPage(user:s.data!);
   final p=a.data!.data()??{};final approval=(p['approvalStatus']??'').toString().toLowerCase();
   if(approval=='pending')return PendingApprovalPage(user:s.data!,rejected:false);
   if(approval=='rejected')return PendingApprovalPage(user:s.data!,rejected:true,reason:(p['rejectionReason']??'').toString());
   return CarrierShell(user:s.data!);
  });
 });
}

class CarrierLoginPage extends StatefulWidget {
  final String? message;
  const CarrierLoginPage({super.key,this.message});
  @override State<CarrierLoginPage> createState()=>_CarrierLoginPageState();
}
class _CarrierLoginPageState extends State<CarrierLoginPage>{
  final email=TextEditingController(),password=TextEditingController();
  bool busy=false,obscure=true;String? error;
  Future<void> login()async{
    if(email.text.trim().isEmpty||password.text.isEmpty)return;
    setState(()=>busy=true);
    try{await FirebaseAuth.instance.signInWithEmailAndPassword(email:email.text.trim(),password:password.text);}
    on FirebaseAuthException catch(e){if(mounted)setState(()=>error=e.message??e.code);}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    if(mounted)setState(()=>busy=false);
  }
  Future<void> signInWithGoogle() async {
    setState(() { busy = true; error = null; });
    try {
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw Exception('Google Sign-In is not supported on this device.');
      }
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google Sign-In did not return an ID token.');
      }
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => error = e.message ?? e.code);
    } on GoogleSignInException catch (e) {
      if (mounted) setState(() => error = e.description ?? e.code.toString());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override Widget build(BuildContext c)=>Scaffold(
    body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:440),
      child:Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const CircleAvatar(radius:30,backgroundColor:Color(0x1A5B1ACF),child:Icon(Icons.two_wheeler,color:purple,size:34)),
        const SizedBox(height:18),const Text('ALLways Carrier',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),const Text('Ride partner workspace'),
        if(widget.message!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(widget.message!,style:const TextStyle(color:Colors.red))),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(error!,style:const TextStyle(color:Colors.red))),
        const SizedBox(height:20),
        TextField(controller:email,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.email_outlined))),
        const SizedBox(height:12),
        TextField(controller:password,obscureText:obscure,decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility_outlined:Icons.visibility_off_outlined)))),
        const SizedBox(height:18),
        SizedBox(width:double.infinity,height:52,child:FilledButton(onPressed:busy?null:login,style:FilledButton.styleFrom(backgroundColor:purple),child:busy?const CircularProgressIndicator(color:Colors.white):const Text('Sign in'))),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')),
            Expanded(child: Divider()),
          ]),
        ),
        SizedBox(width:double.infinity,height:52,child:OutlinedButton.icon(onPressed:busy?null:signInWithGoogle,icon:const Icon(Icons.account_circle_outlined),label:const Text('Sign in with Google'))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48, child: TextButton(
            onPressed: busy ? null : signInWithGoogle,
            child: const Text('Create New Account'),
          )),
      ])),
    ))))),
  );
}


class PartnerRegistrationPage extends StatefulWidget {
  final User user;
  const PartnerRegistrationPage({super.key, required this.user});
  @override State<PartnerRegistrationPage> createState() => _PartnerRegistrationPageState();
}

class _PartnerRegistrationPageState extends State<PartnerRegistrationPage> {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final address = TextEditingController();
  String vehicleType = 'bike';
  final vehicleNumber = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (name.text.trim().isEmpty ||
        mobile.text.trim().isEmpty ||
        address.text.trim().isEmpty ||
                vehicleNumber.text.trim().isEmpty) {
      setState(() => error = 'Please complete all required fields.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final ref = FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid);
      await ref.set({
        'uid': widget.user.uid,
        'role': 'carrier',
        'name': name.text.trim(),
        'displayName': name.text.trim(),
        'email': widget.user.email,
        'phone': mobile.text.trim(),
        'mobileNumber': mobile.text.trim(),
        'address': address.text.trim(),
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumber.text.trim().toUpperCase(),
        'profilePhotoUrl': widget.user.photoURL,
        'approvalStatus': 'pending',
        'status': 'pending',
        'availableForDeliveries': false,
        'availableForRides': false,
        'isOnline': false,
        'createdAt': FieldValue.serverTimestamp(),
        'submittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(TextEditingController controller, String label, {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create Partner Account')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Partner registration',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Complete your profile. Admin approval is required before you can go online.'),
          const SizedBox(height: 20),
          field(name, 'Full name'),
          field(mobile, 'Mobile number', keyboard: TextInputType.phone),
          field(address, 'Address'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: vehicleType,
              decoration: const InputDecoration(
                labelText: 'Vehicle type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'bike', child: Text('Bike')),
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'car', child: Text('Car')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => vehicleType = value);
              },
            ),
          ),
          field(vehicleNumber, 'Vehicle number'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit for approval'),
            ),
          ),
        ],
      ),
    ),
  );
}

class PendingApprovalPage extends StatelessWidget {
  final User user;
  final bool rejected;
  final String reason;
  const PendingApprovalPage({
    super.key,
    required this.user,
    required this.rejected,
    this.reason = '',
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    rejected ? Icons.cancel_outlined : Icons.hourglass_top,
                    size: 58,
                    color: rejected ? Colors.red : purple,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    rejected ? 'Registration rejected' : 'Approval pending',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rejected
                        ? (reason.isEmpty ? 'Please contact ALLways support for the next step.' : 'Reason: $reason')
                        : 'Your registration has been submitted. You can go online and accept work after Admin approval.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class CarrierShell extends StatefulWidget{
  final User user;const CarrierShell({super.key,required this.user});
  @override State<CarrierShell> createState()=>_CarrierShellState();
}
class _CarrierShellState extends State<CarrierShell>{
  int tab=0;bool online=false;Position? position;String vehicle='bike';String? activeRideId;
  StreamSubscription<Position>? locationSub;
  StreamSubscription<DocumentSnapshot<Map<String,dynamic>>>? activeRideSub;
  @override void initState(){super.initState();_load();_notifications();}
  @override void dispose(){locationSub?.cancel();activeRideSub?.cancel();super.dispose();}
  Future<void> _load()async{
    try{
      final r=await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).get();
      final x=r.data()??{};
      online=(x['status']??'offline').toString().toLowerCase()=='online';
      activeRideId=(x['activeRideId']??'').toString();if(activeRideId!.isEmpty)activeRideId=null;
      _watchActiveRide();
      vehicle=(x['vehicleType']??'bike').toString().toLowerCase();if(vehicle=='two_wheeler')vehicle='bike';
      if(online) await _startLocation();
    }catch(_){}
    if(mounted)setState((){});
  }
  void _watchActiveRide(){
    activeRideSub?.cancel();
    final id=activeRideId;
    if(id==null||id.isEmpty)return;
    final ref=FirebaseFirestore.instance.collection('autoRideRequests').doc(id);
    activeRideSub=ref.snapshots().listen((snap)async{
      final status=(snap.data()?['status']??'').toString().toLowerCase();
      if(const {'cancelled','completed','rejected','expired'}.contains(status)){
        await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({
          'status':'online',
          'availableForRides':true,
          'isOnline':true,
          'activeRideId':null,
          'statusUpdatedAt':FieldValue.serverTimestamp(),
        },SetOptions(merge:true));
        if(mounted)setState(()=>activeRideId=null);
        await activeRideSub?.cancel();
      }
    });
  }
  Future<void> _notifications()async{
    try{
      final p=await SharedPreferences.getInstance();
      if(p.getBool('notifications_enabled')==false)return;
      final s=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      if(s.authorizationStatus==AuthorizationStatus.denied)return;
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert:true,badge:true,sound:true);
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      await FirebaseMessaging.instance.subscribeToTopic('carriers');
      await p.setBool('notifications_enabled',true);

      Future<void> saveToken(String? t)async{
        if(t==null||t.isEmpty)return;
        final data={
          'uid':widget.user.uid,
          'token':t,
          'role':'carrier',
          'platform':'mobile',
          'notificationsEnabled':true,
          'notificationPreferences':{'travelUpdates':true,'offers':true,'announcements':true},
          'updatedAt':FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance.collection('fcmTokens').doc(widget.user.uid).collection('tokens').doc(t).set(data,SetOptions(merge:true));
        await FirebaseFirestore.instance.collection('fcmTokens').doc(widget.user.uid).set(data,SetOptions(merge:true));
      }

      await saveToken(await FirebaseMessaging.instance.getToken());
      FirebaseMessaging.instance.onTokenRefresh.listen(saveToken);
      FirebaseMessaging.onMessage.listen((RemoteMessage message){
        if(!mounted)return;
        final title=message.notification?.title??message.data['title']??'ALLways';
        final body=message.notification?.body??message.data['body']??'';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(body.isEmpty?title:'$title: $body'),
          duration:const Duration(seconds:4),
        ));
      });
    }catch(_){}
  }
  Future<bool> _permission()async{
    if(!await Geolocator.isLocationServiceEnabled())return false;
    var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
    return p!=LocationPermission.denied&&p!=LocationPermission.deniedForever;
  }
  Future<void> _startLocation()async{
    if(!await _permission())return;
    try{
      final LocationSettings settings = Platform.isAndroid && online
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 10),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'ALLways live ride tracking',
                notificationText: 'ALLways is sharing your location while you are online or on an active ride.',
                notificationChannelName: 'ALLways Live Ride Tracking',
                enableWakeLock: true,
                setOngoing: true,
              ),
            )
          : const LocationSettings(accuracy: LocationAccuracy.high,distanceFilter:10);
      final first=await Geolocator.getCurrentPosition(locationSettings:settings);position=first;await _savePosition(first);
      await locationSub?.cancel();
      locationSub=Geolocator.getPositionStream(locationSettings:settings).listen((p){position=p;_savePosition(p);if(mounted)setState((){});});
    }catch(_){}
  }
  Future<void> _savePosition(Position p)async{
    try{
      await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({'carrierLat':p.latitude,'carrierLng':p.longitude,'carrierLocationUpdatedAt':FieldValue.serverTimestamp(),'lastLocationAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      final id=activeRideId;
      if(id!=null)await FirebaseFirestore.instance.collection('autoRideRequests').doc(id).set({'driverLat':p.latitude,'driverLng':p.longitude,'driverLocationUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
    }catch(_){}
  }
  Future<void> _setOnline(bool value)async{
    if(value){
      final profile = await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).get();
      final approval = (profile.data()?['approvalStatus'] ?? '').toString().toLowerCase();
      if (approval.isNotEmpty && approval != 'approved') {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin approval is required before going online.')));
        return;
      }
    }
    if(value&&!await _permission()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Location permission is required before going online.')));return;}
    if(value)await _startLocation();else await locationSub?.cancel();
    final data={'status':value?'online':'offline','availableForRides':value,'isOnline':value,'statusUpdatedAt':FieldValue.serverTimestamp(),'vehicleType':vehicle};
    await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set(data,SetOptions(merge:true));
    if(mounted)setState(()=>online=value);
  }
  Future<void> _reject(DocumentReference ref)async{await ref.update({'rejectedBy':FieldValue.arrayUnion([widget.user.uid]),'updatedAt':FieldValue.serverTimestamp()});}
  double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
  Future<void> _accept(QueryDocumentSnapshot<Map<String,dynamic>> doc)async{
    try{
      await FirebaseFirestore.instance.runTransaction((tx)async{
        final latest=await tx.get(doc.reference);final x=latest.data()??{};
        if((x['status']??'').toString().toLowerCase()!='searching')throw Exception('Ride already accepted.');
        final p=await tx.get(FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid));final profile=p.data()??{};
        final existingActive=(profile['activeRideId']??'').toString().trim();
        final partnerStatus=(profile['status']??'').toString().toLowerCase();
        if(existingActive.isNotEmpty||partnerStatus=='on_trip')throw Exception('Complete your current ride before accepting another ride.');
        final requested=(x['rideType']??'bike').toString().toLowerCase();final mine=(profile['vehicleType']??vehicle).toString().toLowerCase();final normalized=mine=='two_wheeler'?'bike':mine;
        if(requested!=normalized)throw Exception('This ride is for a different vehicle type.');
        tx.update(doc.reference,{'status':'accepted','driverUid':widget.user.uid,'driverName':profile['name']??widget.user.displayName??'ALLways Carrier','driverPhone':profile['phone']??profile['mobileNumber']??widget.user.phoneNumber??'','driverVehicleType':normalized,'acceptedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        tx.set(p.reference,{'status':'on_trip','availableForRides':false,'activeRideId':doc.id,'statusUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      });
      if(mounted){setState(()=>activeRideId=doc.id);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride accepted.')));}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
  }
  Future<void> _complete(DocumentReference ref)async{
    await ref.update({'status':'completed','completedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
    await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({'status':'online','availableForRides':true,'activeRideId':null,'statusUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
    if(mounted)setState(()=>activeRideId=null);
  }
  Future<void> _call(String phone)async{final p=phone.replaceAll(RegExp(r'[^0-9+]'),'');if(p.isNotEmpty)await launchUrl(Uri(scheme:'tel',path:p),mode:LaunchMode.externalApplication);}
  Future<void> _sos()async{await FirebaseFirestore.instance.collection('sosAlerts').add({'uid':widget.user.uid,'role':'carrier','createdAt':FieldValue.serverTimestamp(),'status':'open'});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('SOS alert sent to ALLways operations.')));}
  Future<void> _vehicleDialog()async{
    final selected=await showDialog<String>(
      context:context,
      builder:(d)=>AlertDialog(
        title:const Text('Vehicle type'),
        content:StatefulBuilder(builder:(context,setDialogState)=>Column(
          mainAxisSize:MainAxisSize.min,
          children:[
            RadioListTile<String>(value:'bike',groupValue:vehicle,title:const Text('Bike'),secondary:const Icon(Icons.two_wheeler),onChanged:(v){if(v!=null)Navigator.pop(d,v);}),
            RadioListTile<String>(value:'auto',groupValue:vehicle,title:const Text('Auto'),secondary:const Icon(Icons.local_taxi_outlined),onChanged:(v){if(v!=null)Navigator.pop(d,v);}),
            RadioListTile<String>(value:'car',groupValue:vehicle,title:const Text('Car'),secondary:const Icon(Icons.directions_car_outlined),onChanged:(v){if(v!=null)Navigator.pop(d,v);}),
          ],
        )),
        actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Cancel'))],
      ),
    );
    if(selected==null)return;
    await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({'vehicleType':selected},SetOptions(merge:true));
    if(mounted)setState(()=>vehicle=selected);
  }
  @override Widget build(BuildContext context){
    final pages=[
      CarrierHome(online:online,position:position,activeRideId:activeRideId,onOnline:_setOnline),
      RideRequests(user:widget.user,online:online,position:position,vehicle:vehicle,activeRideId:activeRideId,onAccept:_accept,onReject:_reject),
      ActiveRide(rideId:activeRideId,position:position,onCall:_call,onComplete:_complete),
      CarrierEarnings(user:widget.user),
      CarrierProfile(user:widget.user,vehicle:vehicle,onVehicle:_vehicleDialog,onSos:_sos),
      CarrierVehiclePage(user:widget.user),
    ];
    return Scaffold(
      body:SafeArea(child:IndexedStack(index:tab,children:pages)),
      bottomNavigationBar:NavigationBar(
        selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),
        destinations:const[
          NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Home'),
          NavigationDestination(icon:Icon(Icons.near_me_outlined),selectedIcon:Icon(Icons.near_me),label:'Requests'),
          NavigationDestination(icon:Icon(Icons.navigation_outlined),selectedIcon:Icon(Icons.navigation),label:'Active Ride'),
          NavigationDestination(icon:Icon(Icons.currency_rupee_outlined),selectedIcon:Icon(Icons.currency_rupee),label:'Earnings'),
          NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile'),
          NavigationDestination(icon:Icon(Icons.directions_car_outlined),selectedIcon:Icon(Icons.directions_car),label:'Vehicle'),
        ],
      ),
    );
  }
}

class CarrierHome extends StatelessWidget {
  final bool online;
  final Position? position;
  final String? activeRideId;
  final Future<void> Function(bool) onOnline;

  const CarrierHome({
    super.key,
    required this.online,
    required this.position,
    required this.activeRideId,
    required this.onOnline,
  });

  @override
  Widget build(BuildContext context) {
    final center = position == null
        ? const LatLng(25.4358, 81.8463)
        : LatLng(position!.latitude, position!.longitude);

    final bottomItems = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where are you going?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: ivory,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search),
                    SizedBox(width: 10),
                    Text(
                      'Search pickup or destination',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recent destinations',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Prayagraj Civil Lines')),
                  Chip(label: Text('Railway Junction')),
                  Chip(label: Text('Sangam')),
                ],
              ),
            ],
          ),
        ),
      ),
    ];

    if (activeRideId != null) {
      bottomItems.add(
        Card(
          child: ListTile(
            leading: const Icon(Icons.navigation, color: purple),
            title: const Text(
              'Active ride',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('#' + activeRideId!),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      );
    }

    if (online) {
      bottomItems.insert(0,Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const CircleAvatar(backgroundColor:Color(0x1A5B1ACF),child:Icon(Icons.bolt,color:purple)),const SizedBox(width:10),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Next action',style:TextStyle(fontWeight:FontWeight.w900)),Text('Open Requests → Accept → Navigate → Complete',style:TextStyle(color:Colors.grey,fontSize:12))]))]))));
      bottomItems.add(
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'Nearby ride requests are shown in Requests.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
      );

      return Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                maxZoom: 19,
                userAgentPackageName: 'com.allways.carrier',
              ),
              if (position != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 64,
                      height: 64,
                      child: Container(
                        decoration: BoxDecoration(
                          color: purple,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: const Icon(
                          Icons.two_wheeler,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0x1A5B1ACF),
                        child: Icon(Icons.two_wheeler, color: purple),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ALLways Carrier',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              online
                                  ? 'Online • accepting rides within 25 km'
                                  : 'Offline • turn on to receive rides',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: online, onChanged: onOnline),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Column(children: bottomItems),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 14.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              maxZoom: 19,
              userAgentPackageName: 'com.allways.carrier',
            ),
            if (position != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 64,
                    height: 64,
                    child: Container(
                      decoration: BoxDecoration(
                        color: purple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: const Icon(
                        Icons.two_wheeler,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0x1A5B1ACF),
                      child: Icon(Icons.two_wheeler, color: purple),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ALLways Carrier',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Offline • turn on to receive rides',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: online, onChanged: onOnline),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Column(
              children: bottomItems,
            ),
          ),
        ),
      ],
    );
  }
}

class RideRequests extends StatelessWidget{
  final User user;final bool online;final Position? position;final String vehicle;final String? activeRideId;
  final Future<void> Function(QueryDocumentSnapshot<Map<String,dynamic>>) onAccept;final Future<void> Function(DocumentReference) onReject;
  const RideRequests({super.key,required this.user,required this.online,required this.position,required this.vehicle,required this.activeRideId,required this.onAccept,required this.onReject});
  double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
  @override Widget build(BuildContext c)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('autoRideRequests').where('status',isEqualTo:'searching').snapshots(),
    builder:(context,s){
      if(!online)return const Center(child:Text('Go online to receive ride requests.'));
      if(activeRideId!=null&&activeRideId!.isNotEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('You already have an active ride. Complete it before accepting another ride.',textAlign:TextAlign.center)));
      if(position==null)return const Center(child:Text('Live location is required to match rides.'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final list=<QueryDocumentSnapshot<Map<String,dynamic>>>[];
      for(final d in s.data!.docs){
        final x=d.data();
        final st=(x['status']??'').toString().trim().toLowerCase();
        if(st!='searching')continue;
        if(x['cancelledAt']!=null||x['completedAt']!=null||x['endedAt']!=null||x['rejectedAt']!=null||x['expiredAt']!=null)continue;
        final assignedUid=(x['driverUid']??x['carrierUid']??x['deliveryPartnerUid']??x['assignedPartnerId']??'').toString().trim();
        if(assignedUid.isNotEmpty)continue;
        final rejected=x['rejectedBy'] is List?List.from(x['rejectedBy']):<dynamic>[];
        if(rejected.contains(user.uid))continue;
        final type=(x['rideType']??'bike').toString().toLowerCase();if(type!=vehicle)continue;
        final lat=n(x['pickupLatitude']??x['pickupLat']);final lng=n(x['pickupLongitude']??x['pickupLng']);if(lat==0||lng==0)continue;
        if(Geolocator.distanceBetween(position!.latitude,position!.longitude,lat,lng)<=25000)list.add(d);
      }
      if(list.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('No ride requests within 25 km right now.',textAlign:TextAlign.center)));
      return ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[
        const Text('Ride Requests',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),
        ...list.map((d){final x=d.data();final lat=n(x['pickupLatitude']??x['pickupLat']);final lng=n(x['pickupLongitude']??x['pickupLng']);final km=Geolocator.distanceBetween(position!.latitude,position!.longitude,lat,lng)/1000;
          return Card(margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[CircleAvatar(backgroundColor:purple.withOpacity(.1),child:Icon((x['rideType']??'bike').toString()=='auto'?Icons.local_taxi_outlined:Icons.two_wheeler,color:purple)),const SizedBox(width:10),Expanded(child:Text((x['rideType']??'bike').toString().toUpperCase()+' RIDE',style:const TextStyle(fontWeight:FontWeight.w900))),Text(km.toStringAsFixed(1)+' km',style:const TextStyle(color:purple,fontWeight:FontWeight.w800))]),
            const SizedBox(height:10),Text((x['pickupAddress']??x['address']??'Pickup location').toString(),maxLines:2,overflow:TextOverflow.ellipsis),Text((x['destinationAddress']??x['destination']??'Destination').toString(),style:const TextStyle(color:Colors.grey),maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:8),
            Text('₹'+n(x['estimatedFare']??x['fare']??x['total']).toStringAsFixed(0),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
            const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>onReject(d.reference),child:const Text('Reject'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>onAccept(d),style:FilledButton.styleFrom(backgroundColor:purple),child:const Text('Accept')))]),
          ])));
        }),
      ]);
    },
  );
}

class Pin extends StatelessWidget {
  final Color color;
  final IconData icon;

  const Pin({super.key, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }
}

class ActiveRide extends StatefulWidget {
  final String? rideId;
  final Position? position;
  final Future<void> Function(String) onCall;
  final Future<void> Function(DocumentReference) onComplete;

  const ActiveRide({
    super.key,
    required this.rideId,
    required this.position,
    required this.onCall,
    required this.onComplete,
  });

  @override
  State<ActiveRide> createState() => _ActiveRideState();
}

class _ActiveRideState extends State<ActiveRide> {
  List<LatLng> route = [];
  bool routeLoading = false;
  final MapController mapController = MapController();
  bool mapReady = false;
  DateTime? lastCameraMove;
  List<Map<String,dynamic>> navSteps = [];
  int activeStep = 0;

  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  LatLng? point(dynamic latitude, dynamic longitude) {
    final lat = number(latitude);
    final lng = number(longitude);
    if (lat == 0 || lng == 0) return null;
    return LatLng(lat, lng);
  }

  Future<void> loadRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final coordinates = body['routes']?[0]?['geometry']?['coordinates'];
      if (coordinates is! List) return;

      final points = coordinates
          .whereType<List>()
          .where((item) => item.length >= 2)
          .map(
            (item) => LatLng(
              (item[1] as num).toDouble(),
              (item[0] as num).toDouble(),
            ),
          )
          .toList();

      final steps=<Map<String,dynamic>>[];
      final legs=body['routes']?[0]?['legs'];
      if(legs is List)for(final leg in legs){
        final raw=leg['steps'];
        if(raw is! List)continue;
        for(final step in raw){
          final m=step['maneuver'] is Map?Map<String,dynamic>.from(step['maneuver']):<String,dynamic>{};
          final type=(m['type']??'').toString();
          final modifier=(m['modifier']??'').toString();
          final distance=step['distance'] is num?(step['distance'] as num).toDouble():0;
          final loc=m['location'] is List&&(m['location'] as List).length>=2?LatLng(((m['location'] as List)[1] as num).toDouble(),((m['location'] as List)[0] as num).toDouble()):null;
          final instruction=type=='arrive'?'You have arrived':type=='depart'?'Start on the current road':modifier.isEmpty?'Continue straight':modifier.replaceAll('_',' ');
          steps.add({'instruction':instruction,'modifier':modifier,'distance':distance,'road':(step['name']??'').toString(),'location':loc});
        }
      }
      if (mounted) setState(() { route=points; navSteps=steps; activeStep=0; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    if (rideId == null || rideId.isEmpty) {
      return const Center(child: Text('No active ride.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('autoRideRequests')
          .doc(rideId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() ?? <String, dynamic>{};
        final pickup = point(
          data['pickupLatitude'] ?? data['pickupLat'],
          data['pickupLongitude'] ?? data['pickupLng'],
        );
        final destination = point(
          data['destinationLatitude'] ?? data['destLat'],
          data['destinationLongitude'] ?? data['destLng'],
        );
        final driver = point(data['driverLat'], data['driverLng']);
        final customer = point(
          data['customerLat'] ?? data['pickupLatitude'],
          data['customerLng'] ?? data['pickupLongitude'],
        );

        if (!routeLoading && driver != null && customer != null && (route.isEmpty || (data['status']??'accepted').toString().toLowerCase() == 'accepted' || (data['status']??'accepted').toString().toLowerCase() == 'started')) {
          routeLoading = true;
          final target = (data['status']??'accepted').toString().toLowerCase() == 'started' ? (destination ?? customer) : customer;
          loadRoute(driver, target);
        }

        final center =
            driver ?? pickup ?? destination ?? const LatLng(25.4358, 81.8463);

        final markers = <Marker>[
          if (driver != null)
            Marker(
              point: driver,
              width: 62,
              height: 62,
              child: const Pin(color: purple, icon: Icons.two_wheeler),
            ),
          if (customer != null)
            Marker(
              point: customer,
              width: 58,
              height: 58,
              child: const Pin(color: Colors.blue, icon: Icons.person),
            ),
          if (pickup != null)
            Marker(
              point: pickup,
              width: 58,
              height: 58,
              child: const Pin(color: Colors.green, icon: Icons.check),
            ),
          if (destination != null)
            Marker(
              point: destination,
              width: 58,
              height: 58,
              child: const Pin(color: Colors.red, icon: Icons.flag),
            ),
        ];

        final phone =
            (data['customerPhone'] ?? data['phone'] ?? '').toString();
        final status = (data['status'] ?? 'accepted').toString();
        final pickupAddress =
            (data['pickupAddress'] ?? 'Pickup').toString();
        final destinationAddress =
            (data['destinationAddress'] ?? 'Destination').toString();

        return Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.5,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  maxZoom: 19,
                  userAgentPackageName: 'com.allways.carrier',
                ),
                if (route.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        color: purple,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Card(
                  color: const Color(0xFFFDECEF),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: Colors.green,
                          size: 12,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Live ride tracking',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                status + (customer != null && driver != null ? ' • Customer ' + (Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude) < 1000 ? Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude).round().toString() + ' m away' : (Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude) / 1000).toStringAsFixed(1) + ' km away') : ''),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (phone.isNotEmpty)
                          IconButton(
                            onPressed: () => widget.onCall(phone),
                            icon: const Icon(Icons.call),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pickupAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          destinationAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                widget.onComplete(snapshot.data!.reference),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Complete ride'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CarrierEarnings extends StatelessWidget{
  final User user;const CarrierEarnings({super.key,required this.user});
  num n(dynamic v)=>v is num?v:num.tryParse((v??'').toString())??0;
  @override Widget build(BuildContext c)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('autoRideRequests').where('driverUid',isEqualTo:user.uid).snapshots(),
    builder:(context,s){num earned=0;int done=0;num ratingSum=0;int ratings=0;for(final d in s.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[]){final x=d.data();final st=(x['status']??'').toString().toLowerCase();if(st=='completed'){done++;earned+=n(x['driverEarning']??x['partnerEarning']);}final r=x['rating'];if(r is num){ratingSum+=r;ratings++;}}final avg=ratings==0?0:ratingSum/ratings;
      return ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[const Text('Earnings & Ratings',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),Row(children:[Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.currency_rupee,color:purple),const SizedBox(height:8),Text('₹'+earned.toStringAsFixed(0),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const Text('Recorded earnings',style:TextStyle(color:Colors.grey))])))),const SizedBox(width:10),Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.star,color:Colors.amber),const SizedBox(height:8),Text(avg.toStringAsFixed(1),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),Text(ratings==0?'No ratings yet':ratings.toString()+' ratings',style:const TextStyle(color:Colors.grey))]))))]),const SizedBox(height:12),Card(child:ListTile(leading:const Icon(Icons.check_circle,color:Colors.green),title:Text(done.toString(),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),subtitle:const Text('Completed rides')))]);
    },
  );
}


class CarrierVehiclePage extends StatefulWidget{
  final User user;
  const CarrierVehiclePage({super.key,required this.user});
  @override State<CarrierVehiclePage> createState()=>_CarrierVehiclePageState();
}
class _CarrierVehiclePageState extends State<CarrierVehiclePage>{
  final categories=['Motorcycle','Scooter','E-bike','Auto Rickshaw','E-Rickshaw','Hatchback','Sedan','SUV','MUV','Luxury Car','Taxi / Cab','Tempo Traveller','Van','Mini Bus','Bus','Pickup Truck','Mini Truck','Bolero Pickup','Goods Auto','Cargo Van','Tractor','Tractor Trolley','Trailer','Ambulance','Other'];
  Future<void> _listVehicle()async{
    final category=ValueNotifier('Motorcycle');final price=TextEditingController();final capacity=TextEditingController();final phone=TextEditingController();final city=TextEditingController();final pincode=TextEditingController();bool negotiate=true;
    try{
      final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(
        title:const Text('List your vehicle'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          ValueListenableBuilder<String>(valueListenable:category,builder:(_,v,__)=>DropdownButtonFormField<String>(initialValue:v,decoration:const InputDecoration(labelText:'Vehicle category'),items:categories.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)category.value=x;})),
          TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Contact number')),
          TextField(controller:city,decoration:const InputDecoration(labelText:'City / town')),
          TextField(controller:pincode,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Pincode')),
          TextField(controller:capacity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Seats / capacity')),
          TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Price (₹)')),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Allow negotiation'),value:negotiate,onChanged:(v)=>setD(()=>negotiate=v)),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Publish'))],
      )));
      if(ok!=true)return;
      final cleanPhone=phone.text.replaceAll(RegExp(r'\D'),'');
      final cleanPrice=num.tryParse(price.text.trim())??0;
      if(cleanPhone.length!=10||cleanPrice<=0||pincode.text.trim().isEmpty){if(!mounted)return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid phone, pincode and price.')));return;}
      await FirebaseFirestore.instance.collection('vehicles').add({
        'ownerUid':widget.user.uid,'ownerName':widget.user.displayName??'ALLways Carrier','ownerPhone':cleanPhone,
        'category':category.value,'vehicleType':category.value,'price':cleanPrice,'capacity':num.tryParse(capacity.text.trim())??0,
        'allowNegotiation':negotiate,'status':'available','listingStatus':'active','available':true,
        'manual_location':{'villageTownCity':city.text.trim(),'pincode':pincode.text.trim()},
        'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp(),
      });
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Vehicle listed successfully.')));
    }finally{category.dispose();price.dispose();capacity.dispose();phone.dispose();city.dispose();pincode.dispose();}
  }
  Future<void> _updateBooking(DocumentReference ref,String status)async{
    try{
      await ref.update({'status':status,'updatedAt':FieldValue.serverTimestamp()});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Booking $status.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update booking: '+e.toString())));}
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[
    const Text('Vehicle',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
    const SizedBox(height:6),
    const Text('Offer your vehicle and manage customer booking requests from one place.',style:TextStyle(color:Colors.grey)),
    const SizedBox(height:14),
    Card(child:ListTile(leading:const Icon(Icons.add_business_outlined,color:purple),title:const Text('Offer your vehicle',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('List your vehicle, set your own price and receive booking requests.'),trailing:const Icon(Icons.chevron_right),onTap:_listVehicle)),
    const SizedBox(height:12),
    const Text('My vehicle listings',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
    const SizedBox(height:8),
    StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('vehicles').where('ownerUid',isEqualTo:widget.user.uid).snapshots(),
      builder:(c,snap){
        if(snap.hasError){
          return Card(child:ListTile(
            leading:const Icon(Icons.error_outline,color:Colors.red),
            title:const Text('Could not load vehicle listings.'),
            subtitle:Text(snap.error.toString()),
          ));
        }
        final docs=snap.data?.docs??[];
        if(docs.isEmpty){
          return const Card(child:ListTile(
            title:Text('No vehicle listed yet.'),
            subtitle:Text('Use “Offer your vehicle” to publish one.'),
          ));
        }
        return Column(
          children:docs.map((d){
            final x=d.data();
            final listingStatus=(x['status']??x['listingStatus']??'').toString().toLowerCase();
            final available=(x['available']==false)?false:const {'available','active','published','listed'}.contains(listingStatus);
            return Card(
              child:ListTile(
                leading:const Icon(Icons.directions_car_outlined),
                title:Text((x['category']??'Vehicle').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Text('₹'+(x['price']??0).toString()+' • '+(x['status']??'').toString()),
                trailing:Switch(
                  value:available,
                  onChanged:(v)=>d.reference.update({'status':v?'available':'paused','listingStatus':v?'active':'paused','available':v,'updatedAt':FieldValue.serverTimestamp()}),
                ),
              ),
            );
          }).toList(),
        );
      },
    ),
    const SizedBox(height:14),
    const Text('Booking requests',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
    const SizedBox(height:8),
    StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('vehicleBookings').where('ownerUid',isEqualTo:widget.user.uid).snapshots(),
      builder:(c,snap){
        final docs=snap.data?.docs??[];
        if(docs.isEmpty)return const Card(child:ListTile(title:Text('No booking requests yet.')));
        return Column(
          children:docs.map((d){
            final x=d.data();
            final status=(x['status']??'Booked').toString();
            final pending=!['accepted','rejected','cancelled','delivered'].contains(status.toLowerCase());
            return Card(
              child:ListTile(
                title:Text((x['customerName']??'Customer').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Text(status+' • '+(x['category']??'Vehicle').toString()+' • ₹'+(x['listedPrice']??0).toString()),
                trailing:pending
                  ? Row(mainAxisSize:MainAxisSize.min,children:[
                      TextButton(onPressed:()=>_updateBooking(d.reference,'Rejected'),child:const Text('Reject')),
                      FilledButton(onPressed:()=>_updateBooking(d.reference,'Accepted'),child:const Text('Accept')),
                    ])
                  : Text(status),
              ),
            );
          }).toList(),
        );
      },
    ),
  ]);
}

class CarrierProfile extends StatelessWidget{
  final User user;final String vehicle;final Future<void> Function() onVehicle;final Future<void> Function() onSos;
  const CarrierProfile({super.key,required this.user,required this.vehicle,required this.onVehicle,required this.onSos});
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[
    const Text('Carrier Profile',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),
    Card(child:ListTile(leading:const Icon(Icons.person_outline,color:purple),title:Text(user.displayName??'ALLways Carrier'),subtitle:Text(user.email??''))),
    Card(child:ListTile(leading:const Icon(Icons.two_wheeler,color:purple),title:const Text('Vehicle & Documents'),subtitle:Text('Vehicle type: '+vehicle),trailing:const Icon(Icons.chevron_right),onTap:onVehicle)),
    const Card(child:ListTile(leading:Icon(Icons.description_outlined),title:Text('Verification'),subtitle:Text('Keep identity and vehicle documents current.'))),
    Card(child:ListTile(leading:const Icon(Icons.sos,color:Colors.red),title:const Text('SOS / Emergency'),onTap:onSos)),
    const Card(child:ListTile(leading:Icon(Icons.help_outline),title:Text('Help & Support'),subtitle:Text('Contact ALLways operations for ride issues.'))),
    Card(child:ListTile(leading:const Icon(Icons.logout),title:const Text('Sign out'),onTap:()=>FirebaseAuth.instance.signOut())),
  ]);
}
