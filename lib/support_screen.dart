import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CarrierSupportScreen extends StatefulWidget {
  final User user;
  const CarrierSupportScreen({super.key,required this.user});
  @override State<CarrierSupportScreen> createState()=>_CarrierSupportScreenState();
}
class _CarrierSupportScreenState extends State<CarrierSupportScreen>{
  String area='Ride';
  final message=TextEditingController();
  String category='Ride issue';
  bool busy=false;
  Future<void> submit()async{
    if(message.text.trim().isEmpty)return;
    setState(()=>busy=true);
    try{
      await FirebaseFirestore.instance.collection('supportTickets').add({
        'requesterId':widget.user.uid,'requesterRole':'carrier','requesterName':widget.user.displayName??widget.user.email??'Carrier',
        'queue':'Service Support','area':area,'category':category,'subcategory':category,'subject':category,
        'message':message.text.trim(),'priority':'normal','status':'open',
        'createdAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp(),
      });
      if(mounted){message.clear();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Support request submitted.')));}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not submit support request: $e')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Help & Support')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('What do you need help with?',style:TextStyle(fontSize:21,fontWeight:FontWeight.w900)),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:area,decoration:const InputDecoration(labelText:'Area'),
        items:const [DropdownMenuItem(value:'Ride',child:Text('Ride')),DropdownMenuItem(value:'Account',child:Text('Account')),DropdownMenuItem(value:'Safety',child:Text('Safety')),DropdownMenuItem(value:'General',child:Text('General'))],
        onChanged:(v)=>setState(()=>area=v??area)),
      const SizedBox(height:10),
      DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Issue'),
        items:const [DropdownMenuItem(value:'Ride issue',child:Text('Ride issue')),DropdownMenuItem(value:'Customer issue',child:Text('Customer issue')),DropdownMenuItem(value:'Fare issue',child:Text('Fare / earnings issue')),DropdownMenuItem(value:'Navigation issue',child:Text('Navigation / location issue')),DropdownMenuItem(value:'Account issue',child:Text('Account issue')),DropdownMenuItem(value:'Safety concern',child:Text('Safety concern')),DropdownMenuItem(value:'General issue',child:Text('General issue'))],
        onChanged:(v)=>setState(()=>category=v??category)),
      const SizedBox(height:10),
      TextField(controller:message,maxLines:6,decoration:const InputDecoration(labelText:'Describe the issue')),
      const SizedBox(height:12),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:submit,child:busy?const CircularProgressIndicator():const Text('Submit to ALLways Support'))),
      const SizedBox(height:20),
      const Text('My support requests',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:FirebaseFirestore.instance.collection('supportTickets').where('requesterId',isEqualTo:widget.user.uid).orderBy('createdAt',descending:true).limit(20).snapshots(),
        builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());if(s.data!.docs.isEmpty)return const Text('No support requests yet.');
          return Column(children:s.data!.docs.map((d){final x=d.data();return Card(child:ListTile(title:Text((x['subject']??'Support request').toString()),subtitle:Text((x['status']??'open').toString()+' • '+(x['message']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis)));}).toList());}
      )
    ])
  );
}
