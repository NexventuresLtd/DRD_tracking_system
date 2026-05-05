import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/commander/commander_home.dart';
import '../screens/commander/team_management.dart';
import '../screens/commander/route_planning.dart';
import '../screens/commander/live_tracking.dart';
import '../screens/operator/operator_home.dart';
import '../screens/operator/field_operations.dart';
import '../screens/operator/reports.dart';
import '../screens/field_unit/field_home.dart';
import '../screens/field_unit/tactical_map_screen.dart';
import '../screens/field_unit/navigation.dart';
import '../screens/field_unit/check_in.dart';
import '../screens/field_unit/sos_screen.dart';
import '../screens/viewer/viewer_home.dart';

class AppRoutes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/splash':
        return _buildRoute(settings, const SplashScreen());
      case '/login':
        return _buildRoute(settings, const LoginScreen());
      case '/commander/home':
        return _buildRoute(settings, const CommanderHome());
      case '/commander/teams':
        return _buildRoute(settings, const TeamManagement());
      case '/commander/routes':
        return _buildRoute(settings, const RoutePlanning());
      case '/commander/tracking':
        return _buildRoute(settings, const LiveTracking());
      case '/operator/home':
        return _buildRoute(settings, const OperatorHome());
      case '/operator/operations':
        return _buildRoute(settings, const FieldOperations());
      case '/operator/reports':
        return _buildRoute(settings, const Reports());
      case '/field/tactical':
        return _buildRoute(settings, const TacticalMapScreen());
      case '/field/home':
        return _buildRoute(settings, const FieldHome());
      case '/field/navigation':
        return _buildRoute(settings, const Navigation());
      case '/field/checkin':
        return _buildRoute(settings, const CheckIn());
      case '/field/sos':
        return _buildRoute(settings, const SOSScreen());
      case '/viewer/home':
        return _buildRoute(settings, const ViewerHome());
      default:
        return _buildRoute(settings, const SplashScreen());
    }
  }

  static MaterialPageRoute _buildRoute(RouteSettings settings, Widget page) {
    return MaterialPageRoute(
      builder: (context) => page,
      settings: settings,
    );
  }
}