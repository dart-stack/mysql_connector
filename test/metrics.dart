import 'package:mockito/annotations.dart';
import 'package:mysql_connector/src/metrics.dart';

@GenerateNiceMocks([MockSpec<MetricsCollector>()])
export 'metrics.mocks.dart';
