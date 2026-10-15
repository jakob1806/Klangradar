import { assertEquals } from "jsr:@std/assert@1";
import { extractTicketUrl } from "./extract.ts";

const start = new Date("2027-03-20T19:00:00+01:00");

Deno.test("eindeutiger Eventim-Webshop-Link", () => {
  const html = `<a href="https://www.shop.dso-berlin.de/eventim.webshop/webticket/shop?event=12640&amp;language=de">Tickets</a>`;
  assertEquals(extractTicketUrl(html, start), "https://www.shop.dso-berlin.de/eventim.webshop/webticket/shop?event=12640&language=de");
});

Deno.test("allgemeine Shop-Links werden ignoriert", () => {
  const html = `<a href="https://tickets.muenchenticket.net/shop/142">Webshop</a><a href="/service/tickets">Ticketinfos</a>`;
  assertEquals(extractTicketUrl(html, start), null);
});

Deno.test("mehrere Termine: Link neben dem passenden Datum", () => {
  const html = `<li>19.03.2027 <a href="https://tickets.muenchenticket.net/shop/142/link/event/1?language=2">Karten</a></li>
    <li>20.03.2027 <a href="https://tickets.muenchenticket.net/shop/142/link/event/2?language=2">Karten</a></li>`;
  assertEquals(extractTicketUrl(html, start), "https://tickets.muenchenticket.net/shop/142/link/event/2?language=2");
});

Deno.test("mehrere Termine ohne erkennbares Datum: kein Link", () => {
  const html = `<a href="https://x.de/shop/142/link/event/1">A</a><a href="https://x.de/shop/142/link/event/2">B</a>`;
  assertEquals(extractTicketUrl(html, start), null);
});
