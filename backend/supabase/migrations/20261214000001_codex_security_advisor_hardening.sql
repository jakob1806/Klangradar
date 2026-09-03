-- Created by ChatGPT Codex
-- Security Advisor hardening: make public API views obey the caller's RLS
-- context. public.spatial_ref_sys is owned by the managed PostGIS extension;
-- project migrations intentionally do not mutate that provider-owned object.

alter view public.events_today
  set (security_invoker = true);

alter view public.events_this_weekend
  set (security_invoker = true);

alter view public.events_free
  set (security_invoker = true);

alter view public.city_regions
  set (security_invoker = true);

alter view public.venues_in_city_region
  set (security_invoker = true);

notify pgrst, 'reload schema';
