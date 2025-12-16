-- 
-- Autor: David Ruiz
-- Fecha: Noviembre 2025
-- Descripción: Tests de aceptación para Tenis usando PROCEDIMIENTOS (compatibles con HeidiSQL)
-- Filosofía: similar a 'ejemplo_tests_procedimientos.sql' (Bodegas)
-- 

USE tenisdb;

-- =============================================================
-- TABLA DE RESULTADOS DE TESTS
-- =============================================================
CREATE OR REPLACE TABLE test_results (
    test_id VARCHAR(20) NOT NULL PRIMARY KEY,
    test_name VARCHAR(200) NOT NULL,
    test_message VARCHAR(500) NOT NULL,
    test_status ENUM('PASS','FAIL','ERROR') NOT NULL,
    execution_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================
-- PROCEDIMIENTO AUXILIAR DE LOGGING
-- =============================================================
DELIMITER //
CREATE OR REPLACE PROCEDURE p_log_test(
    IN p_test_id VARCHAR(20),
    IN p_message VARCHAR(500),
    IN p_status ENUM('PASS','FAIL','ERROR')
)
BEGIN
    INSERT INTO test_results(test_id, test_name, test_message, test_status)
    VALUES (p_test_id, SUBSTRING_INDEX(p_message, ':', 1), p_message, p_status);
END //
DELIMITER ;

-- Nota: p_populate_db() se define en populateDB.sql y debe ejecutarse antes (HeidiSQL: abrir y ejecutar ese archivo).

-- =============================================================
-- TESTS
-- =============================================================

-- RN-02: Mayoría de edad
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn02_adult_age()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-02', 'RN-02: No se permiten personas menores de 18 años', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (name, age, nationality) VALUES ('Young Player', 17, 'España');
    CALL p_log_test('RN-02', 'ERROR: Se insertó una persona menor de edad', 'FAIL');
END //
DELIMITER ;

-- RN-03: Nombre único en people
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn03_unique_name()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-03', 'RN-03: No se permiten nombres duplicados', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (name, age, nationality) VALUES ('Novak Djokovic', 35, 'Serbia');
    CALL p_log_test('RN-03', 'ERROR: Se permitió un nombre duplicado', 'FAIL');
END //
DELIMITER ;

-- RN-04: Ranking válido (1..1000)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn04_invalid_ranking()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-04a', 'RN-04: No se permite ranking > 1000', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (person_id, name, age, nationality) VALUES (100, 'Test Player', 25, 'Argentina');
    INSERT INTO players (player_id, ranking) VALUES (100, 1500);
    CALL p_log_test('RN-04a', 'ERROR: Se permitió ranking > 1000', 'FAIL');
END //
DELIMITER ;

DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn04_zero_ranking()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-04b', 'RN-04: No se permite ranking <= 0', 'PASS');

    CALL p_populate_db();
    INSERT INTO people (person_id, name, age, nationality) VALUES (101, 'Test Player 2', 25, 'Chile');
    INSERT INTO players (player_id, ranking) VALUES (101, 0);
    CALL p_log_test('RN-04b', 'ERROR: Se permitió ranking <= 0', 'FAIL');
END //
DELIMITER ;

-- RN-05: Jugadores distintos en un partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn05_same_player()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-05', 'RN-05: Un jugador no puede jugar contra sí mismo', 'PASS');

    CALL p_populate_db();
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (8, 1, 1, 1, 'Test Tournament', '2024-12-01', 'Final', 120);
    CALL p_log_test('RN-05', 'ERROR: Se creó un partido con el mismo jugador en ambos lados', 'FAIL');
END //
DELIMITER ;

-- RN-06: Maximum 3 matches/day per referee
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn06_max_matches_referee()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-06', 'RN-06: No se permite un 4.º partido del mismo árbitro en el mismo día', 'PASS');

    CALL p_populate_db();
    -- Crear 3 partidos para el árbitro 8 en el mismo día
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration) VALUES
        (8, 1, 3, 1, 'Test T1', '2025-01-15', 'R1', 120),
        (8, 2, 4, 2, 'Test T2', '2025-01-15', 'R2', 130),
        (8, 5, 6, 5, 'Test T3', '2025-01-15', 'R3', 140);
    -- Intentar el 4º
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (8, 1, 2, 1, 'Test T4', '2025-01-15', 'R4', 110);
    CALL p_log_test('RN-06', 'ERROR: Se permitió un 4.º partido el mismo día para el árbitro', 'FAIL');
END //
DELIMITER ;

-- RN-07: Nacionalidad del árbitro ≠ jugadores
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_rn07_referee_nationality()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RN-07', 'RN-07: El árbitro no puede compartir nacionalidad con los jugadores', 'PASS');

    CALL p_populate_db();
    -- Árbitro 7 (España) con jugador 2 (España)
    INSERT INTO matches (referee_id, player1_id, player2_id, winner_id, tournament, match_date, round, duration)
    VALUES (7, 2, 3, 2, 'Test Tournament', '2025-02-01', 'Final', 150);
    CALL p_log_test('RN-07', 'ERROR: Se permitió árbitro con la misma nacionalidad que un jugador', 'FAIL');
END //
DELIMITER ;

-- Sets: El ganador debe ser participante del partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_sets_invalid_winner()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('SET-1', 'Sets: El ganador del set debe ser participante del partido', 'PASS');

    CALL p_populate_db();
    -- Partido 1: jugadores 1 y 2, intentar ganador 3
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES (1, 3, 4, '6-4');
    CALL p_log_test('SET-1', 'ERROR: Se permitió ganador de set no participante', 'FAIL');
END //
DELIMITER ;

-- Sets: Máximo 5 sets por partido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_sets_max_5_sets()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('SET-2', 'Sets: No se permiten más de 5 sets por partido', 'PASS');

    CALL p_populate_db();
    -- El partido 1 ya tiene 3 sets, añadir 2 (límite) y luego intentar el 6º
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES
        (1, 1, 4, '6-4'),
        (1, 2, 5, '7-5');
    -- 6th set
    INSERT INTO sets (match_id, winner_id, set_order, score) VALUES (1, 1, 6, '6-3');
    CALL p_log_test('SET-2', 'ERROR: Se permitió más de 5 sets en un partido', 'FAIL');
END //
DELIMITER ;

-- RA-02: Un entrenador no puede entrenar a más de dos tenistas a la vez
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ra02_max_players_a_trainer_has()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RA-02', 'RA-02: Un entrenador no puede entrenar a más de dos tenistas a la vez', 'PASS');

    CALL p_populate_db();
    -- Crear un entrenador
	 INSERT INTO trainers (trainer_id, experience, speciality) VALUES
        (19, 15, 'Individual');
    -- Insertar a players a dos peronas cuyo entrenador_id = 19
    INSERT INTO players (player_id, ranking, active, trainer_id) VALUES 
        (20, 12, TRUE, 19),
        (21, 13, TRUE, 19);
    -- Insertar el tercero
    INSERT INTO players (player_id, ranking, active, trainer_id) VALUES
        (22, 14, TRUE, 19);
    CALL p_log_test('RA-02', 'ERROR: Se permitió un 3.º tenista para un entrenador', 'FAIL');
END //
DELIMITER ;

-- F1: Dado un tenista y un partido, realice una función que devuelva el número de sets ganados por ese tenista en ese partido 
-- (devolver tabla con [match_id, player1, sets_won_p1, player2, sets_won_p2] que recoja todos los sets jugados y los agrupe por match_id)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_f1_sets_won_by_player()
BEGIN
    -- Se popula la base de datos para tener los datos de prueba
    CALL p_populate_db();

    -- Se realiza la consulta solicitada usando la función F1
    SELECT 
        m.match_id,
        p1.name AS player1,
        f1_sets_won_by_player_in_match(m.player1_id, m.match_id) AS sets_won_p1,
        p2.name AS player2,
        f1_sets_won_by_player_in_match(m.player2_id, m.match_id) AS sets_won_p2
    FROM matches m
    JOIN people p1 ON m.player1_id = p1.person_id
    JOIN people p2 ON m.player2_id = p2.person_id
    ORDER BY m.match_id;
END //
DELIMITER ;

-- T1.1: Test de transacción con los datos introducidos CORRECTOS

DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_t1_valid()
BEGIN
	 DECLARE EXIT HANDLER FOR SQLEXCEPTION
	     CALL p_log_test('T-1.1', 'ERROR: Rollback de transacción con datos correctos', 'FAIL');
    -- Se popula la base de datos para tener los datos de prueba
    CALL p_populate_db();

    -- Se realiza la transacción usando el proccedimiento (los dos tenistas correctos)
	 CALL create2Trainers(
	 23,
	 'Pepe Viyuela',
	 55,
	 'España',
	 5,
	 'Individual',
	 24,
	 'Puff Daddy',
	 33,
	 'Estados Unidos',
	 10,
	 'Dobles'
	 );
	 CALL p_log_test('T-1.1', 'Transacción: Se han añadido datos correctos', 'PASS');
END //
DELIMITER ;

-- T1.2: Test de transacción con los datos introducidos INCORRECTOS

DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_t1_invalid()
BEGIN
	 DECLARE EXIT HANDLER FOR SQLEXCEPTION
	     CALL p_log_test('T-1.2', 'Transacción: Rollback de transacción con datos incorrectos', 'PASS');
    -- Se popula la base de datos para tener los datos de prueba
    CALL p_populate_db();

    -- Se realiza la transacción usando el proccedimiento (primer trainer bien, segundo trainer mal)
	 CALL create2Trainers(
	 23,
	 'Pepe Viyuela',
	 55,
	 'España',
	 5,
	 'Individual',
	 24,
	 'Puff Daddy',
	 33,
	 'Estados Unidos',
	 10,
	 'Diddy'
	 );
	 CALL p_log_test('T-1.2', 'ERROR: Se han añadido datos incorrectos', 'FAIL');
END //
DELIMITER ;

-- =============================================================
-- TESTS PARA LA TABLA RANKING
-- =============================================================

-- RN-Ranking-01: Constraint de unicidad (player_id, fecha)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ranking_unique_constraint()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RANK-01', 'RN-Ranking: No se permiten duplicados (jugador, fecha)', 'PASS');

    CALL p_populate_db();
    -- Intentar insertar un ranking duplicado para el mismo jugador y fecha
    INSERT INTO ranking (player_id, fecha, posicion) VALUES (2, '2024-01-01', 5);
    CALL p_log_test('RANK-01', 'ERROR: Se permitió un ranking duplicado para el mismo jugador y fecha', 'FAIL');
END //
DELIMITER ;

-- RN-Ranking-02: Validar que la posición esté en rango válido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ranking_position_range()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RANK-02', 'RN-Ranking: La posición debe estar entre 1 y 1000', 'PASS');

    CALL p_populate_db();
    -- Intentar insertar una posición inválida (> 1000)
    INSERT INTO ranking (player_id, fecha, posicion) VALUES (2, '2024-12-01', 1500);
    CALL p_log_test('RANK-02', 'ERROR: Se permitió una posición fuera del rango válido', 'FAIL');
END //
DELIMITER ;

-- RN-Ranking-03: Validar que el cambio de posición no exceda 50 lugares (caso: excede límite)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ranking_max_change_exceeded()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RANK-03', 'RN-Ranking: No se permite cambio > 50 posiciones entre fechas consecutivas', 'PASS');

    CALL p_populate_db();
    -- Carlos Alcaraz está en posición 3 el 2024-05-01
    -- Intentar insertar posición 60 el 2024-06-01: ABS(60 - 3) = 57 posiciones (excede el límite de 50)
    INSERT INTO ranking (player_id, fecha, posicion) VALUES (2, '2024-06-01', 60);
    CALL p_log_test('RANK-03', 'ERROR: Se permitió un cambio mayor a 50 posiciones', 'FAIL');
END //
DELIMITER ;

-- RN-Ranking-04: Validar que el cambio de posición dentro del límite (50 lugares) sea permitido
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ranking_valid_change()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RANK-04', 'ERROR: No se permitió un cambio válido de posición', 'FAIL');

    CALL p_populate_db();
    -- Carlos Alcaraz está en posición 3 el 2024-05-01
    -- Insertar posición 50 el 2024-06-01: ABS(50 - 3) = 47 posiciones (dentro del límite de 50)
    INSERT INTO ranking (player_id, fecha, posicion) VALUES (2, '2024-06-01', 50);
    CALL p_log_test('RANK-04', 'RN-Ranking: Se permitió correctamente un cambio de posición dentro del límite', 'PASS');
END //
DELIMITER ;

-- RN-Ranking-05: Validar que se permita el primer ranking de un jugador (sin historial previo)
DELIMITER //
CREATE OR REPLACE PROCEDURE p_test_ranking_first_entry()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        CALL p_log_test('RANK-05', 'ERROR: No se permitió insertar el primer ranking de un jugador', 'FAIL');

    CALL p_populate_db();
    -- Djokovic (player_id = 1) no tiene rankings en la BD
    -- Debe permitirse insertar su primer ranking sin restricciones
    INSERT INTO ranking (player_id, fecha, posicion) VALUES (1, '2024-01-01', 1);
    CALL p_log_test('RANK-05', 'RN-Ranking: Se permitió correctamente el primer ranking de un jugador', 'PASS');
END //
DELIMITER ;

-- =============================================================
-- ORQUESTADOR: Ejecutar todos los tests
-- =============================================================
DELIMITER //
CREATE OR REPLACE PROCEDURE p_run_all_tests()
BEGIN
    DELETE FROM test_results;

    CALL p_test_rn02_adult_age();
    CALL p_test_rn03_unique_name();
    CALL p_test_rn04_invalid_ranking();
    CALL p_test_rn04_zero_ranking();
    CALL p_test_rn05_same_player();
    CALL p_test_rn06_max_matches_referee();
    CALL p_test_rn07_referee_nationality();
    CALL p_test_sets_invalid_winner();
    CALL p_test_sets_max_5_sets();
    CALL p_test_ra02_max_players_a_trainer_has();
    CALL p_test_t1_valid();
    CALL p_test_t1_invalid();
    -- Tests para la tabla Ranking
    CALL p_test_ranking_unique_constraint();
    CALL p_test_ranking_position_range();
    CALL p_test_ranking_max_change_exceeded();
    CALL p_test_ranking_valid_change();
    CALL p_test_ranking_first_entry();
    -- Ejecutar test F1 (devuelve resultset)
    CALL p_test_f1_sets_won_by_player();

    -- Resultados
    SELECT * FROM test_results ORDER BY execution_time, test_id;

    -- Resumen
    SELECT test_status, COUNT(*) AS count FROM test_results GROUP BY test_status;
END //
DELIMITER ;

-- Ejecutar todos los tests (opcional en HeidiSQL)
CALL p_run_all_tests();
