import 'package:mysql_connector/src/connection.dart';

Future<Connection> connectToServer() async {
  final fac = ConnectionFactory();
  final conn = await fac.connect(
    host: "127.0.0.1",
    port: 3306,
    user: "root",
    password: "root",
    database: "test",
    enableCompression: true,
    compressionThreshold: 0xffffff,
  );

  return conn;
}