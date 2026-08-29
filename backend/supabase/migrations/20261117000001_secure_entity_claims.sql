-- Jede Claim-Anfrage braucht einen überprüfbaren Kontakt und einen Nachweis.
alter table entity_claims
  add column if not exists verification_email text,
  add column if not exists evidence_url text;

-- Eine neue Institution erhält Verwaltungsrechte erst nach Redaktionsprüfung.
drop policy if exists "Ersteller-Claim auf eigene neue Institution ist sofort genehmigt" on entity_claims;
