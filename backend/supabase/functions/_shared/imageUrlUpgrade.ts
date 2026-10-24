// Erstellt von Claude Code (24.10.2026, Nutzermeldung "Bilder wirken
// niedriger aufgelöst"): Bild-CDNs liefern über URL-Parameter verkleinerte
// Vorschaubilder (z. B. in-muenchen.de: .../imagedelivery/<id>/<hash>/
// w=265,h=186,fit=cover). Diese auf die volle Größe umschreiben.
export function upgradeImageUrl(url: string): string {
  // Cloudflare Images: letzter Pfadteil ist die Variante/Optionen.
  if (/\/cdn-cgi\/imagedelivery\//.test(url)) {
    return url.replace(/\/(?:w|h|width|height|fit)=[^/?#]*$/, "/w=1600,fit=scale-down");
  }
  // Cloudflare Image Resizing: /cdn-cgi/image/<opts>/<origin>
  if (/\/cdn-cgi\/image\/[^/]+\//.test(url)) {
    return url.replace(/\/cdn-cgi\/image\/[^/]+\//, "/cdn-cgi/image/width=1600,fit=scale-down/");
  }
  return url;
}
