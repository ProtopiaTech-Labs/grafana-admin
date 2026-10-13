-- Modul 4: rozklad adnotacji na klasy retencji (PostgreSQL, baza Grafany).
-- Bez dostepu do bazy (np. Lab wspolny: Azure PostgreSQL) ten sam rozklad liczy przez API 04-annotation-klasy.sh.
SELECT CASE WHEN alert_id <> 0 THEN 'alert'
            WHEN dashboard_id <> 0 THEN 'dashboard'
            ELSE 'organization' END AS klasa,
       count(*),
       to_timestamp(min(created) / 1000) AS najstarsza,
       to_timestamp(max(created) / 1000) AS najnowsza
FROM annotation
GROUP BY 1
ORDER BY 1;
