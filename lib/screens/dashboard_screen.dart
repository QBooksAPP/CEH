import 'package:flutter/material.dart';
import '../core/ceh_theme.dart';
import '../models/session.dart';
import 'concrete_operations_screen.dart';
import 'module_placeholder_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.session, required this.onLogout});
  final CehSession session;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final modules = <Map<String,dynamic>>[
      {'t':'Concrete Operations','s':'Calibration, mix designs and mixer settings','i':Icons.precision_manufacturing_outlined,'e':true},
      if (user.isAdmin) {'t':'Accounts','s':'Expenses, income, petty cash and reports','i':Icons.account_balance_wallet_outlined,'e':false},
      if (user.isAdmin) {'t':'Fleet & Equipment','s':'Mixers, pumps, trucks and workshop equipment','i':Icons.local_shipping_outlined,'e':false},
      if (user.isAdmin) {'t':'Administration','s':'Users, history, approvals and audit trail','i':Icons.admin_panel_settings_outlined,'e':true},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('CEH',style:TextStyle(fontWeight:FontWeight.w900)), actions:[
        IconButton(onPressed:onLogout, icon:const Icon(Icons.logout))
      ]),
      body: ListView(
        padding:const EdgeInsets.all(18),
        children:[
          Container(
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(
              gradient:const LinearGradient(colors:[CehTheme.navy,CehTheme.blue]),
              borderRadius:BorderRadius.circular(20),
            ),
            child:Text('Welcome\n${user.fullName}\n${user.role}', style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800)),
          ),
          const SizedBox(height:22),
          const Text('Company modules',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),
          ...modules.map((m)=>Card(child:ListTile(
            contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
            leading:Icon(m['i'] as IconData),
            title:Text(m['t'] as String,style:const TextStyle(fontWeight:FontWeight.w800)),
            subtitle:Text(m['s'] as String),
            trailing:(m['e'] as bool)?const Icon(Icons.chevron_right):const Text('COMING SOON',style:TextStyle(fontSize:10,fontWeight:FontWeight.w800)),
            onTap:(){
              if(m['t']=='Concrete Operations'){
                Navigator.push(context,MaterialPageRoute(builder:(_)=>ConcreteOperationsScreen(session:session)));
              } else {
                Navigator.push(context,MaterialPageRoute(builder:(_)=>ModulePlaceholderScreen(
                  title:m['t'] as String,
                  message:'${m['t']} will be connected as a later CEH module.',
                )));
              }
            },
          ))),
        ],
      ),
    );
  }
}
