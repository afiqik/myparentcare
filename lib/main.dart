import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'api/email_gateway.dart';
import 'api/email_relay.dart';
import 'app_config.dart';
import 'auth/auth_service.dart';
import 'auth/google_auth_adapter.dart';
import 'availability/connectivity_manager.dart';
import 'backend_logic/account_deletion_service.dart';
import 'backend_logic/admin_state.dart';
import 'backend_logic/backup_service.dart';
import 'backend_logic/email_service.dart';
import 'backend_logic/legacy_migration_service.dart';
import 'backend_logic/student_state.dart';
import 'cache_cdn/cache_manager.dart';
import 'database_storage/admin_workspace.dart';
import 'database_storage/media_repository.dart';
import 'database_storage/program_repository.dart';
import 'database_storage/user_repository.dart';
import 'error_tracking/error_tracker.dart';
import 'firebase_options.dart';
import 'frontend/screens/auth/splash_screen.dart';
import 'frontend/theme.dart';
import 'frontend/widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;
  CacheManager.configureFirestore(firestore);
  final auth = FirebaseAuth.instance;

  var appVersion = '';
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {}

  ErrorTracker().configure(
    firestore: firestore,
    currentUid: () => auth.currentUser?.uid,
    appVersion: appVersion,
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorTracker().logError(
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorTracker().logError('Uncaught error', error: error, stackTrace: stack);
    return true;
  };

  runApp(MyParentCareApp(services: AppServices.create(firestore, auth, appVersion)));
}

/// Semua kebergantungan aplikasi (disuntik supaya boleh diuji).
class AppServices {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final String appVersion;
  final ProgramRepository programs;
  final UserRepository users;
  final MediaRepository media;
  final EmailService email;
  final AccountDeletionService deletion;
  final AdminWorkspace Function() workspace;
  final GoogleAuthAdapter? google;
  final Duration? adminAutoSendInterval;
  final EmailRelay? relay;
  final ConnectivityManager connectivity = ConnectivityManager();

  AppServices({
    required this.auth,
    required this.firestore,
    required this.appVersion,
    required this.programs,
    required this.users,
    required this.media,
    required this.email,
    required this.deletion,
    required this.workspace,
    this.google,
    this.adminAutoSendInterval,
    this.relay,
  });

  factory AppServices.create(
    FirebaseFirestore firestore,
    FirebaseAuth auth,
    String appVersion,
  ) {
    final programs = ProgramRepository(firestore);
    final users = UserRepository(firestore);

    // RTDB hanya dibuka apabila admin menggunakannya (had 100 sambungan Spark).
    AdminWorkspace? workspace;
    AdminWorkspace workspaceFactory() {
      if (workspace != null) return workspace!;
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: AppConfig.rtdbUrl,
      );
      CacheManager.configureRealtimeDatabase(database);
      return workspace = RtdbAdminWorkspace(database);
    }

    return AppServices(
      auth: auth,
      firestore: firestore,
      appVersion: appVersion,
      programs: programs,
      users: users,
      media: MediaRepository(firestore),
      email: EmailService(
        firestore,
        gateway: EmailJsGateway(),
        programs: programs,
      ),
      deletion: AccountDeletionService(firestore, programs),
      workspace: workspaceFactory,
      adminAutoSendInterval: const Duration(minutes: 1),
      relay: EmailRelay(firestore),
    );
  }
}

class MyParentCareApp extends StatelessWidget {
  final AppServices services;
  final Widget home;

  const MyParentCareApp({
    super.key,
    required this.services,
    this.home = const SplashScreen(),
  });

  @override
  Widget build(BuildContext context) {
    final connectivity = services.connectivity;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        Provider<MediaRepository>.value(value: services.media),
        ChangeNotifierProvider<ConnectivityManager>.value(value: connectivity),
        ChangeNotifierProvider(
          create: (_) => AuthService(
            auth: services.auth,
            users: services.users,
            workspace: services.workspace,
            deletion: services.deletion,
            google: services.google,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => StudentState(
            programs: services.programs,
            users: services.users,
            connectivity: connectivity,
            relay: services.relay,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminState(
            programsRepo: services.programs,
            usersRepo: services.users,
            email: services.email,
            media: services.media,
            workspace: services.workspace,
            backup: () => BackupService(services.firestore, services.workspace()),
            migration: () =>
                LegacyMigrationService(services.firestore, services.workspace()),
            connectivity: connectivity,
            autoSendInterval: services.adminAutoSendInterval,
            relay: services.relay,
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => AppShell(child: child ?? const SizedBox()),
        home: home,
      ),
    );
  }
}
