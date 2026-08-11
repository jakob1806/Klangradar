-- Nutzeranfrage: Fehlermeldungen sollen auch aus der nativen App möglich
-- sein, und in der Redaktion zwischen Flutter- und Native-Meldungen
-- unterschieden werden können. Default 'flutter' hält alle bisherigen
-- (vor dieser Migration eingegangenen) Meldungen korrekt eingeordnet, ohne
-- sie nachträglich anfassen zu müssen — die Flutter-App setzt das Feld ab
-- jetzt zusätzlich explizit statt sich auf den Default zu verlassen.
alter table content_reports add column platform text not null default 'flutter'
  check (platform in ('flutter', 'native'));

create index idx_content_reports_platform on content_reports(platform, status, created_at desc);
