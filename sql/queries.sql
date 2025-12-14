USE `tenisdb`;

-- 5.- Consultas (1.5 puntos)

-- Fecha y duración de los partidos decididos en 2 sets.
SELECT
	m.match_date,
	m.duration
FROM matches m
JOIN sets s ON (s.match_id = m.match_id)
GROUP BY m.match_date, m.duration
HAVING COUNT(*) = 2
ORDER BY match_date
;

-- Lista de árbitros ordenados por número de partidos arbitrados, incluyendo el número de partidos arbitrados por cada árbitro.
SELECT 
	p.`name`,
	COUNT(*) AS matches_refereed                    -- COUNT (*) CON EL ESPACIO EN BLANCO DA ERROR, QUITAR ESPACIO EN BLANCO
FROM matches m
JOIN referees r ON (m.referee_id = r.referee_id)
JOIN people p ON (p.person_id = r.referee_id)
GROUP BY p.name
ORDER BY matches_refereed DESC
;