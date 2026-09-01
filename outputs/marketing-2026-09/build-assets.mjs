import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const raw = `${root}raw/`;
const out = `${root}final/`;
fs.mkdirSync(out, { recursive: true });

const esc = (s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
const data = (name) => `data:image/png;base64,${fs.readFileSync(raw + name).toString('base64')}`;

function make({ name, source, w, h, eyebrow, lines, subline, phoneX, phoneY, phoneW, phoneH, accent = '#8B2635' }) {
  const src = data(source);
  const title = lines.map((line, i) => `<text x="72" y="${210 + i * 82}" font-family="-apple-system, BlinkMacSystemFont, Arial" font-size="70" font-weight="760" fill="#111114">${esc(line)}</text>`).join('');
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
  <svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
    <defs>
      <filter id="shadow" x="-30%" y="-20%" width="160%" height="160%"><feDropShadow dx="0" dy="28" stdDeviation="34" flood-color="#0b1830" flood-opacity=".16"/></filter>
      <clipPath id="screen"><rect x="${phoneX}" y="${phoneY}" width="${phoneW}" height="${phoneH}" rx="58"/></clipPath>
    </defs>
    <rect width="${w}" height="${h}" fill="#FAFAF8"/>
    <circle cx="${w-90}" cy="80" r="250" fill="${accent}" opacity=".08"/>
    <rect x="72" y="76" width="72" height="9" rx="5" fill="${accent}"/>
    <text x="72" y="132" font-family="-apple-system, BlinkMacSystemFont, Arial" font-size="28" font-weight="700" letter-spacing="3" fill="${accent}">${esc(eyebrow.toUpperCase())}</text>
    ${title}
    <text x="72" y="${225 + lines.length * 82}" font-family="-apple-system, BlinkMacSystemFont, Arial" font-size="30" font-weight="500" fill="#66666B">${esc(subline)}</text>
    <g filter="url(#shadow)">
      <rect x="${phoneX-12}" y="${phoneY-12}" width="${phoneW+24}" height="${phoneH+24}" rx="70" fill="#101114"/>
      <image href="${src}" x="${phoneX}" y="${phoneY}" width="${phoneW}" height="${phoneH}" preserveAspectRatio="xMidYMid slice" clip-path="url(#screen)"/>
    </g>
    <text x="72" y="${h-60}" font-family="-apple-system, BlinkMacSystemFont, Arial" font-size="27" font-weight="650" fill="#111114">Klangradar</text>
    <text x="${w-72}" y="${h-60}" text-anchor="end" font-family="-apple-system, BlinkMacSystemFont, Arial" font-size="25" fill="#77777C">Klassik in München</text>
  </svg>`;
  const svgPath = `${out}${name}.svg`;
  fs.writeFileSync(svgPath, svg);
  execFileSync('/opt/homebrew/bin/rsvg-convert', ['-w', String(w), '-h', String(h), '-o', `${out}${name}.png`, svgPath]);
}

make({ name:'appstore-01-entdecken', source:'07-premium-home-light-clean.png', w:1290, h:2796, eyebrow:'Dein Konzertabend', lines:['Münchens beste', 'Konzerte. Auf einen Blick.'], subline:'Persönlich kuratiert. Täglich aktuell.', phoneX:135, phoneY:520, phoneW:1020, phoneH:2218 });
make({ name:'appstore-02-details', source:'08-mahler-detail-light.png', w:1290, h:2796, eyebrow:'Alles an einem Ort', lines:['Programm, Besetzung', '& Tickets.'], subline:'Alle Details für deinen perfekten Konzertabend.', phoneX:135, phoneY:520, phoneW:1020, phoneH:2218, accent:'#146194' });
make({ name:'instagram-01-highlights', source:'07-premium-home-light-clean.png', w:1080, h:1350, eyebrow:'Klangradar München', lines:['Große Orchester.', 'Große Abende.'], subline:'BRSO, Münchner Philharmoniker & mehr.', phoneX:535, phoneY:405, phoneW:480, phoneH:1044 });
make({ name:'instagram-02-mahler', source:'08-mahler-detail-light.png', w:1080, h:1350, eyebrow:'Saisonhighlight', lines:['Sir Simon Rattle', 'dirigiert Mahler 2.'], subline:'Entdecken. Merken. Tickets sichern.', phoneX:535, phoneY:405, phoneW:480, phoneH:1044, accent:'#146194' });
