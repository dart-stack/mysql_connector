import 'dart:typed_data';

import 'package:mysql_connector/src/utils.dart';


List<int> generatePackets(
  List<({int length, int sequence})> templates, {
  bool compressed = false,
}) {
  final builder = BytesBuilder();

  for (final template in templates) {
    writeInteger(builder, 3, template.length);
    writeInteger(builder, 1, template.sequence);
    if (compressed) {
      writeInteger(builder, 3, 0);
    }
    writeBytes(builder, List.filled(template.length, 0x00));
  }

  return builder.takeBytes();
}
