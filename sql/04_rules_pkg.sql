PROMPT Создание пакета DURAK_RULES

CREATE OR REPLACE PACKAGE durak_rules AUTHID DEFINER AS
    FUNCTION default_max_pairs (
        p_deck_size IN NUMBER
    ) RETURN NUMBER DETERMINISTIC;

    FUNCTION effective_attack_limit (
        p_max_pairs          IN NUMBER,
        p_defender_hand_size IN NUMBER
    ) RETURN NUMBER DETERMINISTIC;

    FUNCTION can_beat_values (
        p_attack_rank    IN NUMBER,
        p_attack_suit    IN VARCHAR2,
        p_defense_rank   IN NUMBER,
        p_defense_suit   IN VARCHAR2,
        p_trump_suit     IN VARCHAR2
    ) RETURN NUMBER DETERMINISTIC;

    FUNCTION can_beat (
        p_attack_card_id  IN NUMBER,
        p_defense_card_id IN NUMBER,
        p_trump_suit      IN VARCHAR2
    ) RETURN NUMBER;

    FUNCTION can_beat (
        p_attack_card_code  IN VARCHAR2,
        p_defense_card_code IN VARCHAR2,
        p_trump_suit        IN VARCHAR2
    ) RETURN NUMBER;

    FUNCTION active_player_count (
        p_game_id IN NUMBER
    ) RETURN NUMBER;

    FUNCTION next_active_seat (
        p_game_id      IN NUMBER,
        p_from_seat_no IN NUMBER
    ) RETURN NUMBER;

    FUNCTION rank_present_on_table (
        p_game_id  IN NUMBER,
        p_round_no IN NUMBER,
        p_card_id  IN NUMBER
    ) RETURN NUMBER;
END durak_rules;
/

CREATE OR REPLACE PACKAGE BODY durak_rules AS
    PROCEDURE validate_suit (
        p_suit IN VARCHAR2,
        p_name IN VARCHAR2
    ) IS
    BEGIN
        IF p_suit IS NULL
           OR UPPER(TRIM(p_suit)) NOT IN ('C', 'D', 'H', 'S') THEN
            RAISE_APPLICATION_ERROR(-20601, p_name || ': неизвестная масть.');
        END IF;
    END validate_suit;

    PROCEDURE validate_rank (
        p_rank IN NUMBER,
        p_name IN VARCHAR2
    ) IS
    BEGIN
        IF p_rank IS NULL OR p_rank NOT BETWEEN 2 AND 14 THEN
            RAISE_APPLICATION_ERROR(-20602, p_name || ': недопустимый ранг.');
        END IF;
    END validate_rank;

    FUNCTION default_max_pairs (
        p_deck_size IN NUMBER
    ) RETURN NUMBER DETERMINISTIC IS
    BEGIN
        CASE p_deck_size
            WHEN 36 THEN RETURN 6;
            WHEN 52 THEN RETURN 8;
            ELSE
                RAISE_APPLICATION_ERROR(-20603, 'Размер колоды должен быть 36 или 52.');
        END CASE;
    END default_max_pairs;

    FUNCTION effective_attack_limit (
        p_max_pairs          IN NUMBER,
        p_defender_hand_size IN NUMBER
    ) RETURN NUMBER DETERMINISTIC IS
    BEGIN
        IF p_max_pairs IS NULL
           OR p_max_pairs < 1
           OR p_max_pairs > 8
           OR p_max_pairs <> TRUNC(p_max_pairs) THEN
            RAISE_APPLICATION_ERROR(-20604, 'Некорректный лимит пар.');
        END IF;

        IF p_defender_hand_size IS NULL
           OR p_defender_hand_size < 1
           OR p_defender_hand_size <> TRUNC(p_defender_hand_size) THEN
            RAISE_APPLICATION_ERROR(-20605, 'У защитника должна быть хотя бы одна карта.');
        END IF;

        RETURN LEAST(p_max_pairs, p_defender_hand_size);
    END effective_attack_limit;

    FUNCTION can_beat_values (
        p_attack_rank    IN NUMBER,
        p_attack_suit    IN VARCHAR2,
        p_defense_rank   IN NUMBER,
        p_defense_suit   IN VARCHAR2,
        p_trump_suit     IN VARCHAR2
    ) RETURN NUMBER DETERMINISTIC IS
        v_attack_suit  CHAR(1);
        v_defense_suit CHAR(1);
        v_trump_suit   CHAR(1);
    BEGIN
        validate_rank(p_attack_rank, 'Атакующая карта');
        validate_rank(p_defense_rank, 'Защитная карта');
        validate_suit(p_attack_suit, 'Атакующая карта');
        validate_suit(p_defense_suit, 'Защитная карта');
        validate_suit(p_trump_suit, 'Козырь');

        v_attack_suit  := UPPER(TRIM(p_attack_suit));
        v_defense_suit := UPPER(TRIM(p_defense_suit));
        v_trump_suit   := UPPER(TRIM(p_trump_suit));

        IF v_attack_suit = v_defense_suit
           AND p_defense_rank > p_attack_rank THEN
            RETURN 1;
        END IF;

        IF v_attack_suit <> v_trump_suit
           AND v_defense_suit = v_trump_suit THEN
            RETURN 1;
        END IF;

        RETURN 0;
    END can_beat_values;

    FUNCTION can_beat (
        p_attack_card_id  IN NUMBER,
        p_defense_card_id IN NUMBER,
        p_trump_suit      IN VARCHAR2
    ) RETURN NUMBER IS
        v_attack_rank  durak_card.rank_value%TYPE;
        v_attack_suit  durak_card.suit_code%TYPE;
        v_defense_rank durak_card.rank_value%TYPE;
        v_defense_suit durak_card.suit_code%TYPE;
    BEGIN
        SELECT rank_value, suit_code
        INTO v_attack_rank, v_attack_suit
        FROM durak_card
        WHERE card_id = p_attack_card_id;

        SELECT rank_value, suit_code
        INTO v_defense_rank, v_defense_suit
        FROM durak_card
        WHERE card_id = p_defense_card_id;

        RETURN can_beat_values(
            v_attack_rank,
            v_attack_suit,
            v_defense_rank,
            v_defense_suit,
            p_trump_suit
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20606, 'Атакующая или защитная карта не найдена.');
    END can_beat;

    FUNCTION can_beat (
        p_attack_card_code  IN VARCHAR2,
        p_defense_card_code IN VARCHAR2,
        p_trump_suit        IN VARCHAR2
    ) RETURN NUMBER IS
        v_attack_id  durak_card.card_id%TYPE;
        v_defense_id durak_card.card_id%TYPE;
    BEGIN
        SELECT card_id
        INTO v_attack_id
        FROM durak_card
        WHERE card_code = UPPER(TRIM(p_attack_card_code));

        SELECT card_id
        INTO v_defense_id
        FROM durak_card
        WHERE card_code = UPPER(TRIM(p_defense_card_code));

        RETURN can_beat(v_attack_id, v_defense_id, p_trump_suit);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20607, 'Неизвестный код карты.');
    END can_beat;

    FUNCTION active_player_count (
        p_game_id IN NUMBER
    ) RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_status = 'ACTIVE';

        RETURN v_count;
    END active_player_count;

    FUNCTION next_active_seat (
        p_game_id      IN NUMBER,
        p_from_seat_no IN NUMBER
    ) RETURN NUMBER IS
        v_seat_no NUMBER;
    BEGIN
        IF p_from_seat_no IS NULL OR p_from_seat_no NOT BETWEEN 1 AND 6 THEN
            RAISE_APPLICATION_ERROR(-20608, 'Исходное место должно быть от 1 до 6.');
        END IF;

        SELECT seat_no
        INTO v_seat_no
        FROM (
            SELECT seat_no,
                   CASE
                       WHEN seat_no > p_from_seat_no THEN seat_no - p_from_seat_no
                       ELSE seat_no + 6 - p_from_seat_no
                   END AS clockwise_distance
            FROM durak_game_player
            WHERE game_id = p_game_id
              AND player_status = 'ACTIVE'
              AND seat_no <> p_from_seat_no
            ORDER BY clockwise_distance, seat_no
        )
        WHERE ROWNUM = 1;

        RETURN v_seat_no;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END next_active_seat;

    FUNCTION rank_present_on_table (
        p_game_id  IN NUMBER,
        p_round_no IN NUMBER,
        p_card_id  IN NUMBER
    ) RETURN NUMBER IS
        v_rank_value durak_card.rank_value%TYPE;
        v_pair_count NUMBER;
        v_rank_count NUMBER;
    BEGIN
        SELECT rank_value
        INTO v_rank_value
        FROM durak_card
        WHERE card_id = p_card_id;

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = p_round_no;

        IF v_pair_count = 0 THEN
            RETURN 1;
        END IF;

        SELECT COUNT(*)
        INTO v_rank_count
        FROM (
            SELECT attack_card_id AS table_card_id
            FROM durak_table_pair
            WHERE game_id = p_game_id
              AND round_no = p_round_no
            UNION ALL
            SELECT defense_card_id AS table_card_id
            FROM durak_table_pair
            WHERE game_id = p_game_id
              AND round_no = p_round_no
              AND defense_card_id IS NOT NULL
        ) table_cards
        JOIN durak_card c ON c.card_id = table_cards.table_card_id
        WHERE c.rank_value = v_rank_value;

        RETURN CASE WHEN v_rank_count > 0 THEN 1 ELSE 0 END;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20609, 'Карта для проверки достоинства не найдена.');
    END rank_present_on_table;
END durak_rules;
/

SHOW ERRORS PACKAGE durak_rules
SHOW ERRORS PACKAGE BODY durak_rules
