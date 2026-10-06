import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'db.dart';
import 'models.dart';

const _thumbPx = 240;
const _headerBg = PdfColor.fromInt(0xFFEEEAF7); // wrzos
const _sumBg = PdfColor.fromInt(0xFFF8F6FB);
const _border = PdfColor.fromInt(0xFFDDDDDD);

/// Miniatury JPEG w tle, żeby nie zamrozić UI przy wielu zdjęciach.
Future<Map<String, Uint8List>> _thumbs(List<String> paths) => Isolate.run(() {
      final out = <String, Uint8List>{};
      for (final p in paths) {
        final f = File(p);
        if (!f.existsSync()) continue;
        final im = img.decodeImage(f.readAsBytesSync());
        if (im == null) continue;
        out[p] = img.encodeJpg(img.copyResize(im, width: _thumbPx), quality: 70);
      }
      return out;
    });

Future<Uint8List> buildReport(DateTime from, DateTime to, List<Entry> entries, Values norms) async {
  final base = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
  final thumbs = await _thumbs([for (final e in entries) if (e.photo != null) Db.photoFile(e.photo!).path]);
  final days = byDay(entries);
  final range = '${DateFormat('d MMMM y').format(from)} – ${DateFormat('d MMMM y').format(to)}';

  final doc = pw.Document(
    title: 'Dzienniczek żywieniowy $range',
    theme: pw.ThemeData.withFont(base: base, bold: bold).copyWith(defaultTextStyle: pw.TextStyle(font: base, fontSize: 8)),
  );

  const short = ['kcal', 'Białko', 'Tłuszcz', 'nasyc.', 'Węgl.', 'cukry', 'Błonnik', 'Sól']; // kolejność jak `nutrients`
  const cols = ['Godz.', '', 'Posiłek', ...short];
  final colWidths = {
    0: const pw.FixedColumnWidth(28),
    1: const pw.FixedColumnWidth(40),
    2: const pw.FlexColumnWidth(),
    for (var i = 3; i < cols.length; i++) i: const pw.FixedColumnWidth(38),
  };

  pw.Widget cell(String t, {bool b = false, pw.TextAlign align = pw.TextAlign.right}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(t, textAlign: align, style: b ? pw.TextStyle(font: bold) : null),
      );

  List<pw.Widget> valueCells(Values v, {bool b = false}) => [for (final n in nutrients) cell(fmtNum(v[n.key]!), b: b)];
  List<pw.Widget> pctCells(Values v) => [for (final n in nutrients) cell('${(v[n.key]! / norms[n.key]! * 100).round()}%')];

  pw.TableRow sumRow(String label, List<pw.Widget> cells, PdfColor bg, {bool b = true}) => pw.TableRow(
        decoration: pw.BoxDecoration(color: bg),
        verticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [cell(''), cell(''), cell(label, b: b, align: pw.TextAlign.left), ...cells],
      );

  pw.Widget dayTable(List<Entry> list) {
    final total = sumValues(list.map((e) => e.values));
    return pw.Table(
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _border, width: .5)),
      columnWidths: colWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerBg),
          children: [for (final c in cols) cell(c, b: true, align: c == 'Posiłek' ? pw.TextAlign.left : pw.TextAlign.right)],
        ),
        for (final e in list)
          pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.middle, children: [
            cell(DateFormat('HH:mm').format(e.eatenAt), align: pw.TextAlign.left),
            pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: e.photo != null && thumbs[Db.photoFile(e.photo!).path] != null
                  ? pw.ClipRRect(
                      horizontalRadius: 3,
                      verticalRadius: 3,
                      child: pw.Image(pw.MemoryImage(thumbs[Db.photoFile(e.photo!).path]!),
                          width: 36, height: 36, fit: pw.BoxFit.cover))
                  : pw.SizedBox(width: 36, height: 12),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(e.name, style: pw.TextStyle(font: bold)),
                pw.Text([e.mealType.label, if (e.portion.isNotEmpty) e.portion].join(' · '),
                    style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 7)),
                if (e.description != null)
                  pw.Text(e.description!, style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 7)),
              ]),
            ),
            ...valueCells(e.values),
          ]),
        sumRow('Suma dnia', valueCells(total, b: true), _sumBg),
        sumRow('% dziennej normy', pctCells(total), _sumBg, b: false),
      ],
    );
  }

  final avg = dailyAverage(entries);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Dzienniczek żywieniowy', style: pw.TextStyle(font: bold, fontSize: 14)),
        pw.Text(range, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ]),
    ),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Wartości szacunkowe (AI na podstawie zdjęć i opisów). Masy w g, energia w kcal.',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      pw.Text('Strona ${ctx.pageNumber} z ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
    build: (ctx) => [
      for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(toBeginningOfSentenceCase(DateFormat('EEEE, d MMMM y').format(d))!,
              style: pw.TextStyle(font: bold, fontSize: 11)),
        ),
        days[d] == null
            ? pw.Text('Brak wpisów', style: const pw.TextStyle(color: PdfColors.grey600))
            : dayTable(days[d]!),
      ],
      pw.SizedBox(height: 16),
      pw.Text('Podsumowanie okresu', style: pw.TextStyle(font: bold, fontSize: 12)),
      pw.SizedBox(height: 4),
      pw.Text('Dni z wpisami: ${days.length} · liczba wpisów: ${entries.length}'),
      pw.SizedBox(height: 6),
      pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _border, width: .5)),
        columnWidths: {0: const pw.FlexColumnWidth(), for (var i = 1; i <= nutrients.length; i++) i: const pw.FixedColumnWidth(52)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _headerBg),
            children: [cell(''), for (var i = 0; i < nutrients.length; i++) cell('${short[i]} [${nutrients[i].unit}]', b: true)],
          ),
          pw.TableRow(children: [cell('Średnio dziennie', b: true, align: pw.TextAlign.left), ...valueCells(avg, b: true)]),
          pw.TableRow(children: [
            cell('Dzienna norma', align: pw.TextAlign.left),
            for (final n in nutrients) cell(fmtNum(norms[n.key]!)),
          ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _sumBg),
            children: [cell('% normy (średnio)', align: pw.TextAlign.left), ...pctCells(avg)],
          ),
        ],
      ),
    ],
  ));
  return doc.save();
}
