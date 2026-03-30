-- ============================================================
-- CATERING LISTE — Supabase Schema
-- Projekt: Demo (Mehrbenutzer)
-- ============================================================
-- Ausführen in: Supabase Dashboard → SQL Editor
-- ============================================================

-- ── Alles zurücksetzen (Neustart) ──────────────────────────
DROP TABLE IF EXISTS teilnahme CASCADE;
DROP TABLE IF EXISTS personen  CASCADE;
DROP TABLE IF EXISTS lizenzen  CASCADE;
DROP FUNCTION IF EXISTS pruefe_lizenz(TEXT);

-- ── Tabelle: personen ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS personen (
  id        TEXT NOT NULL,
  name      TEXT NOT NULL,
  abteilung TEXT DEFAULT '',
  aktiv     BOOLEAN DEFAULT true,
  erstellt  TIMESTAMPTZ DEFAULT NOW(),
  user_id   UUID REFERENCES auth.users(id),
  PRIMARY KEY (id, user_id)
);

-- ── Tabelle: teilnahme ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS teilnahme (
  id         BIGSERIAL PRIMARY KEY,
  datum      DATE NOT NULL,
  person_id  TEXT NOT NULL,
  name       TEXT NOT NULL,
  abteilung  TEXT DEFAULT '',
  timestamp  TIMESTAMPTZ DEFAULT NOW(),
  anzahl     INTEGER,
  user_id    UUID REFERENCES auth.users(id),
  UNIQUE(datum, person_id, user_id)
);

-- Index für häufige Queries
CREATE INDEX IF NOT EXISTS idx_teilnahme_datum ON teilnahme(datum);
CREATE INDEX IF NOT EXISTS idx_teilnahme_person ON teilnahme(person_id);

-- ── Row Level Security ──────────────────────────────────────
ALTER TABLE personen  ENABLE ROW LEVEL SECURITY;
ALTER TABLE teilnahme ENABLE ROW LEVEL SECURITY;

-- Jeder User sieht und schreibt nur seine eigenen Zeilen
CREATE POLICY "Own: read personen"
  ON personen FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Own: write personen"
  ON personen FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Own: read teilnahme"
  ON teilnahme FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Own: write teilnahme"
  ON teilnahme FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ── Tabelle: lizenzen ──────────────────────────────────────
-- Kein direkter RLS-Zugriff — nur via pruefe_lizenz() RPC
CREATE TABLE IF NOT EXISTS lizenzen (
  schluessel   TEXT PRIMARY KEY,
  name         TEXT,                        -- z.B. "Catering ZvE 2026"
  aktiv        BOOLEAN NOT NULL DEFAULT true,
  gueltig_bis  DATE,                        -- NULL = unbefristet
  erstellt_am  TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE lizenzen ENABLE ROW LEVEL SECURITY;
-- Keine RLS-Policy → niemand kann direkt lesen/schreiben

-- ── RPC: pruefe_lizenz ─────────────────────────────────────
-- SECURITY DEFINER = läuft als postgres, umgeht RLS
-- anon-Rolle darf diese Funktion aufrufen
CREATE OR REPLACE FUNCTION pruefe_lizenz(p_schluessel TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- Rückgabewerte:
--   'UNGUELTIG'  → Schlüssel unbekannt, deaktiviert oder abgelaufen
--   'PERMANENT'  → gültig, kein Ablaufdatum
--   'YYYY-MM-DD' → gültig bis diesem Datum
DECLARE
  v_aktiv       BOOLEAN;
  v_gueltig_bis DATE;
BEGIN
  SELECT aktiv, gueltig_bis
  INTO v_aktiv, v_gueltig_bis
  FROM lizenzen
  WHERE schluessel = p_schluessel;

  IF NOT FOUND              THEN RETURN 'UNGUELTIG'; END IF;
  IF NOT v_aktiv            THEN RETURN 'UNGUELTIG'; END IF;
  IF v_gueltig_bis IS NOT NULL
     AND v_gueltig_bis < CURRENT_DATE THEN RETURN 'UNGUELTIG'; END IF;

  IF v_gueltig_bis IS NULL  THEN RETURN 'PERMANENT'; END IF;
  RETURN v_gueltig_bis::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION pruefe_lizenz TO anon;

-- ── Tabelle: demo_nutzer ────────────────────────────────────
-- Optionales Ablaufdatum pro User. Kein Eintrag = unbegrenzt.
CREATE TABLE IF NOT EXISTS demo_nutzer (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id),
  gueltig_bis DATE NOT NULL
);
ALTER TABLE demo_nutzer ENABLE ROW LEVEL SECURITY;
-- Keine RLS-Policy → kein direkter Zugriff

-- ── RPC: pruefe_demo_nutzer ─────────────────────────────────
CREATE OR REPLACE FUNCTION pruefe_demo_nutzer()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gueltig_bis DATE;
BEGIN
  SELECT gueltig_bis INTO v_gueltig_bis
  FROM demo_nutzer
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN RETURN true; END IF;
  RETURN v_gueltig_bis >= CURRENT_DATE;
END;
$$;

GRANT EXECUTE ON FUNCTION pruefe_demo_nutzer TO authenticated;

-- Demo-Lizenzschlüssel anlegen:
INSERT INTO lizenzen (schluessel, name)
VALUES ('DEMO-2026', 'Catering Demo 2026');

-- ============================================================
-- NACH TABELLEN-ANLAGE: Demo-User anlegen
-- ============================================================
-- 1. Supabase Dashboard → Authentication → Users → Add user
--    E-Mail + Passwort eingeben, "Auto Confirm User" anhaken
--
-- 2. Ablaufdatum setzen (SQL Editor):
--    INSERT INTO demo_nutzer (user_id, gueltig_bis)
--    SELECT id, CURRENT_DATE + INTERVAL '30 days'
--    FROM auth.users WHERE email = 'neuuser@example.com';
--
--    Statt '30 days' z.B. '14 days' für 2 Wochen.
--    Kein Eintrag in demo_nutzer = unbegrenzt gültig.
-- ============================================================
