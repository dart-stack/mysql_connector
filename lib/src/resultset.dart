import 'session.dart';
import 'socket.dart';
import 'utils.dart';

class FieldDefinitionView {
  final Map<String, dynamic> props;

  const FieldDefinitionView(this.props);

  String get catalog => props["catalog"];

  String get db => props["db"];

  String get name => props["name"];

  String get originalName => props["orgName"];

  String get table => props["table"];

  String get originalTable => props["orgTable"];

  int get charsetNumber => props["charsetNumber"];

  int get type => props["type"];

  int get length => props["length"];

  int get decimals => props["decimals"];

  int get flags => props["flags"];

  @override
  String toString() {
    return props.toString();
  }
}

class ResultSetView {
  final Map<String, dynamic> _props;

  const ResultSetView(this._props);

  Map<String, dynamic> get props => _props;

  int get columnCount => _props["columnCount"];

  List<FieldDefinitionView> get columns => _props["columns"];

  List<List<dynamic>> get rows => _props["rows"];
}

Future<void> readResultSet(
  PacketBuffer reader,
  SessionContext session,
) async {
  final numColumns = _readColumnCount(await reader.readPacket(), session);
  for (int i = 0; i < numColumns; i++) {
    await reader.readPacket();
  }
  await reader.readPacket();

  for (int i = 0;; i++) {
    final buffer = await reader.readPacket();
    if (buffer[4] == 0xFE) {
      print("resultset was read $i rows");
      return;
    }
  }
}

int _readColumnCount(List<int> buffer, SessionContext session) {
  final cursor = Cursor.from(4);
  return readLengthEncodedInteger(buffer, cursor)!;
}
