-- 
-- Autor: David Ruiz
-- Fecha: Noviembre 2025
-- Descripción: Script para crear la BD de Tenis
-- 
USE tenisdb;

-- Eliminar tablas si existen (orden seguro por claves foráneas)
-- Primero eliminar vistas que dependan de las tablas
DROP VIEW IF EXISTS v_players;
DROP VIEW IF EXISTS v_referees;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS ranking;
DROP TABLE IF EXISTS sets;
DROP TABLE IF EXISTS matches;
DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS referees;
DROP TABLE IF EXISTS trainers;
DROP TABLE IF EXISTS people;
-- NO borrar test_results para preservar resultados de tests
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE people (
    person_id INT AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    age INT NOT NULL,
    nationality VARCHAR(50) NOT NULL,
    PRIMARY KEY (person_id),
    CONSTRAINT rn_03_unique_name UNIQUE(name),
    CONSTRAINT rn_02_adult_age CHECK (age >= 18)
);

CREATE TABLE trainers (
	 trainer_id INT,
	 experience INT NOT NULL,
	 speciality VARCHAR(20) NOT NULL,
	 PRIMARY KEY (trainer_id),
	 FOREIGN KEY (trainer_id) REFERENCES people(person_id),
	 CONSTRAINT ra_01_invalidSpecuality CHECK (speciality IN ('Individual','Dobles'))
);

CREATE TABLE players (
    player_id INT,
    ranking INT NOT NULL,
    active BOOLEAN NOT NULL,
    trainer_id INT,
    PRIMARY KEY (player_id),
    FOREIGN KEY (player_id) REFERENCES people(person_id),
    FOREIGN KEY (trainer_id) REFERENCES trainers(trainer_id),
    CONSTRAINT rn_04_ranking CHECK (ranking > 0 AND ranking <= 1000)
);

CREATE TABLE ranking (
    ranking_id INT AUTO_INCREMENT,
    player_id INT NOT NULL,
    fecha DATE NOT NULL,
    posicion INT NOT NULL,
    PRIMARY KEY (ranking_id),
    FOREIGN KEY (player_id) REFERENCES players(player_id),
    CONSTRAINT rn_ranking_unique UNIQUE(player_id, fecha),
    CONSTRAINT rn_ranking_posicion CHECK (posicion > 0 AND posicion <= 1000)
);

CREATE TABLE referees (
    referee_id INT,
    license VARCHAR(30) NOT NULL,
    PRIMARY KEY (referee_id),
    FOREIGN KEY (referee_id) REFERENCES people(person_id),
    CONSTRAINT rn_07_license CHECK (license IN ('Nacional', 'Internacional'))
);

CREATE TABLE matches (
    match_id INT AUTO_INCREMENT,
    referee_id INT NOT NULL,
    player1_id INT NOT NULL,
    player2_id INT NOT NULL,
    winner_id INT NOT NULL,
    tournament VARCHAR(100) NOT NULL,
    match_date DATE NOT NULL,
    round VARCHAR(30) NOT NULL,
    duration INT NOT NULL,
    PRIMARY KEY (match_id),
    FOREIGN KEY (referee_id) REFERENCES referees(referee_id),
    FOREIGN KEY (player1_id) REFERENCES players(player_id),
    FOREIGN KEY (player2_id) REFERENCES players(player_id),
    FOREIGN KEY (winner_id) REFERENCES players(player_id),  
    CONSTRAINT rn_05_different_players CHECK (player1_id <> player2_id),
    CONSTRAINT rn_xx_valid_winner CHECK (winner_id IN (player1_id, player2_id)),
    CONSTRAINT rn_xx_duration CHECK (duration > 0) -- Extra: positive duration
);

CREATE TABLE sets (
    set_id INT AUTO_INCREMENT,
    match_id INT NOT NULL,
    winner_id INT NOT NULL,
    set_order INT NOT NULL,
    score VARCHAR(20) NOT NULL,
    PRIMARY KEY (set_id),
    FOREIGN KEY (match_id) REFERENCES matches(match_id),
    FOREIGN KEY (winner_id) REFERENCES players(player_id),
    CONSTRAINT rn_03_set_order CHECK (set_order >= 1 AND set_order <= 5)
);

-- Vistas para simplificar consultas uniendo people con referees/players
CREATE OR REPLACE VIEW v_referees AS
SELECT 
    r.referee_id AS person_id,
    p.name,
    p.age,
    p.nationality,
    r.license
FROM referees r
JOIN people p ON p.person_id = r.referee_id;

CREATE OR REPLACE VIEW v_players AS
SELECT 
    pl.player_id AS person_id,
    p.name,
    p.age,
    p.nationality,
    pl.ranking
FROM players pl
JOIN people p ON p.person_id = pl.player_id;

-- ============================================================================
-- TRIGGERS DE VALIDACIÓN
-- ============================================================================

DELIMITER //

-- ============================================================================
-- RN-06: Un árbitro no puede arbitrar más de 3 partidos en el mismo día
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_matches_rn06
BEFORE INSERT OR UPDATE ON matches
FOR EACH ROW
BEGIN
    DECLARE v_count INT;
    
    SELECT COUNT(*) INTO v_count
    FROM matches
    WHERE referee_id = NEW.referee_id
      AND match_date = NEW.match_date
      AND match_id <> IFNULL(NEW.match_id, 0);
    
    IF v_count >= 3 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RN-06: Un árbitro no puede arbitrar más de 3 partidos en el mismo día';
    END IF;
END //

-- ============================================================================
-- RN-07: La nacionalidad del árbitro no puede coincidir con la de ninguno de los jugadores
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_matches_rn07
BEFORE INSERT OR UPDATE ON matches
FOR EACH ROW
BEGIN
    DECLARE v_ref_nationality VARCHAR(50);
    DECLARE v_player1_nationality VARCHAR(50);
    DECLARE v_player2_nationality VARCHAR(50);
    
    -- Uso de vistas para obtener las nacionalidades
    SELECT nationality INTO v_ref_nationality
    FROM v_referees
    WHERE person_id = NEW.referee_id;
    
    SELECT nationality INTO v_player1_nationality
    FROM v_players
    WHERE person_id = NEW.player1_id;
    
    SELECT nationality INTO v_player2_nationality
    FROM v_players
    WHERE person_id = NEW.player2_id;
    
    IF v_ref_nationality = v_player1_nationality OR v_ref_nationality = v_player2_nationality THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RN-07: La nacionalidad del árbitro no puede coincidir con la de ninguno de los jugadores';
    END IF;
END //

-- ============================================================================
-- Sets: Validación de ganador y máximo 5 sets
-- ============================================================================

-- Validar que el ganador del set sea uno de los jugadores del partido
-- y que no se excedan los 5 sets por partido
CREATE OR REPLACE TRIGGER t_biu_sets_validations
BEFORE INSERT OR UPDATE ON sets
FOR EACH ROW
BEGIN
    DECLARE v_player1 INT;
    DECLARE v_player2 INT;
    DECLARE v_count INT;

    -- Validar ganador del set
    SELECT player1_id, player2_id INTO v_player1, v_player2
    FROM matches
    WHERE match_id = NEW.match_id;

    IF NEW.winner_id NOT IN (v_player1, v_player2) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sets: El ganador del set debe ser uno de los jugadores del partido';
    END IF;

    -- Validar máximo 5 sets
    SELECT COUNT(*) INTO v_count
    FROM sets
    WHERE match_id = NEW.match_id
      AND set_id <> IFNULL(NEW.set_id, 0);
    
    IF v_count >= 5 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sets: Un partido no puede tener más de 5 sets';
    END IF;
END //

-- ============================================================================
-- RA-02: Un entrenador no puede entrenar a más de 2 tenistas a la vez
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_players_ra02
BEFORE INSERT OR UPDATE ON players
FOR EACH ROW
BEGIN
    DECLARE t_count INT;
    
    SELECT COUNT(*) INTO t_count
    FROM players
    WHERE trainer_id = NEW.trainer_id;
    
    IF t_count >= 2 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RA-02: Un entrenador no puede entrenar a más de 2 tenistas a la vez';
    END IF;
END //

-- ============================================================================
-- RA-03: Un entrenador ha podido ser tenista con anterioridad
-- ============================================================================

CREATE OR REPLACE TRIGGER t_biu_trainers_ra03
BEFORE INSERT OR UPDATE ON trainers
FOR EACH ROW
BEGIN
    DECLARE activeb BOOLEAN;
    SET activeb = FALSE;
    
    SELECT active INTO activeb FROM players WHERE player_id = NEW.trainer_id;
    
    IF activeb = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RA-03: Un entrenador ha podido ser tenista con anterioridad';
    END IF;
END //

CREATE OR REPLACE TRIGGER t_biu_players_ra03
BEFORE INSERT OR UPDATE ON players
FOR EACH ROW
BEGIN
    DECLARE trainerid INT;
    SET trainerid = NULL;
    
    SELECT trainer_id INTO trainerid FROM trainers WHERE trainer_id = NEW.player_id;
    
    IF (NEW.active = TRUE) AND (trainerid = NEW.player_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RA-03: Estás intentando añadir un tenista activo que ya es entrenador';
    END IF;
END //

-- ============================================================================
-- RN-Ranking: La posición en el ranking no puede cambiar más de 50 lugares 
-- entre dos fechas consecutivas para el mismo jugador
-- ============================================================================

CREATE OR REPLACE TRIGGER t_bi_ranking_position_change
BEFORE INSERT ON ranking
FOR EACH ROW
BEGIN
    DECLARE v_previous_position INT;
    DECLARE v_position_diff INT;
    
    -- Obtener la posición más reciente anterior a la nueva fecha para el mismo jugador
    SELECT posicion INTO v_previous_position
    FROM ranking
    WHERE player_id = NEW.player_id
      AND fecha < NEW.fecha
    ORDER BY fecha DESC
    LIMIT 1;
    
    -- Si existe una posición previa, validar que el cambio no exceda 50 lugares
    IF v_previous_position IS NOT NULL THEN
        SET v_position_diff = ABS(NEW.posicion - v_previous_position);
        
        IF v_position_diff > 50 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-Ranking: La posición no puede cambiar más de 50 lugares entre fechas consecutivas';
        END IF;
    END IF;
END //

CREATE OR REPLACE TRIGGER t_bu_ranking_position_change
BEFORE UPDATE ON ranking
FOR EACH ROW
BEGIN
    DECLARE v_previous_position INT;
    DECLARE v_position_diff INT;
    
    -- Obtener la posición más reciente anterior a la nueva fecha para el mismo jugador
    SELECT posicion INTO v_previous_position
    FROM ranking
    WHERE player_id = NEW.player_id
      AND fecha < NEW.fecha
      AND ranking_id <> OLD.ranking_id
    ORDER BY fecha DESC
    LIMIT 1;
    
    -- Si existe una posición previa, validar que el cambio no exceda 50 lugares
    IF v_previous_position IS NOT NULL THEN
        SET v_position_diff = ABS(NEW.posicion - v_previous_position);
        
        IF v_position_diff > 50 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RN-Ranking: La posición no puede cambiar más de 50 lugares entre fechas consecutivas';
        END IF;
    END IF;
END //
DELIMITER ;

-- ============================================================================
-- FUNCIONES
-- ============================================================================

DELIMITER //

-- ============================================================================
-- F1: Dado un tenista y un partido, realice una función que devuelva el número de sets ganados por ese tenista en ese partido
-- ============================================================================

CREATE OR REPLACE FUNCTION f1_sets_won_by_player_in_match(p_player_id INT, p_match_id INT)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_sets_won INT;
    SELECT COUNT(*) INTO v_sets_won
    FROM sets
    WHERE winner_id = p_player_id
      AND match_id = p_match_id;
    RETURN v_sets_won;
END //

DELIMITER ;

-- ============================================================================
-- 6.- TRANSACCIONES
-- ============================================================================

DELIMITER //
CREATE OR REPLACE PROCEDURE create2Trainers(
	 person_id1 INT,
	 name1 VARCHAR(100),
	 age1 INT,
	 nationality1 VARCHAR(100),
	 experience1 INT, 
	 speciality1 VARCHAR(50),
	 person_id2 INT,
	 name2 VARCHAR(100),
	 age2 INT,
	 nationality2 VARCHAR(100),
    experience2 INT, 
    speciality2 VARCHAR(50)
)
BEGIN
    START TRANSACTION;
    tblock: BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION, SQLWARNING
        BEGIN
            ROLLBACK;
            RESIGNAL;
        END;
         INSERT INTO people (person_id, name, age, nationality) VALUES
         	(person_id1, name1, age1, nationality1),
         	(person_id2, name2, age2, nationality2);
			INSERT INTO trainers (trainer_id, experience, speciality) VALUES
				(person_id1, experience1, speciality1),
				(person_id2, experience2, speciality2);
        COMMIT;
    END tblock;
END //
DELIMITER ;