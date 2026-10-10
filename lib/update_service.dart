import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AllwaysUpdateGate extends StatefulWidget {
  final Widget child;
  final String repo;
  final String packageChannel;
  final String assetName;
  const AllwaysUpdateGate({super.key, required this.child, required this.repo, required this.packageChannel, required this.assetName});
  @override State<AllwaysUpdateGate> createState()=>_AllwaysUpdateGateState();
}
class _AllwaysUpdateGateState extends State<AllwaysUpdateGate> {
  Timer? _timer;
  String? version;
  String? url;
  String? expectedSha256;
  String notes='';
  bool busy=false;
  @override void initState(){super.initState();_check();_timer=Timer.periodic(const Duration(minutes:10),(_)=>_check(silent:true));}
  @override void dispose(){_timer?.cancel();super.dispose();}
  List<int> _parts(String v)=>v.replaceFirst(RegExp(r'^[^0-9]*'),'').split('.').map((x)=>int.tryParse(RegExp(r'^\d+').stringMatch(x)??'0')??0).toList();
  bool _newer(String a,String b){final x=_parts(a),y=_parts(b);for(var i=0;i<3;i++){final aa=i<x.length?x[i]:0,bb=i<y.length?y[i]:0;if(aa!=bb)return aa>bb;}return false;}
  Future<void> _check({bool silent=false})async{
    if(busy)return;
    try{
      final info=await PackageInfo.fromPlatform();
      final r=await http.get(Uri.parse('https://api.github.com/repos/${widget.repo}/releases/tags/allways-latest'),headers:{'Accept':'application/vnd.github+json','User-Agent':'ALLways-Updater'}).timeout(const Duration(seconds:8));
      if(r.statusCode!=200)return;
      final d=jsonDecode(r.body);if(d is! Map)return;
      final name=(d['name']??'').toString();final m=RegExp(r'(\d+\.\d+\.\d+)').firstMatch(name);final remote=m?.group(1)??'';
      final assets=(d['assets'] is List)?(d['assets'] as List):const [];
      String found=''; String digest='';
      for(final raw in assets){
        if(raw is Map&&(raw['name']??'').toString()==widget.assetName){
          found=(raw['browser_download_url']??'').toString();
          final rawDigest=(raw['digest']??'').toString().toLowerCase().trim();
          digest=rawDigest.startsWith('sha256:')?rawDigest.substring(7):rawDigest;
          break;
        }
      }
      if(remote.isNotEmpty&&found.isNotEmpty&&RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)&&_newer(remote,info.version)&&mounted){
        setState(() { version=remote; url=found; expectedSha256=digest; notes=(d['body']??'').toString(); });
      }
    }catch(_) {}
  }
  Future<void> _install()async{
    final u=url, expected=expectedSha256;
    if(u==null||u.isEmpty||expected==null||expected.isEmpty||busy)return;
    setState(()=>busy=true);final p=ValueNotifier<double>(0);
    try{
      if(mounted)showDialog(context:context,barrierDismissible:false,builder:(_)=>AlertDialog(title:Text('Updating ALLways to ${version??''}'),content:ValueListenableBuilder<double>(valueListenable:p,builder:(_,v,__)=>Column(mainAxisSize:MainAxisSize.min,children:[LinearProgressIndicator(value:v>0?v:null),const SizedBox(height:12),Text(v>0?'Downloading ${(v*100).toStringAsFixed(0)}%':'Starting download…')]))));
      final file=File('${Directory.systemTemp.path}/allways_${DateTime.now().millisecondsSinceEpoch}.apk');
      await Dio().download(u+(u.contains('?')?'&':'?')+'cacheBust=${DateTime.now().millisecondsSinceEpoch}',file.path,deleteOnError:true,onReceiveProgress:(a,b){if(b>0)p.value=a/b;});
      final actual=sha256.convert(await file.readAsBytes()).toString().toLowerCase();
      if(actual!=expected)throw StateError('Downloaded update failed integrity verification.');
      if(mounted&&Navigator.of(context).canPop())Navigator.of(context).pop();
      final result=await MethodChannel(widget.packageChannel).invokeMethod<String>('installApk',{'path':file.path});
      if(result=='permission_required'){
        await MethodChannel(widget.packageChannel).invokeMethod('openInstallSettings');
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Allow ALLways to install updates, then tap UPDATE NOW again.')));
      }else if(result!='started'&&mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not start installation: ${result??'unknown error'}')));}
    }catch(e){if(mounted&&Navigator.of(context).canPop())Navigator.of(context).pop();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Update failed: $e')));}finally{p.dispose();if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context) {
    if (version == null) {
      return Stack(children: [
        widget.child,
        Positioned(
          right: 12,
          bottom: 96,
          child: SafeArea(
            child: FloatingActionButton.small(
              heroTag: 'allways_update_check_${widget.repo}',
              tooltip: 'Check for updates',
              onPressed: busy ? null : () async {
                await _check();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(version == null
                    ? 'No update was detected. Check your connection and try again if needed.'
                    : 'ALLways update ${version!} is available at the top of the screen.'),
                ));
              },
              child: const Icon(Icons.system_update_alt),
            ),
          ),
        ),
      ]);
    }
    return Stack(children:[widget.child,Positioned(top:0,left:0,right:0,child:Material(elevation:6,color:Theme.of(context).colorScheme.primaryContainer,child:SafeArea(bottom:false,child:Padding(padding:const EdgeInsets.fromLTRB(14,10,8,10),child:Row(children:[const Icon(Icons.system_update),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('New ALLways update available',style:TextStyle(fontWeight:FontWeight.w900)),Text('Version $version is ready${notes.isNotEmpty ? ' • ' + notes.replaceAll(RegExp(r'\\s+'),' ').trim() : ''}',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12))])),FilledButton(onPressed:busy?null:_install,child:const Text('UPDATE'))])))))]);
  }
}