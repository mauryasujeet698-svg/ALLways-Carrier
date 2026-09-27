import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  Future<bool> _allowed(User u) async {
    final r=await FirebaseFirestore.instance.collection('ridePartners').doc(u.uid).get();
    if(r.exists)return true;
    final c=await FirebaseFirestore.instance.collection('customers').doc(u.uid).get();
    final role=(c.data()?['role']??'').toString().toLowerCase();
    return role=='carrier'||role=='rider';
  }
  @override Widget build(BuildContext context)=>StreamBuilder<User?>(
    stream:FirebaseAuth.instance.authStateChanges(),
    builder:(context,s){
      if(s.data==null)return const CarrierLoginPage();
      return FutureBuilder<bool>(
        future:_allowed(s.data!),
        builder:(context,a){
          if(!a.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));
          if(a.data!=true){FirebaseAuth.instance.signOut();return const CarrierLoginPage(message:'This account is not a Carrier.');}
          return CarrierShell(user:s.data!);
        },
      );
    },
  );
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
      ])),
    ))))),
  );
}

class CarrierShell extends StatefulWidget{
  final User user;const CarrierShell({super.key,required this.user});
  @override State<CarrierShell> createState()=>_CarrierShellState();
}
class _CarrierShellState extends State<CarrierShell>{
  int tab=0;bool online=false;Position? position;String vehicle='bike';String? activeRideId;
  StreamSubscription<Position>? locationSub;
  @override void initState(){super.initState();_load();_notifications();}
  @override void dispose(){locationSub?.cancel();super.dispose();}
  Future<void> _load()async{
    try{
      final r=await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).get();
      final x=r.data()??{};
      online=(x['status']??'offline').toString().toLowerCase()=='online';
      activeRideId=(x['activeRideId']??'').toString();if(activeRideId!.isEmpty)activeRideId=null;
      vehicle=(x['vehicleType']??'bike').toString().toLowerCase();if(vehicle=='two_wheeler')vehicle='bike';
      await _startLocation();
    }catch(_){}
    if(mounted)setState((){});
  }
  Future<void> _notifications()async{
    try{
      final p=await SharedPreferences.getInstance();if(p.getBool('notifications_enabled')==false)return;
      final s=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      if(s.authorizationStatus==AuthorizationStatus.denied)return;
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      await FirebaseMessaging.instance.subscribeToTopic('carriers');
      final t=await FirebaseMessaging.instance.getToken();
      if(t!=null&&t.isNotEmpty)await FirebaseFirestore.instance.collection('fcmTokens').doc(widget.user.uid).collection('tokens').doc(t).set({'uid':widget.user.uid,'token':t,'role':'carrier','updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
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
      const settings=LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:10);
      final first=await Geolocator.getCurrentPosition(locationSettings:settings);position=first;await _savePosition(first);
      await locationSub?.cancel();
      locationSub=Geolocator.getPositionStream(locationSettings:settings).listen((p){position=p;_savePosition(p);if(mounted)setState((){});});
    }catch(_){}
  }
  Future<void> _savePosition(Position p)async{
    try{
      await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({'carrierLat':p.latitude,'carrierLng':p.longitude,'carrierLocationUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
      final id=activeRideId;
      if(id!=null)await FirebaseFirestore.instance.collection('autoRideRequests').doc(id).set({'driverLat':p.latitude,'driverLng':p.longitude,'driverLocationUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
    }catch(_){}
  }
  Future<void> _setOnline(bool value)async{
    if(value&&!await _permission()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Location permission is required before going online.')));return;}
    if(value)await _startLocation();
    final data={'status':value?'online':'offline','availableForRides':value,'statusUpdatedAt':FieldValue.serverTimestamp(),'vehicleType':vehicle};
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
    final c=TextEditingController(text:vehicle);
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('Vehicle type'),content:TextField(controller:c,decoration:const InputDecoration(hintText:'bike / auto / car')),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Save'))]));
    if(ok==true){vehicle=c.text.trim().toLowerCase().replaceAll('two_wheeler','bike');await FirebaseFirestore.instance.collection('ridePartners').doc(widget.user.uid).set({'vehicleType':vehicle},SetOptions(merge:true));if(mounted)setState((){});}
  }
  @override Widget build(BuildContext context){
    final pages=[
      CarrierHome(online:online,position:position,activeRideId:activeRideId,onOnline:_setOnline),
      RideRequests(user:widget.user,online:online,position:position,vehicle:vehicle,onAccept:_accept,onReject:_reject),
      ActiveRide(rideId:activeRideId,position:position,onCall:_call,onComplete:_complete),
      CarrierEarnings(user:widget.user),
      CarrierProfile(user:widget.user,vehicle:vehicle,onVehicle:_vehicleDialog,onSos:_sos),
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
        ],
      ),
    );
  }
}

class CarrierHome extends StatelessWidget{
  final bool online;final Position? position;final String? activeRideId;final Future<void> Function(bool) onOnline;
  const CarrierHome({super.key,required this.online,required this.position,required this.activeRideId,required this.onOnline});
  @override Widget build(BuildContext c){
    final center=position==null?const LatLng(25.4358,81.8463):LatLng(position!.latitude,position!.longitude);
    return Stack(children:[
      FlutterMap(options:MapOptions(initialCenter:center,initialZoom:14.5),children:[
        TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',maxZoom:19,userAgentPackageName:'com.allways.carrier'),
        if(position!=null)MarkerLayer(markers:[Marker(point:center,width:64,height:64,child:Container(decoration:BoxDecoration(color:purple,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:4),boxShadow:const[BoxShadow(color:Colors.black26,blurRadius:8)]),child:const Icon(Icons.two_wheeler,color:Colors.white,size:30)))]),
      ]),
      Positioned(top:12,left:12,right:12,child:SafeArea(bottom:false,child:Card(color:Colors.white,child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const CircleAvatar(backgroundColor:Color(0x1A5B1ACF),child:Icon(Icons.two_wheeler,color:purple)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('ALLways Carrier',style:TextStyle(fontWeight:FontWeight.w900)),Text(online?'Online • accepting rides within 7 km':'Offline • turn on to receive rides',style:const TextStyle(color:Colors.grey,fontSize:12))])),Switch(value:online,onChanged:onOnline)]))))),
      Positioned(left:12,right:12,bottom:16,child:SafeArea(top:false,child:Column(children:[
        Card(child:Padding(padding:const EdgeInsets.fromLTRB(16,15,16,14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Where are you going?',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          const SizedBox(height:10),
          Container(height:50,padding:const EdgeInsets.symmetric(horizontal:14),decoration:BoxDecoration(color:ivory,borderRadius:BorderRadius.circular(15)),child:const Row(children:[Icon(Icons.search),SizedBox(width:10),Text('Search pickup or destination',style:TextStyle(color:Colors.grey))])),
          const SizedBox(height:12),
          const Text('Recent destinations',style:TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:7),
          const Wrap(spacing:8,runSpacing:8,children:[Chip(label:Text('Prayagraj Civil Lines')),Chip(label:Text('Railway Junction')),Chip(label:Text('Sangam'))]),
        ])),
        const SizedBox(height:8),
        if(activeRideId!=null)Card(child:ListTile(leading:const Icon(Icons.navigation,color:purple),title:const Text('Active ride',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('#'+activeRideId!),trailing:const Icon(Icons.chevron_right))),
        if(!online)const SizedBox(height:2),
        if(online)const Text('Nearby ride requests are shown in Requests.',style:TextStyle(color:Colors.black54,fontSize:12)),
      ]))),
    ]);
  }
}

class RideRequests extends StatelessWidget{
  final User user;final bool online;final Position? position;final String vehicle;
  final Future<void> Function(QueryDocumentSnapshot<Map<String,dynamic>>) onAccept;final Future<void> Function(DocumentReference) onReject;
  const RideRequests({super.key,required this.user,required this.online,required this.position,required this.vehicle,required this.onAccept,required this.onReject});
  double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
  @override Widget build(BuildContext c)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('autoRideRequests').where('status',isEqualTo:'searching').snapshots(),
    builder:(context,s){
      if(!online)return const Center(child:Text('Go online to receive ride requests.'));
      if(position==null)return const Center(child:Text('Live location is required to match rides.'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final list=<QueryDocumentSnapshot<Map<String,dynamic>>>[];
      for(final d in s.data!.docs){
        final x=d.data();final rejected=x['rejectedBy'] is List?List.from(x['rejectedBy']):<dynamic>[];
        if(rejected.contains(user.uid))continue;
        final type=(x['rideType']??'bike').toString().toLowerCase();if(type!=vehicle)continue;
        final lat=n(x['pickupLatitude']??x['pickupLat']);final lng=n(x['pickupLongitude']??x['pickupLng']);if(lat==0||lng==0)continue;
        if(Geolocator.distanceBetween(position!.latitude,position!.longitude,lat,lng)<=7000)list.add(d);
      }
      if(list.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('No ride requests within 7 km right now.',textAlign:TextAlign.center)));
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

class ActiveRide extends StatefulWidget{
  final String? rideId;final Position? position;final Future<void> Function(String) onCall;final Future<void> Function(DocumentReference) onComplete;
  const ActiveRide({super.key,required this.rideId,required this.position,required this.onCall,required this.onComplete});
  @override State<ActiveRide> createState()=>_ActiveRideState();
}
class _ActiveRideState extends State<ActiveRide>{
  List<LatLng> route=[];LatLng? pickup,destination,driver,customer;bool routeLoading=false;
  double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
  @override Widget build(BuildContext c){
    if(widget.rideId==null)return const Center(child:Text('No active ride.'));
    return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('autoRideRequests').doc(widget.rideId).snapshots(),
      builder:(context,s){
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final x=s.data!.data()??{};
        pickup=_point(x['pickupLatitude']??x['pickupLat'],x['pickupLongitude']??x['pickupLng']);
        destination=_point(x['destinationLatitude']??x['destLat'],x['destinationLongitude']??x['destLng']);
        driver=_point(x['driverLat'],x['driverLng']);
        customer=_point(x['customerLat']??x['pickupLatitude'],x['customerLng']??x['pickupLongitude']);
        if(route.isEmpty&&pickup!=null&&destination!=null&&!routeLoading){routeLoading=true;_route(pickup!,destination!);}
        final center=driver??pickup??destination??const LatLng(25.4358,81.8463);
        final marks=<Marker>[
          if(driver!=null)Marker(point:driver!,width:62,height:62,child:const Pin(color:purple,icon:Icons.two_wheeler)),
          if(customer!=null)Marker(point:customer!,width:58,height:58,child:const Pin(color:Colors.blue,icon:Icons.person)),
          if(pickup!=null)Marker(point:pickup!,width:58,height:58,child:const Pin(color:Colors.green,icon:Icons.check)),
          if(destination!=null)Marker(point:destination!,width:58,height:58,child:const Pin(color:Colors.red,icon:Icons.flag)),
        ];
        final phone=(x['customerPhone']??x['phone']??'').toString();
        return Stack(children:[
          FlutterMap(options:MapOptions(initialCenter:center,initialZoom:14.5),children:[TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',maxZoom:19,userAgentPackageName:'com.allways.carrier'),if(route.isNotEmpty)PolylineLayer(polylines:[Polyline(points:route,color:purple,strokeWidth:5)]),MarkerLayer(markers:marks)]),
          Positioned(top:12,left:12,right:12,child:SafeArea(bottom:false,child:Card(color:const Color(0xFFFDECEF),child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[const Icon(Icons.circle,color:Colors.green,size:12),const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Live ride tracking',style:TextStyle(fontWeight:FontWeight.w900)),Text((x['status']??'accepted').toString(),style:const TextStyle(color:Colors.grey,fontSize:12))])),if(phone.isNotEmpty)IconButton(onPressed:()=>widget.onCall(phone),icon:const Icon(Icons.call))]))))),
          Positioned(left:12,right:12,bottom:14,child:SafeArea(top:false,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text((x['pickupAddress']??'Pickup').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800)),
            Text((x['destinationAddress']??'Destination').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.grey)),
            const SizedBox(height:10),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>widget.onComplete(s.data!.reference),style:FilledButton.styleFrom(backgroundColor:Colors.green),child:const Text('Complete ride'))),
          ])))),
        ]);
      },
    );
  }
  LatLng? _point(dynamic a,dynamic b){final x=n(a),y=n(b);if(x==0&&y==0)return null;return LatLng(x,y);}
  Future<void> _route(LatLng a,LatLng b)async{
    try{
      final uri=Uri.parse('https://router.project-osrm.org/route/v1/driving/'+a.longitude.toString()+','+a.latitude.toString()+';'+b.longitude.toString()+','+b.latitude.toString()+'?overview=full&geometries=geojson');
      final r=await http.get(uri);if(r.statusCode!=200)return;final d=jsonDecode(r.body);final coords=d['routes']?[0]?['geometry']?['coordinates'];if(coords is! List)return;
      final points=coords.whereType<List>().where((p)=>p.length>=2).map((p)=>LatLng((p[1] as num).toDouble(),(p[0] as num).toDouble())).toList();
      if(mounted)setState(()=>route=points);
    }catch(_){}
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
