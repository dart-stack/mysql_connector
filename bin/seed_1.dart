import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  final content = BytesBuilder();
  content.add(utf8.encode("id email\n"));
  for (int i = 1; content.length < 0xffffff + 0xff; i++) {
    content.add(utf8.encode("$i admin@example.com\n"));
  }

  final file = File("./generated/data/users.csv");
  await file.writeAsBytes(content.takeBytes(), mode: FileMode.writeOnly);
}
