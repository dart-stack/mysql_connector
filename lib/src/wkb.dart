import 'dart:typed_data';

import 'package:mysql_connector/src/utils.dart';

sealed class WkbGeometry {}

class Point {
  final double coordX;

  final double coordY;

  const Point(this.coordX, this.coordY);

  @override
  String toString() {
    return "Point($coordX, $coordY)";
  }
}

class LinearRing {
  final List<Point> points;

  const LinearRing(this.points);

  @override
  String toString() {
    return "LinearRing($points)";
  }
}

final class WkbPoint implements WkbGeometry {
  final Point point;

  const WkbPoint(this.point);

  double get coordX => point.coordX;

  double get coordY => point.coordY;

  @override
  String toString() {
    return "WbkPoint($coordX, $coordY)";
  }
}

final class WkbLineString implements WkbGeometry {
  final List<Point> points;

  const WkbLineString(this.points);

  @override
  String toString() {
    return "WkbLineString($points)";
  }
}

final class WkbPolygon implements WkbGeometry {
  final List<LinearRing> rings;

  const WkbPolygon(this.rings);

  @override
  String toString() {
    return "WkbPolygon($rings)";
  }
}

final class WkbMultiPoint implements WkbGeometry {
  final List<WkbPoint> points;

  const WkbMultiPoint(this.points);

  @override
  String toString() {
    return "WkbMultiPoint($points)";
  }
}

final class WkbMultiLineString implements WkbGeometry {
  final List<WkbLineString> lineStrings;

  const WkbMultiLineString(this.lineStrings);

  @override
  String toString() {
    return "WkbMultiLineString($lineStrings)";
  }
}

final class WkbMultiPolygon implements WkbGeometry {
  final List<WkbPolygon> polygons;

  const WkbMultiPolygon(this.polygons);

  @override
  String toString() {
    return "WkbMultiPolygon($polygons)";
  }
}

final class WkbGeometryCollection implements WkbGeometry {
  final List<WkbGeometry> geometries;

  const WkbGeometryCollection(this.geometries);

  @override
  String toString() {
    return "WkbGeometryCollection($geometries)";
  }
}

Point _parsePoint(
  List<int> buffer,
  Endian endian, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();
  final coordX = (ByteData(8)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3])
        ..setUint8(4, buffer[cursor.position + 4])
        ..setUint8(5, buffer[cursor.position + 5])
        ..setUint8(6, buffer[cursor.position + 6])
        ..setUint8(7, buffer[cursor.position + 7]))
      .getFloat64(0, endian);
  final coordY = (ByteData(8)
        ..setUint8(0, buffer[cursor.position + 8])
        ..setUint8(1, buffer[cursor.position + 9])
        ..setUint8(2, buffer[cursor.position + 10])
        ..setUint8(3, buffer[cursor.position + 11])
        ..setUint8(4, buffer[cursor.position + 12])
        ..setUint8(5, buffer[cursor.position + 13])
        ..setUint8(6, buffer[cursor.position + 14])
        ..setUint8(7, buffer[cursor.position + 15]))
      .getFloat64(0, endian);
  cursor.increment(16);
  return Point(coordX, coordY);
}

LinearRing _parseLinearRing(
  List<int> buffer,
  Endian endian, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();
  final numPoints = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final points = <Point>[];
  for (int i = 0; i < numPoints; i++) {
    points.add(_parsePoint(buffer, endian, cursor));
  }
  return LinearRing(points);
}

Endian _parseEndian(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  return buffer[cursor.getAndIncrement(1)] == 0x00 ? Endian.big : Endian.little;
}

int _parseWkbType(List<int> buffer, Endian endian, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final wkbType = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  return wkbType;
}

WkbPoint parseWkbPoint(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 1);
  return WkbPoint(_parsePoint(buffer, endian, cursor));
}

WkbLineString parseWkbLineString(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 2);
  final numPoints = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final points = <Point>[];
  for (int i = 0; i < numPoints; i++) {
    points.add(_parsePoint(buffer, endian, cursor));
  }
  return WkbLineString(points);
}

WkbPolygon parseWkbPolygon(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 3);
  final numRings = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final rings = <LinearRing>[];
  for (int i = 0; i < numRings; i++) {
    rings.add(_parseLinearRing(buffer, endian, cursor));
  }
  return WkbPolygon(rings);
}

WkbMultiPoint parseWkbMultiPoint(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 4);
  final numWkbPoints = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final points = <WkbPoint>[];
  for (int i = 0; i < numWkbPoints; i++) {
    points.add(parseWkbPoint(buffer, cursor));
  }
  return WkbMultiPoint(points);
}

WkbMultiLineString parseWkbMultiLineString(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 5);
  final numWkbLineStrings = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final points = <WkbLineString>[];
  for (int i = 0; i < numWkbLineStrings; i++) {
    points.add(parseWkbLineString(buffer, cursor));
  }
  return WkbMultiLineString(points);
}

WkbMultiPolygon parseWkbMultiPolygon(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 6);
  final numWkbPolygons = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final polygons = <WkbPolygon>[];
  for (int i = 0; i < numWkbPolygons; i++) {
    polygons.add(parseWkbPolygon(buffer, cursor));
  }
  return WkbMultiPolygon(polygons);
}

WkbGeometryCollection parseWkbGeometryCollection(
  List<int> buffer, [
  Cursor? cursor,
]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  assert(wkbType == 7);
  final numWkbGeometries = (ByteData(4)
        ..setUint8(0, buffer[cursor.position + 0])
        ..setUint8(1, buffer[cursor.position + 1])
        ..setUint8(2, buffer[cursor.position + 2])
        ..setUint8(3, buffer[cursor.position + 3]))
      .getUint32(0, endian);
  cursor.increment(4);
  final geometries = <WkbGeometry>[];
  for (int i = 0; i < numWkbGeometries; i++) {
    geometries.add(parseWkbGeometry(buffer, cursor));
  }
  return WkbGeometryCollection(geometries);
}

WkbGeometry parseWkbGeometry(List<int> buffer, [Cursor? cursor]) {
  cursor ??= Cursor.zero();
  final endian = _parseEndian(buffer, cursor);
  final wkbType = _parseWkbType(buffer, endian, cursor);
  cursor.increment(-5);

  switch (wkbType) {
    case 1:
      return parseWkbPoint(buffer, cursor);
    case 2:
      return parseWkbLineString(buffer, cursor);
    case 3:
      return parseWkbPolygon(buffer, cursor);
    case 4:
      return parseWkbMultiPoint(buffer, cursor);
    case 5:
      return parseWkbMultiLineString(buffer, cursor);
    case 6:
      return parseWkbMultiPolygon(buffer, cursor);
    case 7:
      return parseWkbGeometryCollection(buffer, cursor);
    default:
      throw UnsupportedError("unrecognized wkb type $wkbType");
  }
}
