import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ValueNotifier<ThemeMode> {
  AppThemeController():super(ThemeMode.system);
  static const _key='app_theme_mode';
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    value=switch(p.getString(_key)){
      'light'=>ThemeMode.light,
      'dark'=>ThemeMode.dark,
      _=>ThemeMode.system,
    };
  }
  Future<void> setMode(ThemeMode mode) async {
    value=mode;
    final p=await SharedPreferences.getInstance();
    await p.setString(_key,switch(mode){ThemeMode.light=>'light',ThemeMode.dark=>'dark',_=>'system'});
  }
}

final appThemeController=AppThemeController();

class ThemeSettingsPage extends StatelessWidget {
  final Color accent;
  const ThemeSettingsPage({super.key,required this.accent});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Change Theme')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Column(children:[
        _option(context,'System default',ThemeMode.system,Icons.brightness_auto),
        _option(context,'Light',ThemeMode.light,Icons.light_mode_outlined),
        _option(context,'Dark',ThemeMode.dark,Icons.dark_mode_outlined),
      ])),
    ]),
  );
  Widget _option(BuildContext c,String label,ThemeMode mode,IconData icon)=>ValueListenableBuilder<ThemeMode>(
    valueListenable:appThemeController,
    builder:(c,current,_)=>RadioListTile<ThemeMode>(
      value:mode,groupValue:current,activeColor:accent,secondary:Icon(icon,color:accent),
      title:Text(label),onChanged:(v){if(v!=null)appThemeController.setMode(v);},
    ),
  );
}

class AccountSettingsPage extends StatefulWidget {
  final User user;
  final String collection;
  final Color accent;
  final String role;
  const AccountSettingsPage({super.key,required this.user,required this.collection,required this.accent,required this.role});
  @override State<AccountSettingsPage> createState()=>_AccountSettingsPageState();
}
class _AccountSettingsPageState extends State<AccountSettingsPage>{
  bool deleting=false;
  Future<void> _deleteAccount() async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Delete account?'),
      content:const Text('This permanently deletes your account and its personal profile data. This action cannot be undone.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete'))],
    ))??false;
    if(!ok||deleting)return;
    setState(()=>deleting=true);
    try{
      final u=FirebaseAuth.instance.currentUser;
      if(u==null)throw Exception('No signed-in account.');
      try{await u.delete();}on FirebaseAuthException catch(e){
        if(e.code!='requires-recent-login')rethrow;
        final providers=u.providerData.map((p)=>p.providerId).toList();
        if(providers.contains('google.com')){
          final gs=GoogleSignIn.instance;
          if(!gs.supportsAuthenticate())throw Exception('Please sign out and sign in again before deleting this account.');
          final gu=await gs.authenticate();
          final id=gu.authentication.idToken;
          if(id==null||id.isEmpty)throw Exception('Google re-authentication failed.');
          await u.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken:id));
          await u.delete();
        }else{
          final password=await _passwordDialog();
          if(password==null||password.isEmpty)throw Exception('Deletion cancelled.');
          final credential=EmailAuthProvider.credential(email:u.email??'',password:password);
          await u.reauthenticateWithCredential(credential);
          await u.delete();
        }
      }
      await FirebaseFirestore.instance.collection(widget.collection).doc(u.uid).delete().catchError((_){});
      await FirebaseAuth.instance.signOut();
      if(mounted)Navigator.of(context).popUntil((r)=>r.isFirst);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));
    }finally{if(mounted)setState(()=>deleting=false);}
  }
  Future<String?> _passwordDialog() async {
    final c=TextEditingController();
    return showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Confirm your password'),
      content:TextField(controller:c,obscureText:true,decoration:const InputDecoration(labelText:'Password')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text),child:const Text('Continue'))],
    ));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Account Settings')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:ListTile(leading:Icon(Icons.person_outline,color:widget.accent),title:Text(widget.user.displayName??'Account'),subtitle:Text(widget.user.email??''))),
      Card(child:ListTile(leading:Icon(Icons.palette_outlined,color:widget.accent),title:const Text('Change Theme'),subtitle:const Text('Light, dark or system default'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ThemeSettingsPage(accent:widget.accent))))),
      Card(child:ListTile(leading:const Icon(Icons.logout),title:const Text('Sign out'),onTap:()=>FirebaseAuth.instance.signOut())),
      Card(child:ListTile(leading:const Icon(Icons.delete_outline,color:Colors.red),title:const Text('Delete Account',style:TextStyle(color:Colors.red)),subtitle:const Text('Permanently delete this account'),onTap:deleting?null:_deleteAccount)),
    ]),
  );
}
