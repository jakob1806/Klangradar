#!/usr/bin/env node
/**
 * Baut eine formatierte Excel-Arbeitsmappe aus Biografien_fuer_Claude.jsonl
 * (Ausgabe von consolidate_bio_drafts.py) — eine "Anleitung"-Übersichtsseite
 * plus je eine Tabelle für alle Einträge / Venues / Personen / Ensembles.
 *
 * Portiert von einer Vorversion, die das Codex-CLI-interne, außerhalb
 * dessen Sandbox nicht verfügbare Paket "@oai/artifact-tool" nutzte — hier
 * durch das öffentlich über npm verfügbare "exceljs" ersetzt, damit das
 * Skript tatsächlich außerhalb dieser einen Umgebung lauffähig ist. Die
 * Formel-Fehler-Suche und PNG-Vorschau-Erzeugung der Vorversion (reine
 * QA-Hilfsmittel des alten Tools, kein öffentliches Äquivalent) entfallen
 * ersatzlos.
 */
import fs from "node:fs/promises";
import path from "node:path";
import ExcelJS from "exceljs";

function parseArgs(argv) {
  const args = { input: null, outDir: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--input") args.input = argv[++i];
    else if (argv[i] === "--out-dir") args.outDir = argv[++i];
  }
  return args;
}

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const { input, outDir } = parseArgs(process.argv.slice(2));
const jsonlPath = input ?? path.join(scriptDir, "Biografien_fuer_Claude.jsonl");
const outputDir = outDir ?? path.join(scriptDir, "outputs", "bio_import");

const raw = await fs.readFile(jsonlPath, "utf8");
const records = raw.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));

const NAVY = "FF1F4D78";
const BLUE = "FF2E74B5";
const PALE = "FFE8EEF5";
const WHITE = "FFFFFFFF";

const HEADERS = [
  ["kategorie", "Kategorie"], ["typ", "Typ"], ["id", "ID"], ["name", "Name"],
  ["kontext", "Kontext"], ["bestandstext", "Bestandstext"], ["ki_entwurf", "KI-Entwurf"],
  ["ki_entwurf_quelle", "KI-Entwurf-Quelle"], ["wikipedia_titel", "Wikipedia-Titel"],
  ["wikipedia_url", "Wikipedia-URL"], ["wikipedia_auszug", "Wikipedia-Auszug"],
  ["wikipedia_konfidenz", "Trefferkonfidenz"], ["status", "Status"],
];
const FINAL_TEXT_HEADER = "Finaler Text";

const workbook = new ExcelJS.Workbook();
workbook.creator = "Klassik München — bio-research";
workbook.created = new Date(0); // deterministisch statt Erstellungszeitpunkt

function addGuideSheet() {
  const sheet = workbook.addWorksheet("Anleitung", { views: [{ showGridLines: false }] });
  sheet.mergeCells("A1:B1");
  sheet.getCell("A1").value = "Biografien für Claude – Recherche- und Importpaket";
  sheet.getCell("A1").font = { bold: true, size: 18, color: { argb: WHITE } };
  sheet.getCell("A1").fill = { type: "pattern", pattern: "solid", fgColor: { argb: NAVY } };
  sheet.getRow(1).height = 34;

  const rows = [
    ["Zweck", `Alle ${records.length} Veranstaltungsorte, Personen und Ensembles sind mit stabiler Datenbank-ID enthalten.`],
    ["Empfohlener Ablauf", "Nach Kategorie oder Status bearbeiten und den fertigen Text in der Spalte 'Finaler Text' eintragen."],
    ["Ziellänge", "5–8 Sätze bzw. etwa 700–1.100 Zeichen pro Eintrag."],
    ["Quellen", "Wikipedia-Links und kurze Quellenhinweise dienen der Zuordnung. Treffer mit niedriger Konfidenz müssen manuell geprüft werden."],
    ["KI-Entwürfe", "Vorhandene Entwürfe sind Arbeitsfassungen und müssen redaktionell auf Namensgleichheit, Aktualität und Fakten geprüft werden — sie werden NIE automatisch dem Bestandstext vorgezogen (siehe README)."],
    ["Import", "Für eine technische Weiterverarbeitung stehen zusätzlich UTF-8-CSV und JSONL mit denselben IDs bereit."],
  ];
  rows.forEach((row, i) => {
    const r = sheet.getRow(i + 3);
    r.getCell(1).value = row[0];
    r.getCell(1).font = { bold: true, color: { argb: NAVY } };
    r.getCell(1).fill = { type: "pattern", pattern: "solid", fgColor: { argb: PALE } };
    r.getCell(2).value = row[1];
    r.getCell(2).alignment = { wrapText: true, vertical: "top" };
    r.getCell(1).alignment = { wrapText: true, vertical: "top" };
    r.height = 42;
  });
  sheet.getColumn(1).width = 24;
  sheet.getColumn(2).width = 105;
  sheet.views = [{ state: "frozen", ySplit: 1 }];
  return sheet;
}

function addDataSheet(name, data) {
  const sheet = workbook.addWorksheet(name, { views: [{ showGridLines: false }] });
  const headerRow = sheet.getRow(1);
  HEADERS.forEach(([, label], i) => {
    headerRow.getCell(i + 1).value = label;
  });
  headerRow.getCell(HEADERS.length + 1).value = FINAL_TEXT_HEADER;
  headerRow.eachCell((cell) => {
    cell.font = { bold: true, color: { argb: WHITE }, size: 10 };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: BLUE } };
    cell.alignment = { wrapText: true, vertical: "middle" };
  });
  headerRow.height = 32;

  data.forEach((record, rowIdx) => {
    const row = sheet.getRow(rowIdx + 2);
    HEADERS.forEach(([key], colIdx) => {
      row.getCell(colIdx + 1).value = record[key] ?? "";
    });
    row.getCell(HEADERS.length + 1).value = "";
    row.eachCell((cell) => {
      cell.font = { size: 10, color: { argb: "FF222222" } };
      cell.alignment = { ...cell.alignment, vertical: "top", wrapText: true };
    });
  });

  const widths = [18, 12, 38, 30, 28, 48, 60, 18, 30, 42, 60, 18, 34, 68];
  widths.forEach((w, i) => (sheet.getColumn(i + 1).width = w));
  sheet.views = [{ state: "frozen", ySplit: 1, xSplit: 4 }];
  if (data.length) {
    sheet.autoFilter = { from: "A1", to: `${sheet.getColumn(HEADERS.length + 1).letter}${data.length + 1}` };
  }
  return sheet;
}

addGuideSheet();
addDataSheet("Alle Einträge", records);
addDataSheet("Veranstaltungsorte", records.filter((r) => r.typ === "venue"));
addDataSheet("Personen", records.filter((r) => r.typ === "person"));
addDataSheet("Ensembles", records.filter((r) => r.typ === "ensemble"));

await fs.mkdir(outputDir, { recursive: true });
const outputPath = path.join(outputDir, "Biografien_fuer_Claude.xlsx");
await workbook.xlsx.writeFile(outputPath);

console.log(JSON.stringify({ outputPath, records: records.length }));
