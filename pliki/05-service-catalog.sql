-- Moduł 5: katalog usług i polityka SLO dla ćwiczeń 05 i 07.
--
-- Lab wspólny wykonuje ten plik przy każdym starcie PostgreSQL-a OTel Demo (baza bez wolumenu).
-- Wykonuje go superuser, dlatego na końcu są GRANT-y dla użytkownika datasource'a
-- `PostgreSQL` (otelu): tylko odczyt. Plik jest idempotentny.

\c otel

CREATE SCHEMA IF NOT EXISTS training;

CREATE TABLE IF NOT EXISTS training.service_catalog (
  service     TEXT PRIMARY KEY,          -- = label service_name w traces_spanmetrics_*
  team        TEXT NOT NULL,
  tier        TEXT NOT NULL CHECK (tier IN ('critical', 'standard', 'best-effort')),
  slo_target  NUMERIC(6,5) NOT NULL,     -- cel dostępności, np. 0.995
  oncall      TEXT NOT NULL,
  language    TEXT
);

CREATE TABLE IF NOT EXISTS training.slo_policy (
  tier        TEXT PRIMARY KEY,
  warn_ratio  NUMERIC(6,5) NOT NULL,     -- próg ostrzegawczy error ratio
  crit_ratio  NUMERIC(6,5) NOT NULL      -- próg krytyczny error ratio
);

INSERT INTO training.service_catalog (service, team, tier, slo_target, oncall, language) VALUES
  ('frontend-proxy',  'platform',      'critical',    0.999, 'platform-oncall',  'C++ (Envoy)'),
  ('frontend',        'web',           'critical',    0.995, 'web-oncall',       'TypeScript'),
  ('checkout',        'orders',        'critical',    0.995, 'orders-oncall',    'Go'),
  ('cart',            'orders',        'critical',    0.995, 'orders-oncall',    'C#'),
  ('payment',         'payments',      'critical',    0.999, 'payments-oncall',  'JavaScript'),
  ('product-catalog', 'catalog',       'critical',    0.995, 'catalog-oncall',   'Go'),
  ('currency',        'payments',      'standard',    0.990, 'payments-oncall',  'C++'),
  ('accounting',      'payments',      'standard',    0.990, 'payments-oncall',  '.NET'),
  ('fraud-detection', 'payments',      'standard',    0.990, 'payments-oncall',  'Kotlin'),
  ('shipping',        'logistics',     'standard',    0.990, 'logistics-oncall', 'Rust'),
  ('recommendation',  'catalog',       'standard',    0.990, 'catalog-oncall',   'Python'),
  ('product-reviews', 'catalog',       'standard',    0.990, 'catalog-oncall',   'Python'),
  ('flagd',           'platform',      'standard',    0.990, 'platform-oncall',  'Go'),
  ('ad',              'marketing',     'best-effort', 0.950, 'marketing-oncall', 'Java'),
  ('email',           'notifications', 'best-effort', 0.950, 'notif-oncall',     'Ruby'),
  ('image-provider',  'web',           'best-effort', 0.950, 'web-oncall',       'nginx'),
  ('llm',             'catalog',       'best-effort', 0.950, 'catalog-oncall',   'Python'),
  ('legacy-billing',  'payments',      'standard',    0.990, 'payments-oncall',  'COBOL')   -- celowo: usługi nie ma w labie (anti-join)
  -- 'quote' celowo pominięta: w LEFT JOIN wychodzi jako "(brak właściciela)"
ON CONFLICT (service) DO NOTHING;

INSERT INTO training.slo_policy (tier, warn_ratio, crit_ratio) VALUES
  ('critical',    0.001, 0.005),
  ('standard',    0.010, 0.020),
  ('best-effort', 0.050, 0.100)
ON CONFLICT (tier) DO NOTHING;

-- Datasource `PostgreSQL` loguje się jako otelu: tylko odczyt schematu training.
GRANT USAGE ON SCHEMA training TO otelu;
GRANT SELECT ON ALL TABLES IN SCHEMA training TO otelu;
