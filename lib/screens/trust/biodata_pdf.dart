import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../services/buddy_service.dart';

/// Everything that goes into the PDF. Built on the device from my own data.
class BiodataPdfData {
  final String name;
  final String? gender;
  final int? age;
  final String? city;
  final List<String> languages;
  final String? about;
  final Biodata biodata;

  // Kundli basics.
  final String? moonSign;
  final String? lagna;
  final String? nakshatra;
  final bool? manglik;

  // Birth details: my own choice to include (toggle, default on).
  final bool includeBirthDetails;
  final String? birthDate;
  final String? birthTime;
  final String? birthPlace;

  /// Optional contact typed only for the PDF (never sent to the server).
  final String? contact;

  const BiodataPdfData({
    required this.name,
    this.gender,
    this.age,
    this.city,
    this.languages = const [],
    this.about,
    this.biodata = Biodata.empty,
    this.moonSign,
    this.lagna,
    this.nakshatra,
    this.manglik,
    this.includeBirthDetails = true,
    this.birthDate,
    this.birthTime,
    this.birthPlace,
    this.contact,
  });

  /// From the app's cached Kundli (BackendService.kundliData).
  static ({String? moonSign, String? lagna, String? nakshatra, bool? manglik, String? date, String? time, String? place})
      kundliBasics(Map<String, dynamic>? k) {
    if (k == null) {
      return (moonSign: null, lagna: null, nakshatra: null, manglik: null, date: null, time: null, place: null);
    }
    String? s(dynamic v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    bool? manglik;
    final planets = k['planetaryPositions'];
    if (planets is List) {
      for (final p in planets) {
        if (p is Map && '${p['name'] ?? p['planet'] ?? ''}'.split(' ').first == 'Mars') {
          final h = int.tryParse('${p['house'] ?? ''}');
          if (h != null) manglik = const [1, 2, 4, 7, 8, 12].contains(h);
        }
      }
    }
    final b = k['birthDetails'] is Map ? k['birthDetails'] as Map : const {};
    final time = s(b['timeOfBirth']);
    return (
      moonSign: s(k['moonSign']),
      lagna: s(k['ascendant']),
      nakshatra: s(k['nakshatra']),
      manglik: manglik,
      date: s(b['dateOfBirth'])?.split('T').first,
      time: time == null ? null : (time.length >= 5 ? time.substring(0, 5) : time),
      place: s(b['placeOfBirth']),
    );
  }
}

/// The built-in PDF fonts are Latin-1 only: map the few symbols we use and
/// drop anything else so generation never fails on an emoji or Hindi text.
String pdfSafe(String s) {
  final mapped = s
      .replaceAll('₹', 'Rs ')
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll('…', '...')
      .replaceAll('·', '-');
  final buf = StringBuffer();
  for (final r in mapped.runes) {
    if (r == 10 || (r >= 32 && r <= 126) || (r >= 160 && r <= 255)) buf.writeCharCode(r);
  }
  return buf.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

const _maroon = PdfColor.fromInt(0xFF7A2E0E);
const _saffron = PdfColor.fromInt(0xFFE5560A);
const _gold = PdfColor.fromInt(0xFFC8901E);
const _ink = PdfColor.fromInt(0xFF2A1D14);
const _muted = PdfColor.fromInt(0xFF7A6A5C);
const _soft = PdfColor.fromInt(0xFFFFF4EA);

pw.Widget _diamond(double size, PdfColor color) => pw.Transform.rotate(
      angle: 0.785398,
      child: pw.Container(width: size, height: size, decoration: pw.BoxDecoration(border: pw.Border.all(color: color, width: 1))),
    );

/// A neutral decorative divider (lines + diamonds, no religious imagery).
pw.Widget _ornament() => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      pw.Container(width: 70, height: 0.8, color: _gold),
      pw.SizedBox(width: 6),
      _diamond(4, _gold),
      pw.SizedBox(width: 4),
      _diamond(7, _saffron),
      pw.SizedBox(width: 4),
      _diamond(4, _gold),
      pw.SizedBox(width: 6),
      pw.Container(width: 70, height: 0.8, color: _gold),
    ]);

pw.Widget _section(String title, List<(String, String)> rows) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const pw.BoxDecoration(color: _soft, border: pw.Border(left: pw.BorderSide(color: _saffron, width: 3))),
        child: pw.Text(pdfSafe(title).toUpperCase(),
            style: const pw.TextStyle(color: _maroon, fontSize: 10.5, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
      ),
      pw.SizedBox(height: 4),
      for (final (label, value) in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 150, child: pw.Text(pdfSafe(label), style: const pw.TextStyle(color: _muted, fontSize: 10.5))),
            pw.Expanded(
              child: pw.Text(pdfSafe(value), style: const pw.TextStyle(color: _ink, fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ),
          ]),
        ),
    ]),
  );
}

/// Builds a clean A4 biodata PDF (photo-free). Pure: easy to unit test.
Future<Uint8List> buildBiodataPdf(BiodataPdfData d) async {
  final b = d.biodata;
  final personal = <(String, String)>[
    if (d.gender != null) ('Gender', d.gender!),
    if (d.age != null) ('Age', '${d.age} years'),
    if (d.includeBirthDetails && d.birthDate != null) ('Date of birth', d.birthDate!),
    if (d.includeBirthDetails && d.birthTime != null) ('Time of birth', d.birthTime!),
    if (d.includeBirthDetails && d.birthPlace != null) ('Place of birth', d.birthPlace!),
    if (d.city != null) ('Lives in', d.city!),
    ...b.personalRows,
    if (d.languages.isNotEmpty) ('Languages', d.languages.join(', ')),
  ];
  final kundli = <(String, String)>[
    if (d.moonSign != null) ('Moon sign (Rashi)', d.moonSign!),
    if (d.lagna != null) ('Lagna (Ascendant)', d.lagna!),
    if (d.nakshatra != null) ('Nakshatra', d.nakshatra!),
    if (d.manglik != null) ('Manglik', d.manglik! ? 'Yes' : 'No'),
  ];
  final family = b.familyRows;
  final contact = d.contact?.trim();

  final doc = pw.Document(title: pdfSafe('Biodata - ${d.name}'), author: 'CosmicGuide', creator: 'CosmicGuide');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(24),
    build: (ctx) => pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _maroon, width: 2)),
      padding: const pw.EdgeInsets.all(4),
      child: pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _gold, width: 0.8)),
        padding: const pw.EdgeInsets.fromLTRB(26, 22, 26, 18),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Center(
            child: pw.Text('BIODATA',
                style: const pw.TextStyle(color: _saffron, fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 4)),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(pdfSafe(d.name).isEmpty ? 'Biodata' : pdfSafe(d.name),
                style: const pw.TextStyle(color: _ink, fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          _ornament(),
          if (d.about != null && pdfSafe(d.about!).isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(pdfSafe(d.about!),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(color: _muted, fontSize: 10.5, fontStyle: pw.FontStyle.italic)),
          ],
          if (personal.isNotEmpty) _section('Personal details', personal),
          if (kundli.isNotEmpty) _section('Kundli', kundli),
          if (family.isNotEmpty) _section('Family details', family),
          if (b.partnerExpectations != null) _section('Partner expectations', [('Looking for', b.partnerExpectations!)]),
          pw.Spacer(),
          _ornament(),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(contact != null && contact.isNotEmpty ? pdfSafe('Contact: $contact') : 'Contact via CosmicGuide',
                style: const pw.TextStyle(color: _maroon, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          if (contact != null && contact.isNotEmpty)
            pw.Center(child: pw.Text('or via CosmicGuide', style: const pw.TextStyle(color: _muted, fontSize: 9))),
        ]),
      ),
    ),
  ));
  return doc.save();
}
