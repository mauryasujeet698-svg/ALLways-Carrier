import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';
import 'support_screen.dart';

const driverTeal=Color(0xFF0B6E69);
const ivory=Color(0xFFF8F6F0);
const _mapboxPublicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');
const _mapboxTilesUrl = 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token=' + _mapboxPublicToken;
@pragma('vm:entry-point')
Future<void> _background(RemoteMessage message) async { await Firebase.initializeApp(); }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Email/password sign-in must remain available if Google Sign-In setup fails.
  try {
    await GoogleSignIn.instance.initialize();
  } catch (_) {}
  FirebaseMessaging.onBackgroundMessage(_background);
  runApp(const AllwaysDriverPartnerApp());
}

class AllwaysDriverPartnerApp extends StatelessWidget {
  const AllwaysDriverPartnerApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'ALLways Driver Partner',
    theme:ThemeData(
      useMaterial3:true,
      colorScheme:ColorScheme.fromSeed(seedColor:driverTeal),
      scaffoldBackgroundColor:ivory,
      textTheme:GoogleFonts.poppinsTextTheme(),
      cardTheme:const CardThemeData(color:Colors.white,elevation:0,margin:EdgeInsets.zero),
    ),
    home:const AllwaysUpdateGate(repo:'mauryasujeet698-svg/ALLways-Carrier',packageChannel:'com.allways.carrier/apk_installer',assetName:'allways-driver-partner-latest.apk',child:AuthGate()),
  );
}

class AuthGate extends StatelessWidget{
 const AuthGate({super.key});
 @override Widget build(BuildContext context)=>StreamBuilder<User?>(stream:FirebaseAuth.instance.authStateChanges(),builder:(context,s){
  if(s.data==null)return const DriverPartnerLoginPage();
  return FutureBuilder<DocumentSnapshot<Map<String,dynamic>>>(future:FirebaseFirestore.instance.collection('ridePartners').doc(s.data!.uid).get(),builder:(context,a){
   if(!a.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));
   if(!a.data!.exists)return PartnerRegistrationPage(user:s.data!);
   final p=a.data!.data()??{};final approval=(p['approvalStatus']??'').toString().toLowerCase();
   if(approval=='pending')return PendingApprovalPage(user:s.data!,rejected:false);
   if(approval=='rejected')return PendingApprovalPage(user:s.data!,rejected:true,reason:(p['rejectionReason']??'').toString());
   return DriverPartnerShell(user:s.data!);
  });
 });
}

class DriverPartnerLoginPage extends StatefulWidget {
  final String? message;
  const DriverPartnerLoginPage({super.key,this.message});
  @override State<DriverPartnerLoginPage> createState()=>_DriverPartnerLoginPageState();
}
class _DriverPartnerLoginPageState extends State<DriverPartnerLoginPage>{
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
        const CircleAvatar(radius:30,backgroundColor:Color(0x1A5B1ACF),child:Icon(Icons.two_wheeler,color:driverTeal,size:34)),
        const SizedBox(height:18),const Text('ALLways Driver Partner',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),const Text('Driver Partner workspace'),
        if(widget.message!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(widget.message!,style:const TextStyle(color:Colors.red))),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(error!,style:const TextStyle(color:Colors.red))),
        const SizedBox(height:20),
        TextField(controller:email,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.email_outlined))),
        const SizedBox(height:12),
        TextField(controller:password,obscureText:obscure,decoration:InputDecoration(labelText:'Password',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility_outlined:Icons.visibility_off_outlined)))),
        const SizedBox(height:18),
        SizedBox(width:double.infinity,height:52,child:FilledButton(onPressed:busy?null:login,style:FilledButton.styleFrom(backgroundColor:driverTeal),child:busy?const CircularProgressIndicator(color:Colors.white):const Text('Sign in'))),
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
              style: FilledButton.styleFrom(backgroundColor: driverTeal),
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
                    color: rejected ? Colors.red : driverTeal,
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

class DriverPartnerShell extends StatefulWidget{
  final User user;const DriverPartnerShell({super.key,required this.user});
  @override State<DriverPartnerShell> createState()=>_DriverPartnerShellState();
}
class _DriverPartnerShellState extends State<DriverPartnerShell>{
  int tab=0;bool online=false;Position? position;String vehicle='bike';String? activeRideId;double matchingRadiusKm=7;bool _acceptingRide=false;
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
      try{final rs=await FirebaseFirestore.instance.collection('settings').doc('ride').get();final v=double.tryParse((rs.data()?['matchingRadiusKm']??'7').toString())??7;if(v>0&&v<=50)matchingRadiusKm=v;}catch(_){}
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
      if(s.authorizationStatus==AuthorizationStatus.denied){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Notifications are blocked by Android. Enable ALLways notifications in system settings, then reopen this app.')));
        return;
      }
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
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.alert);
        try {
          const MethodChannel('allways_notifications').invokeMethod('showNotification', {
            'title': message.notification?.title ?? message.data['title'] ?? 'ALLways',
            'body': message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? 'You have a new ALLways update.',
          });
        } catch (_) {}
        final title=message.notification?.title??message.data['title']??'ALLways';
        final body=message.notification?.body??message.data['body']??'';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(body.isEmpty?title:'$title: $body'),
          duration:const Duration(seconds:4),
        ));
      });
      Future<void> openRideFromMessage(RemoteMessage message) async {
        final rideId=(message.data['rideId']??message.data['id']??'').toString().trim();
        if(rideId.isEmpty)return;
        final ride=await FirebaseFirestore.instance.collection('autoRideRequests').doc(rideId).get();
        if(!ride.exists)return;
        final data=ride.data()??{};
        final status=(data['status']??'').toString().toLowerCase();
        if(const {'cancelled','completed','rejected','expired'}.contains(status))return;
        final assigned=(data['driverUid']??'').toString()==widget.user.uid;
        if(mounted&&assigned){setState((){activeRideId=rideId;tab=2;});return;}
        if(mounted&&status=='searching'&&(data['driverUid']??'').toString().isEmpty){setState(()=>tab=1);}
      }
      FirebaseMessaging.onMessageOpenedApp.listen(openRideFromMessage);
      final initialMessage=await FirebaseMessaging.instance.getInitialMessage();
      if(initialMessage!=null)await openRideFromMessage(initialMessage);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Notification setup failed: ${e.toString()}')));
    }
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
    if(_acceptingRide)return;
    setState(()=>_acceptingRide=true);
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
        tx.update(doc.reference,{'status':'accepted','driverUid':widget.user.uid,'driverName':profile['name']??widget.user.displayName??'ALLways Driver Partner','driverPhone':profile['phone']??profile['mobileNumber']??widget.user.phoneNumber??'','driverVehicleType':normalized,'acceptedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
        tx.set(p.reference,{'status':'on_trip','availableForRides':false,'activeRideId':doc.id,'statusUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      });
      if(mounted){setState(()=>activeRideId=doc.id);setState(()=>tab=2);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride accepted. Opening live tracking.')));}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}
    finally{if(mounted)setState(()=>_acceptingRide=false);}
  }
  Future<void> _startRide(DocumentReference ref) async {
    final pinController=TextEditingController();
    try{
      final pin=await showDialog<String>(
        context:context,
        builder:(dialogContext)=>AlertDialog(
          title:const Text('Passenger confirmation'),
          content:TextField(controller:pinController,autofocus:true,keyboardType:TextInputType.number,maxLength:4,inputFormatters:[FilteringTextInputFormatter.digitsOnly],decoration:const InputDecoration(labelText:'4-digit confirmation number',hintText:'Enter passenger PIN')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),
            FilledButton(onPressed:()=>Navigator.pop(dialogContext,pinController.text.trim()),child:const Text('Start ride')),
          ],
        ),
      );
      if(pin==null||pin.length!=4)return;
      final callable=FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable(
        'verifyConfirmationPin',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      final result=await callable.call({'type':'ride','id':ref.id,'pin':pin});
      final payload=result.data;
      // Current deployed callable returns {ok:true, rideId}; accept the legacy
      // verified flag too so client and backend response contracts stay compatible.
      if(payload is! Map || (payload['ok']!=true && payload['verified']!=true)) {
        throw FirebaseFunctionsException(code:'failed-precondition',message:'The server did not confirm this PIN. Please try again.');
      }
      if(mounted){
        setState(()=>activeRideId=ref.id);
        _watchActiveRide();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('PIN verified securely. Ride started.')));
      }
    }on FirebaseFunctionsException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message??'Could not verify the confirmation number.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));
    }finally{pinController.dispose();}
  }

  Future<void> _complete(DocumentReference ref)async{
    try{
      final callable=FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('completeRide');
      await callable.call({'rideId':ref.id});
      if(mounted){setState(()=>activeRideId=null);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride completed.')));}
    }on FirebaseFunctionsException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.message??'Could not complete ride.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  }
  Future<void> _call(String phone)async{final p=phone.replaceAll(RegExp(r'[^0-9+]'),'');if(p.isNotEmpty)await launchUrl(Uri(scheme:'tel',path:p),mode:LaunchMode.externalApplication);}
  Future<void> _sos()async{await FirebaseFirestore.instance.collection('sosAlerts').add({'uid':widget.user.uid,'role':'carrier','createdAt':FieldValue.serverTimestamp(),'status':'open'});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('SOS alert sent to ALLways operations.')));}
  Future<void> _vehicleDialog()async{
    if (activeRideId != null || online) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Go offline and complete any active ride before switching vehicle type.')));
      return;
    }
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
    await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({
      'vehicleType': selected,
      'vehicleTypeUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge:true));
    if(mounted){
      setState(()=>vehicle=selected);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vehicle switched to ${selected[0].toUpperCase()}${selected.substring(1)}.')));
    }
  }
  @override Widget build(BuildContext context){
    final pages=[
      DriverPartnerHome(online:online,position:position,activeRideId:activeRideId,onOnline:_setOnline),
      RideRequests(user:widget.user,online:online,position:position,vehicle:vehicle,activeRideId:activeRideId,matchingRadiusKm:matchingRadiusKm,onAccept:_accept,onReject:_reject),
      ActiveRide(rideId:activeRideId,position:position,onCall:_call,onStart:_startRide,onComplete:_complete),
      DriverPartnerEarnings(user:widget.user),
      DriverPartnerProfile(user:widget.user,vehicle:vehicle,onVehicle:_vehicleDialog,onSos:_sos,onSupport:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DriverPartnerSupportScreen(user:widget.user))),onHistory:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>DriverPartnerRideHistory(user:widget.user))),onNotifications:_notifications,),
      DriverPartnerVehiclePage(user:widget.user,onRideVehicle:_vehicleDialog),
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

class DriverPartnerHome extends StatelessWidget {
  final bool online;
  final Position? position;
  final String? activeRideId;
  final Future<void> Function(bool) onOnline;

  const DriverPartnerHome({
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
            leading: const Icon(Icons.navigation, color: driverTeal),
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
      bottomItems.insert(0,Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const CircleAvatar(backgroundColor:Color(0x1A5B1ACF),child:Icon(Icons.bolt,color:driverTeal)),const SizedBox(width:10),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Next action',style:TextStyle(fontWeight:FontWeight.w900)),Text('Open Requests → Accept → Navigate → Complete',style:TextStyle(color:Colors.grey,fontSize:12))]))]))));
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
                urlTemplate: _mapboxTilesUrl,
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
                          color: driverTeal,
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
                        child: Icon(Icons.two_wheeler, color: driverTeal),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ALLways Driver Partner',
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
              urlTemplate: _mapboxTilesUrl,
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
                        color: driverTeal,
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
                      child: Icon(Icons.two_wheeler, color: driverTeal),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ALLways Driver Partner',
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
  final Future<void> Function(QueryDocumentSnapshot<Map<String,dynamic>>) onAccept;final Future<void> Function(DocumentReference) onReject;final double matchingRadiusKm;
  const RideRequests({super.key,required this.user,required this.online,required this.position,required this.vehicle,required this.activeRideId,required this.matchingRadiusKm,required this.onAccept,required this.onReject});
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
        if(x['customerActive']==false)continue;
        if(x['cancelledAt']!=null||x['completedAt']!=null||x['endedAt']!=null||x['rejectedAt']!=null||x['expiredAt']!=null)continue;
        final assignedUid=(x['driverUid']??x['carrierUid']??x['deliveryPartnerUid']??x['assignedPartnerId']??'').toString().trim();
        if(assignedUid.isNotEmpty)continue;
        final rejected=x['rejectedBy'] is List?List.from(x['rejectedBy']):<dynamic>[];
        if(rejected.contains(user.uid))continue;
        final type=(x['rideType']??'bike').toString().toLowerCase();if(type!=vehicle)continue;
        final lat=n(x['pickupLatitude']??x['pickupLat']);final lng=n(x['pickupLongitude']??x['pickupLng']);if(lat==0||lng==0)continue;
        if(Geolocator.distanceBetween(position!.latitude,position!.longitude,lat,lng)<=matchingRadiusKm*1000)list.add(d);
      }
      if(list.isEmpty)return Center(child:Padding(padding:const EdgeInsets.all(28),child:Text('No ride requests within '+matchingRadiusKm.toStringAsFixed(0)+' km right now.',textAlign:TextAlign.center)));
      return ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[
        const Text('Ride Requests',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),
        ...list.map((d){final x=d.data();final lat=n(x['pickupLatitude']??x['pickupLat']);final lng=n(x['pickupLongitude']??x['pickupLng']);final km=Geolocator.distanceBetween(position!.latitude,position!.longitude,lat,lng)/1000;
          return Card(margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[CircleAvatar(backgroundColor:driverTeal.withOpacity(.1),child:Icon((x['rideType']??'bike').toString()=='auto'?Icons.local_taxi_outlined:Icons.two_wheeler,color:driverTeal)),const SizedBox(width:10),Expanded(child:Text((x['rideType']??'bike').toString().toUpperCase()+' RIDE',style:const TextStyle(fontWeight:FontWeight.w900))),Text(km.toStringAsFixed(1)+' km',style:const TextStyle(color:driverTeal,fontWeight:FontWeight.w800))]),
            const SizedBox(height:10),Text((x['pickupAddress']??x['address']??'Pickup location').toString(),maxLines:2,overflow:TextOverflow.ellipsis),Text((x['destinationAddress']??x['destination']??'Destination').toString(),style:const TextStyle(color:Colors.grey),maxLines:2,overflow:TextOverflow.ellipsis),const SizedBox(height:8),
            Text('₹'+n(x['estimatedFare']??x['fare']??x['total']).toStringAsFixed(0),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
            const SizedBox(height:10),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>onReject(d.reference),child:const Text('Reject'))),const SizedBox(width:8),Expanded(child:FilledButton(onPressed:()=>onAccept(d),style:FilledButton.styleFrom(backgroundColor:driverTeal),child:const Text('Accept')))]),
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
  final Future<void> Function(DocumentReference) onStart;
  final Future<void> Function(DocumentReference) onComplete;

  const ActiveRide({
    super.key,
    required this.rideId,
    required this.position,
    required this.onCall,
    required this.onStart,
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
  LatLng? lastRouteStart;
  LatLng? lastRouteTarget;
  List<Map<String,dynamic>> navSteps = [];
  int activeStep = 0;
  String? cameraKey;
  double number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  LatLng? point(dynamic latitude, dynamic longitude) {
    final lat = number(latitude);
    final lng = number(longitude);
    if (lat == 0 || lng == 0 || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  Future<void> _openGoogleMaps(LatLng? target, String label) async {
    if (target == null || target.latitude < -90 || target.latitude > 90 ||
        target.longitude < -180 || target.longitude > 180) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label coordinates are not available yet.')),
      );
      return;
    }
    final appUri = Uri.parse('google.navigation:q=${target.latitude},${target.longitude}&mode=d');
    final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}&travelmode=driving');
    try {
      final opened = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!opened) {
        final fallback = await launchUrl(webUri, mode: LaunchMode.externalApplication);
        if (!fallback && mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open navigation. Please check your maps app or browser.')),
        );
      }
    } catch (_) {
      try {
        final fallback = await launchUrl(webUri, mode: LaunchMode.externalApplication);
        if (!fallback && mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open navigation. Please check your maps app or browser.')),
        );
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigation is unavailable on this device.')),
        );
      }
    }
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
        final customer = point(data['customerLat'], data['customerLng']);
        final status = (data['status'] ?? 'accepted').toString().toLowerCase();
        final navigationTarget = status == 'started' ? (destination ?? customer) : (customer ?? pickup);
        final lastDriver = lastRouteStart;
        final lastTarget = lastRouteTarget;
        final shouldRoute = driver != null && navigationTarget != null && !routeLoading &&
            (lastDriver == null || lastTarget == null ||
             Distance().as(LengthUnit.Meter, lastDriver, driver) >= 100 ||
             Distance().as(LengthUnit.Meter, lastTarget, navigationTarget) >= 75 ||
             route.isEmpty);
        if (shouldRoute) {
          routeLoading = true;
          loadRoute(driver, navigationTarget).whenComplete(() {
            if (mounted) setState(() => routeLoading = false);
          });
          lastRouteStart = driver;
          lastRouteTarget = navigationTarget;
        }

        final center = driver ?? pickup ?? destination ?? const LatLng(25.4358, 81.8463);
        final cameraTarget = navigationTarget ?? pickup ?? destination;
        if(mapReady && cameraTarget != null){
          final key='${cameraTarget.latitude.toStringAsFixed(5)},${cameraTarget.longitude.toStringAsFixed(5)}:$status';
          if(cameraKey!=key){
            cameraKey=key;
            final from=driver ?? pickup ?? destination ?? center;
            final meters=Geolocator.distanceBetween(from.latitude,from.longitude,cameraTarget.latitude,cameraTarget.longitude);
            final zoom=meters<1000?15.0:meters<3000?14.0:meters<7000?12.8:meters<15000?11.8:meters<30000?10.8:9.8;
            WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)mapController.move(LatLng((from.latitude+cameraTarget.latitude)/2,(from.longitude+cameraTarget.longitude)/2),zoom);});
          }
        }

        final markers = <Marker>[
          if (driver != null)
            Marker(
              point: driver,
              width: 62,
              height: 62,
              child: const Pin(color: driverTeal, icon: Icons.two_wheeler),
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
        final pickupAddress =
            (data['pickupAddress'] ?? 'Pickup').toString();
        final destinationAddress =
            (data['destinationAddress'] ?? 'Destination').toString();
        final locationUpdatedAt=data['customerLocationUpdatedAt'] ?? data['customerLocationUpdatedAt'];
        final customerLocationFresh=locationUpdatedAt is Timestamp ? DateTime.now().difference(locationUpdatedAt.toDate()).inSeconds <= 60 : false;

        return Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.5,
                onMapReady: (){mapReady=true;},
              ),
              children: [
                TileLayer(
                  urlTemplate: _mapboxTilesUrl,
                  maxZoom: 19,
                  userAgentPackageName: 'com.allways.carrier',
                ),
                if (route.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        color: driverTeal,
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
                                (customerLocationFresh ? 'Live • ' : 'Location may be stale • ') + status + (customer != null && driver != null ? ' • Customer ' + (Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude) < 1000 ? Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude).round().toString() + ' m away' : (Geolocator.distanceBetween(driver.latitude, driver.longitude, customer.latitude, customer.longitude) / 1000).toStringAsFixed(1) + ' km away') : ''),
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
                          child: OutlinedButton.icon(
                            onPressed: status.toLowerCase() == 'started'
                                ? (destination == null ? null : () => _openGoogleMaps(destination, 'Destination'))
                                : (pickup == null ? null : () => _openGoogleMaps(pickup, 'Pickup')),
                            icon: const Icon(Icons.directions),
                            label: Text(status.toLowerCase() == 'started'
                                ? 'Navigate to Destination'
                                : 'Track Customer / Navigate to Pickup'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: status.toLowerCase() == 'started'
                                ? () => widget.onComplete(snapshot.data!.reference)
                                : () => widget.onStart(snapshot.data!.reference),
                            style: FilledButton.styleFrom(
                              backgroundColor: status.toLowerCase() == 'started' ? Colors.green : driverTeal,
                            ),
                            child: Text(status.toLowerCase() == 'started' ? 'Complete ride' : 'Start ride'),
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

class DriverPartnerEarnings extends StatelessWidget{
  final User user;const DriverPartnerEarnings({super.key,required this.user});
  num n(dynamic v)=>v is num?v:num.tryParse((v??'').toString())??0;
  @override Widget build(BuildContext c)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('autoRideRequests').where('driverUid',isEqualTo:user.uid).snapshots(),
    builder:(context,s){num earned=0;int done=0;num ratingSum=0;int ratings=0;for(final d in s.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[]){final x=d.data();final st=(x['status']??'').toString().toLowerCase();if(st=='completed'){done++;earned+=n(x['driverEarning']??x['partnerEarning']);}final r=x['rating'];if(r is num){ratingSum+=r;ratings++;}}final avg=ratings==0?0:ratingSum/ratings;
      return ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[const Text('Earnings & Ratings',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),Row(children:[Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.currency_rupee,color:driverTeal),const SizedBox(height:8),Text('₹'+earned.toStringAsFixed(0),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const Text('Recorded earnings',style:TextStyle(color:Colors.grey))])))),const SizedBox(width:10),Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.star,color:Colors.amber),const SizedBox(height:8),Text(avg.toStringAsFixed(1),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),Text(ratings==0?'No ratings yet':ratings.toString()+' ratings',style:const TextStyle(color:Colors.grey))]))))]),const SizedBox(height:12),Card(child:ListTile(leading:const Icon(Icons.check_circle,color:Colors.green),title:Text(done.toString(),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),subtitle:const Text('Completed rides')))]);
    },
  );
}


class DriverPartnerVehiclePage extends StatefulWidget{
  final User user;
  final Future<void> Function() onRideVehicle;
  const DriverPartnerVehiclePage({super.key,required this.user,required this.onRideVehicle});
  @override State<DriverPartnerVehiclePage> createState()=>_DriverPartnerVehiclePageState();
}
class _DriverPartnerVehiclePageState extends State<DriverPartnerVehiclePage>{
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
        'ownerUid':widget.user.uid,'ownerName':widget.user.displayName??'ALLways Driver Partner','ownerPhone':cleanPhone,
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
    Card(child:ListTile(
      leading:const Icon(Icons.event_available_outlined,color:driverTeal),
      title:const Text('List your vehicle for bookings',style:TextStyle(fontWeight:FontWeight.w900)),
      subtitle:const Text('Publish your vehicle so customers can book it.'),
      trailing:const Icon(Icons.chevron_right),
      onTap:_listVehicle,
    )),
    const SizedBox(height:8),
    Card(child:ListTile(
      leading:const Icon(Icons.two_wheeler,color:driverTeal),
      title:const Text('Your vehicle for riding',style:TextStyle(fontWeight:FontWeight.w900)),
      subtitle:const Text('Set the vehicle you use to accept ALLways rides.'),
      trailing:const Icon(Icons.chevron_right),
      onTap:widget.onRideVehicle,
    )),
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
            subtitle:Text('Use “List your vehicle for bookings” to publish one.'),
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

Future<void> _chooseAllwaysLanguage(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getString('app_language') ?? 'English';
  if (!context.mounted) return;
  final selected = await showDialog<String>(
    context: context,
    builder: (d) => SimpleDialog(
      title: const Text('Language'),
      children: [
        RadioListTile<String>(value: 'English', groupValue: current, title: const Text('English'), onChanged: (v) => Navigator.pop(d, v)),
        RadioListTile<String>(value: 'Hindi', groupValue: current, title: const Text('हिन्दी'), onChanged: (v) => Navigator.pop(d, v)),
      ],
    ),
  );
  if (selected != null) {
    await prefs.setString('app_language', selected);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Language set to $selected.')),
    );
  }
}

class DriverPartnerProfile extends StatelessWidget{
  final User user;final String vehicle;final Future<void> Function() onVehicle;final Future<void> Function() onSos;final VoidCallback onSupport;final VoidCallback onHistory;final Future<void> Function() onNotifications;
  const DriverPartnerProfile({super.key,required this.user,required this.vehicle,required this.onVehicle,required this.onSos,required this.onSupport,required this.onHistory,required this.onNotifications});
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.fromLTRB(16,18,16,28),children:[
    const Text('Driver Partner Profile',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:12),
    Card(child:ListTile(leading:const Icon(Icons.person_outline,color:driverTeal),title:Text(user.displayName??'ALLways Driver Partner'),subtitle:Text(user.email??''))),
    Card(child:ListTile(leading:const Icon(Icons.history,color:driverTeal),title:const Text('Ride History'),subtitle:const Text('Completed and terminal rides from the last 7 calendar days.'),trailing:const Icon(Icons.chevron_right),onTap:onHistory)),
    Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined,color:driverTeal),title:const Text('Notifications & alerts'),subtitle:const Text('Retry notification permission and token registration.'),trailing:const Icon(Icons.refresh),onTap:onNotifications)),
    Card(child:ListTile(leading:const Icon(Icons.two_wheeler,color:driverTeal),title:const Text('Vehicle & Documents'),subtitle:Text('Vehicle type: '+vehicle),trailing:const Icon(Icons.chevron_right),onTap:onVehicle)),
    Card(child:ListTile(leading:const Icon(Icons.language,color:driverTeal),title:const Text('Language'),subtitle:const Text('English / हिन्दी'),trailing:const Icon(Icons.chevron_right),onTap:()=>_chooseAllwaysLanguage(c))),
    const Card(child:ListTile(leading:Icon(Icons.description_outlined),title:Text('Verification'),subtitle:Text('Keep identity and vehicle documents current.'))),
    Card(child:ListTile(leading:const Icon(Icons.sos,color:Colors.red),title:const Text('SOS / Emergency'),onTap:onSos)),
    Card(child:ListTile(leading:const Icon(Icons.help_outline),title:const Text('Help & Support'),subtitle:const Text('Contact ALLways operations for ride issues.'),trailing:const Icon(Icons.chevron_right),onTap:onSupport)),
    Card(child:ListTile(leading:const Icon(Icons.logout),title:const Text('Sign out'),onTap:()=>FirebaseAuth.instance.signOut())),
  ]);
}

class DriverPartnerRideHistory extends StatelessWidget{
  final User user; const DriverPartnerRideHistory({super.key,required this.user});
  static const Duration _indiaOffset=Duration(hours:5,minutes:30);
  DateTime? _date(dynamic value){
    if(value is Timestamp)return value.toDate();
    if(value is DateTime)return value;
    if(value is num){final n=value.toInt();return DateTime.fromMillisecondsSinceEpoch(n<100000000000?n*1000:n);}
    if(value is String)return DateTime.tryParse(value);
    return null;
  }
  DateTime? _event(Map<String,dynamic> x)=>_date(x['completedAt'])??_date(x['cancelledAt'])??_date(x['rejectedAt'])??_date(x['expiredAt'])??_date(x['updatedAt'])??_date(x['createdAt'])??_date(x['requestedAt']);
  bool _recent(Map<String,dynamic> x){
    final at=_event(x);if(at==null)return false;
    final indiaNow=DateTime.now().toUtc().add(_indiaOffset);
    final today=DateTime.utc(indiaNow.year,indiaNow.month,indiaNow.day);
    final shifted=at.toUtc().add(_indiaOffset);
    final day=DateTime.utc(shifted.year,shifted.month,shifted.day);
    final start=today.subtract(const Duration(days:6));
    return !day.isBefore(start)&&day.isBefore(today.add(const Duration(days:1)));
  }
  String _when(DateTime? date){if(date==null)return 'Time unavailable';final i=date.toUtc().add(_indiaOffset);return '${i.day.toString().padLeft(2,'0')}/${i.month.toString().padLeft(2,'0')}/${i.year} ${i.hour.toString().padLeft(2,'0')}:${i.minute.toString().padLeft(2,'0')} IST';}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Ride History')),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('autoRideRequests').where('driverUid',isEqualTo:user.uid).snapshots(),
      builder:(c,s){
        if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(20),child:Text('Could not load ride history: ${s.error}')));
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        const terminal={'completed','cancelled','canceled','rejected','expired','failed'};
        final docs=s.data!.docs.where((d)=>terminal.contains((d.data()['status']??'').toString().toLowerCase())&&_recent(d.data())).toList();
        docs.sort((a,b)=>(_event(b.data())??DateTime.fromMillisecondsSinceEpoch(0)).compareTo(_event(a.data())??DateTime.fromMillisecondsSinceEpoch(0)));
        if(docs.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('No ride history for today or the preceding six calendar days.',textAlign:TextAlign.center)));
        return ListView.builder(padding:const EdgeInsets.all(16),itemCount:docs.length,itemBuilder:(_,i){
          final d=docs[i];final x=d.data();final status=(x['status']??'Unknown').toString();
          final fare=x['carrierEarning']??x['estimatedFare']??x['fare'];
          final distance=x['distanceKm']??x['distance']??x['estimatedDistanceKm'];
          return Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[Expanded(child:Text('Ride #${x['id']??d.id}',style:const TextStyle(fontWeight:FontWeight.w900))),Text(status,style:TextStyle(fontWeight:FontWeight.w800,color:status.toLowerCase()=='completed'?Colors.green:Colors.blueGrey))]),
            const SizedBox(height:6),
            Text(_when(_event(x)),style:const TextStyle(color:Colors.grey,fontSize:12)),
            const SizedBox(height:6),
            Text('Pickup: ${x['pickupAddress']??x['address']??'Unavailable'}'),
            Text('Destination: ${x['destinationAddress']??x['destination']??'Unavailable'}'),
            if(distance!=null)Text('Distance: $distance km'),
            if(fare!=null)Text('Fare / earnings: ₹$fare',style:const TextStyle(fontWeight:FontWeight.w800)),
          ])));
        });
      }
    )
  );
}
