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
  bool checking=false;

  @override void initState(){
    super.initState();
    _check(silent:true);
    _timer=Timer.periodic(const Duration(minutes:10),(_)=>_check(silent:true));
  }
  @override void dispose(){_timer?.cancel();super.dispose();}

  List<int> _parts(String v)=>v.replaceFirst(RegExp(r'^[^0-9]*'),'').split('.').map((x)=>int.tryParse(RegExp(r'^\d+').stringMatch(x)??'0')??0).toList();
  bool _newer(String a,String b){
    final x=_parts(a),y=_parts(b);
    for(var i=0;i<3;i++){final aa=i<x.length?x[i]:0,bb=i<y.length?y[i]:0;if(aa!=bb)return aa>bb;}
    return false;
  }

  void _message(String message){
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));
  }

  Future<void> _check({bool silent=false})async{
    if(busy||checking)return;
    checking=true;
    if(!silent&&mounted)setState(()=>checking=true);
    try{
      final info=await PackageInfo.fromPlatform();
      final r=await http.get(
        Uri.parse('https://api.github.com/repos/${widget.repo}/releases/tags/allways-latest'),
        headers:{'Accept':'application/vnd.github+json','User-Agent':'ALLways-Updater'},
      ).timeout(const Duration(seconds:12));
      if(r.statusCode!=200)throw StateError('Release check failed (HTTP ${r.statusCode}).');
      final decoded=jsonDecode(r.body);
      if(decoded is! Map)throw StateError('The release response was invalid.');
      final releaseName=(decoded['name']??'').toString();
      final match=RegExp(r'(\d+\.\d+\.\d+)').firstMatch(releaseName);
      final remoteVersion=match?.group(1)??'';
      if(remoteVersion.isEmpty)throw StateError('The latest release has no readable version number.');
      final assets=decoded['assets'] is List ? decoded['assets'] as List : const [];
      String downloadUrl='';
      String digest='';
      for(final raw in assets){
        if(raw is Map&&(raw['name']??'').toString()==widget.assetName){
          downloadUrl=(raw['browser_download_url']??'').toString();
          final rawDigest=(raw['digest']??'').toString().toLowerCase().trim();
          digest=rawDigest.startsWith('sha256:')?rawDigest.substring(7):rawDigest;
          break;
        }
      }
      if(!_newer(remoteVersion,info.version)){
        if(mounted)setState((){
          version=null;url=null;expectedSha256=null;notes='';
        });
        if(!silent)_message('You’re up to date (version ${info.version}).');
        return;
      }
      if(downloadUrl.isEmpty)throw StateError('A newer version exists, but its APK asset is missing.');
      if(!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)){
        throw StateError('A newer APK is available, but its SHA-256 checksum is missing. Update is paused for safety.');
      }
      if(mounted)setState((){
        version=remoteVersion;url=downloadUrl;expectedSha256=digest;
        notes=(decoded['body']??'').toString();
      });
      if(!silent)_message('ALLways version $remoteVersion is available. Tap UPDATE to install it.');
    }catch(e){
      if(!silent)_message('Could not check for updates: ${e.toString().replaceFirst('Bad state: ','')}');
    }finally{
      checking=false;
      if(mounted)setState(()=>checking=false);
    }
  }

  Future<void> _install()async{
    final download=url, expected=expectedSha256;
    if(download==null||download.isEmpty||expected==null||expected.isEmpty||busy||checking)return;
    setState(()=>busy=true);
    final progress=ValueNotifier<double>(0);
    var dialogShown=false;
    try{
      if(mounted){
        dialogShown=true;
        showDialog(context:context,barrierDismissible:false,builder:(_)=>AlertDialog(
          title:Text('Updating ALLways to ${version??''}'),
          content:ValueListenableBuilder<double>(valueListenable:progress,builder:(_,value,__)=>Column(
            mainAxisSize:MainAxisSize.min,
            children:[LinearProgressIndicator(value:value>0?value:null),const SizedBox(height:12),
              Text(value>0?'Downloading ${(value*100).toStringAsFixed(0)}%':'Starting download…')],
          )),
        ));
      }
      final file=File('${Directory.systemTemp.path}/allways_${DateTime.now().millisecondsSinceEpoch}.apk');
      await Dio().download(
        download+(download.contains('?')?'&':'?')+'cacheBust=${DateTime.now().millisecondsSinceEpoch}',
        file.path,deleteOnError:true,
        onReceiveProgress:(received,total){if(total>0)progress.value=received/total;},
      );
      final actual=sha256.convert(await file.readAsBytes()).toString().toLowerCase();
      if(actual!=expected)throw StateError('Downloaded APK failed integrity verification; it will not be installed.');
      if(mounted&&dialogShown&&Navigator.of(context).canPop())Navigator.of(context).pop();
      dialogShown=false;
      final result=await MethodChannel(widget.packageChannel).invokeMethod<String>('installApk',{'path':file.path});
      if(result=='permission_required'){
        await MethodChannel(widget.packageChannel).invokeMethod('openInstallSettings');
        _message('Allow ALLways to install updates in Android settings, then return and tap UPDATE again.');
      }else if(result=='started'){
        _message('Android opened the update installer. Confirm the installation to finish updating.');
      }else{
        _message('Could not start installation: ${result??'unknown error'}');
      }
    }catch(e){
      if(mounted&&dialogShown&&Navigator.of(context).canPop())Navigator.of(context).pop();
      _message('Update failed: ${e.toString().replaceFirst('Bad state: ','')}');
    }finally{
      progress.dispose();
      if(mounted)setState(()=>busy=false);
    }
  }

  @override Widget build(BuildContext context){
    final theme=Theme.of(context);
    return Stack(
      children:[
        widget.child,
        Positioned(
          right:12,bottom:12,
          child:SafeArea(
            child:Material(
              color:theme.colorScheme.surface,
              elevation:4,
              borderRadius:BorderRadius.circular(24),
              child:Padding(
                padding:const EdgeInsets.symmetric(horizontal:4,vertical:2),
                child:TextButton.icon(
                  onPressed:busy||checking?null:()=>_check(),
                  icon:checking
                    ?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))
                    :const Icon(Icons.system_update_alt,size:18),
                  label:Text(checking?'Checking…':'App updates'),
                ),
              ),
            ),
          ),
        ),
        if(version!=null)
          Positioned(
            top:0,left:0,right:0,
            child:Material(
              elevation:6,
              color:theme.colorScheme.primaryContainer,
              child:SafeArea(
                bottom:false,
                child:Padding(
                  padding:const EdgeInsets.fromLTRB(14,10,8,10),
                  child:Row(
                    children:[
                      const Icon(Icons.system_update),
                      const SizedBox(width:10),
                      Expanded(
                        child:Column(
                          crossAxisAlignment:CrossAxisAlignment.start,
                          children:[
                            const Text('New ALLways update available',style:TextStyle(fontWeight:FontWeight.w900)),
                            Text(
                              'Version $version is ready${notes.isNotEmpty?' • '+notes.replaceAll(RegExp(r'\s+'),' ').trim():''}',
                              maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(onPressed:busy||checking?null:_install,child:const Text('UPDATE')),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
