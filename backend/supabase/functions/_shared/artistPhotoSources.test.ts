// Ausschnitte der echten Seiten, abgerufen am 02.11.2026.
import { assertEquals } from "jsr:@std/assert@1";
import {
  parseBerlinerPhilDetail,
  parseGaertnerplatzRoster,
  parseMaestroDetail,
  parseMphilDetail,
  parseMphilList,
  parseNdrRoster,
} from "./artistPhotoSources.ts";

Deno.test("Gärtnerplatz: Name aus alt, Fotograf aus Dateiname", () => {
  const html = `<img src="https://www.gaertnerplatztheater.de/uploads/Foto_Video_Galerien/markus_tordik_2/Berg_cMarkusTordik.jpg?449_674" alt="Portrait Frank Berg" class="img-fluid"/>`;
  const [p] = parseGaertnerplatzRoster(html, "https://www.gaertnerplatztheater.de/de/ensemble/solistinnen-und-solisten.html");
  assertEquals([p.name, p.credit], ["Frank Berg", "© Markus Tordik"]);
});

Deno.test("MPhil: Liste und Credit im Bildpfad", () => {
  const list = `<h2 class="h4"> <a href="/ueber-uns/musikerinnen-und-musiker/details/valentin-eichler"> Valentin Eichler </a> </h2>`;
  assertEquals(parseMphilList(list)[0].name, "Valentin Eichler");
  const detail = `<meta property="og:image" content="https://www.mphil.de/fileadmin/Redaktion-mphil/Orchester/credit_Co_Merz/Lahav_Shani_credit_Co_Merz.jpg">`;
  assertEquals(parseMphilDetail(detail, "x", "Lahav Shani")?.credit, "© Co Merz");
  assertEquals(parseMphilDetail(`<meta property="og:image" content="https://www.mphil.de/fileadmin/x/foto.jpg">`, "x", "N N"), null);
});

Deno.test("Berliner Philharmoniker: Credit aus Dateiname, Name aus Titel", () => {
  const html = `<title>Albrecht Mayer | Berliner Philharmoniker</title><meta property="og:image" content="https://www.berliner-philharmoniker.de/fileadmin/_processed_/8/f/csm_BPH_Mayer-Albrecht_c_Hoederath_32095_Y_1169ba1087.jpg">`;
  const p = parseBerlinerPhilDetail(html, "x", "Albrecht Mayer");
  assertEquals([p?.name, p?.credit], ["Albrecht Mayer", "© Hoederath"]);
});

Deno.test("Maestro Arts: Galerie-Original und Credit", () => {
  const html = `<a href="//maestro-arts-production.s3.amazonaws.com/media/Artists/Adam-Walker/ADAM-WALKER-by-Christa-Holka-15May18-0185.jpg">x</a><span>
      © Christa Holka
  </span>`;
  const p = parseMaestroDetail(html, "x", "Adam Walker");
  assertEquals(p?.credit, "© Christa Holka");
  assertEquals(p?.imageUrl.startsWith("https://maestro-arts-production"), true);
});

Deno.test("NDR: Name aus alt, Fotograf aus title", () => {
  const html = `<img src="https://images.ndr.de/image/ed19594e/AAABkXDBJ8E/AAABnSSvrFg/16x9-big/ruxandraklein104.webp?width=576" alt="Ruxandra Klein, Stellvertretende Konzertmeisterin des NDR Elbphilharmonie Orchesters" title="Ruxandra Klein, Stellvertretende Konzertmeisterin des NDR Elbphilharmonie Orchesters | NDR, Jewgeni Roppel, Jewgeni Roppel" class="responsive" loading="lazy" />`;
  const [p] = parseNdrRoster(html, "x");
  assertEquals([p.name, p.credit], ["Ruxandra Klein", "© NDR / Jewgeni Roppel"]);
});
