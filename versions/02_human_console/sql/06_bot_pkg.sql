PROMPT Создание игрового пакета ботов DURAK_BOT

CREATE OR REPLACE PACKAGE durak_bot AUTHID DEFINER AS
    PROCEDURE play_until_human (
        p_game_id     IN NUMBER,
        p_max_actions IN NUMBER DEFAULT 500
    );
END durak_bot;
/

CREATE OR REPLACE PACKAGE BODY durak_bot AS
    FUNCTION choose_attack_card (
        p_game_id IN NUMBER,
        p_seat_no IN NUMBER,
        p_level   IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_card_code durak_card.card_code%TYPE;
    BEGIN
        SELECT card_code
        INTO v_card_code
        FROM (
            SELECT candidate.card_code
            FROM (
                SELECT
                    c.card_code,
                    c.rank_value,
                    c.suit_code,
                    (
                        SELECT COUNT(*)
                        FROM durak_game_card gc2
                        JOIN durak_card c2
                          ON c2.card_id = gc2.card_id
                        WHERE gc2.game_id = gc.game_id
                          AND gc2.owner_seat_no = gc.owner_seat_no
                          AND gc2.card_zone = 'HAND'
                          AND c2.rank_value = c.rank_value
                    ) AS same_rank_count,
                    g.trump_suit
                FROM durak_game_card gc
                JOIN durak_card c
                  ON c.card_id = gc.card_id
                JOIN durak_game g
                  ON g.game_id = gc.game_id
                WHERE gc.game_id = p_game_id
                  AND gc.owner_seat_no = p_seat_no
                  AND gc.card_zone = 'HAND'
            ) candidate
            ORDER BY
                CASE
                    WHEN p_level = 'EASY'
                         AND candidate.suit_code = candidate.trump_suit THEN 0
                    WHEN p_level = 'EASY' THEN 1
                    WHEN candidate.suit_code = candidate.trump_suit THEN 1
                    ELSE 0
                END,
                CASE
                    WHEN p_level = 'HARD' THEN -candidate.same_rank_count
                    ELSE 0
                END,
                CASE
                    WHEN p_level = 'EASY' THEN -candidate.rank_value
                    ELSE candidate.rank_value
                END,
                candidate.suit_code
        )
        WHERE ROWNUM = 1;

        RETURN v_card_code;
    END choose_attack_card;

    PROCEDURE choose_defense_card (
        p_game_id  IN NUMBER,
        p_seat_no  IN NUMBER,
        p_level    IN VARCHAR2,
        p_card_code OUT VARCHAR2,
        p_pair_no   OUT NUMBER
    ) IS
        v_attack_card_id NUMBER;
        v_trump_suit     CHAR(1);
    BEGIN
        p_card_code := NULL;
        p_pair_no := NULL;

        SELECT pair_no, attack_card_id
        INTO p_pair_no, v_attack_card_id
        FROM (
            SELECT pair_no, attack_card_id
            FROM durak_table_pair
            WHERE game_id = p_game_id
              AND pair_status = 'OPEN'
            ORDER BY round_no, pair_no
        )
        WHERE ROWNUM = 1;

        SELECT trump_suit
        INTO v_trump_suit
        FROM durak_game
        WHERE game_id = p_game_id;

        SELECT card_code
        INTO p_card_code
        FROM (
            SELECT
                c.card_code,
                c.rank_value,
                c.suit_code,
                attack_card.suit_code AS attack_suit
            FROM durak_game_card gc
            JOIN durak_card c
              ON c.card_id = gc.card_id
            JOIN durak_card attack_card
              ON attack_card.card_id = v_attack_card_id
            WHERE gc.game_id = p_game_id
              AND gc.owner_seat_no = p_seat_no
              AND gc.card_zone = 'HAND'
              AND durak_rules.can_beat(
                    v_attack_card_id,
                    gc.card_id,
                    v_trump_suit
                  ) = 1
            ORDER BY
                CASE
                    WHEN p_level = 'EASY' AND c.suit_code = v_trump_suit THEN 0
                    WHEN p_level = 'EASY' THEN 1
                    WHEN c.suit_code = attack_card.suit_code THEN 0
                    ELSE 1
                END,
                CASE WHEN p_level = 'EASY' THEN -c.rank_value ELSE c.rank_value END,
                c.suit_code
        )
        WHERE ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_card_code := NULL;
    END choose_defense_card;

    FUNCTION choose_throw_card (
        p_game_id IN NUMBER,
        p_seat_no IN NUMBER,
        p_level   IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_card_code durak_card.card_code%TYPE;
        v_round_no  NUMBER;
    BEGIN
        SELECT current_round_no
        INTO v_round_no
        FROM durak_game
        WHERE game_id = p_game_id;

        SELECT card_code
        INTO v_card_code
        FROM (
            SELECT c.card_code, c.rank_value, c.suit_code, g.trump_suit
            FROM durak_game_card gc
            JOIN durak_card c
              ON c.card_id = gc.card_id
            JOIN durak_game g
              ON g.game_id = gc.game_id
            WHERE gc.game_id = p_game_id
              AND gc.owner_seat_no = p_seat_no
              AND gc.card_zone = 'HAND'
              AND durak_rules.rank_present_on_table(
                    p_game_id,
                    v_round_no,
                    gc.card_id
                  ) = 1
            ORDER BY
                CASE WHEN c.suit_code = g.trump_suit THEN 1 ELSE 0 END,
                CASE WHEN p_level = 'HARD' THEN -c.rank_value ELSE c.rank_value END,
                c.suit_code
        )
        WHERE ROWNUM = 1;

        RETURN v_card_code;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END choose_throw_card;

    PROCEDURE save_decision (
        p_game_id      IN NUMBER,
        p_bot_player_id IN NUMBER,
        p_bot_level    IN VARCHAR2,
        p_action       IN VARCHAR2,
        p_duration_ms  IN NUMBER,
        p_explanation  IN VARCHAR2
    ) IS
        v_event_id durak_event.event_id%TYPE;
    BEGIN
        SELECT event_id
        INTO v_event_id
        FROM (
            SELECT event_id
            FROM durak_event
            WHERE game_id = p_game_id
              AND actor_player_id = p_bot_player_id
              AND event_type = 'BOT_DECISION'
            ORDER BY event_no DESC
        )
        WHERE ROWNUM = 1;

        INSERT INTO durak_bot_decision (
            decision_id,
            game_id,
            event_id,
            bot_player_id,
            bot_level,
            selected_action,
            score_value,
            duration_ms,
            explanation
        ) VALUES (
            durak_id_seq.NEXTVAL,
            p_game_id,
            v_event_id,
            p_bot_player_id,
            p_bot_level,
            p_action,
            CASE p_bot_level WHEN 'EASY' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END,
            GREATEST(0, NVL(p_duration_ms, 0)),
            SUBSTR(p_explanation, 1, 1000)
        );
    END save_decision;

    PROCEDURE play_until_human (
        p_game_id     IN NUMBER,
        p_max_actions IN NUMBER DEFAULT 500
    ) IS
        v_game          durak_game%ROWTYPE;
        v_bot_player_id NUMBER;
        v_bot_level     VARCHAR2(10);
        v_card_code     VARCHAR2(3);
        v_pair_no       NUMBER;
        v_action        VARCHAR2(30);
        v_explanation   VARCHAR2(1000);
        v_started_at    TIMESTAMP WITH TIME ZONE;
        v_duration_ms   NUMBER;
    BEGIN
        IF p_max_actions IS NULL
           OR p_max_actions < 1
           OR p_max_actions > 10000
           OR p_max_actions <> TRUNC(p_max_actions) THEN
            RAISE_APPLICATION_ERROR(
                -20620,
                'Лимит автоматических действий должен быть целым числом от 1 до 10000.'
            );
        END IF;

        FOR v_step IN 1 .. p_max_actions LOOP
            SELECT *
            INTO v_game
            FROM durak_game
            WHERE game_id = p_game_id;

            IF v_game.game_status <> 'ACTIVE'
               OR v_game.current_actor_seat_no IS NULL THEN
                RETURN;
            END IF;

            BEGIN
                SELECT gp.player_id, p.bot_level
                INTO v_bot_player_id, v_bot_level
                FROM durak_game_player gp
                JOIN durak_player p
                  ON p.player_id = gp.player_id
                WHERE gp.game_id = p_game_id
                  AND gp.seat_no = v_game.current_actor_seat_no
                  AND gp.player_status = 'ACTIVE'
                  AND p.player_type = 'BOT';
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Текущий участник человек: управление возвращается SQL-клиенту.
                    RETURN;
            END;

            v_card_code := NULL;
            v_pair_no := NULL;

            CASE v_game.phase
                WHEN 'WAIT_ATTACK' THEN
                    v_action := 'ATTACK';
                    v_card_code := choose_attack_card(
                        p_game_id,
                        v_game.current_actor_seat_no,
                        v_bot_level
                    );
                    v_explanation := CASE v_bot_level
                        WHEN 'EASY' THEN 'Атакует дорогой картой, не сохраняя козыри.'
                        WHEN 'NORMAL' THEN 'Атакует младшей некозырной картой.'
                        ELSE 'Сохраняет козыри и предпочитает достоинство с повторениями.'
                    END;
                WHEN 'WAIT_DEFENSE' THEN
                    choose_defense_card(
                        p_game_id,
                        v_game.current_actor_seat_no,
                        v_bot_level,
                        v_card_code,
                        v_pair_no
                    );
                    IF v_card_code IS NULL THEN
                        v_action := 'TAKE';
                        v_explanation := 'Подходящей карты для защиты нет.';
                    ELSE
                        v_action := 'DEFEND';
                        v_explanation := CASE v_bot_level
                            WHEN 'EASY' THEN 'Использует первую дорогую подходящую карту.'
                            ELSE 'Использует младшую карту, достаточную для защиты.'
                        END;
                    END IF;
                WHEN 'WAIT_THROW' THEN
                    IF v_bot_level = 'EASY' THEN
                        v_action := 'PASS';
                        v_explanation := 'Easy не подбрасывает дополнительные карты.';
                    ELSE
                        v_card_code := choose_throw_card(
                            p_game_id,
                            v_game.current_actor_seat_no,
                            v_bot_level
                        );
                        IF v_card_code IS NULL THEN
                            v_action := 'PASS';
                            v_explanation := 'Подходящей карты для подбрасывания нет.';
                        ELSE
                            v_action := 'THROW_IN';
                            v_explanation := 'Подбрасывает карту уже присутствующего достоинства.';
                        END IF;
                    END IF;
                WHEN 'TAKE_THROW' THEN
                    IF v_bot_level = 'HARD' THEN
                        v_card_code := choose_throw_card(
                            p_game_id,
                            v_game.current_actor_seat_no,
                            v_bot_level
                        );
                    END IF;
                    IF v_card_code IS NULL THEN
                        v_action := 'PASS';
                        v_explanation := 'Завершает подбрасывание после объявления взятия.';
                    ELSE
                        v_action := 'THROW_IN';
                        v_explanation := 'Hard использует разрешённое подбрасывание после взятия.';
                    END IF;
                ELSE
                    RETURN;
            END CASE;

            v_started_at := SYSTIMESTAMP;
            durak_engine.execute_bot_action(
                p_bot_player_id => v_bot_player_id,
                p_game_id       => p_game_id,
                p_action_type   => v_action,
                p_card_code     => v_card_code,
                p_pair_no       => v_pair_no
            );
            v_duration_ms := ROUND(
                (CAST(SYSTIMESTAMP AS DATE) - CAST(v_started_at AS DATE)) * 86400000
            );

            save_decision(
                p_game_id       => p_game_id,
                p_bot_player_id => v_bot_player_id,
                p_bot_level     => v_bot_level,
                p_action        => v_action,
                p_duration_ms   => v_duration_ms,
                p_explanation   => v_explanation
            );
        END LOOP;
    END play_until_human;
END durak_bot;
/

SHOW ERRORS PACKAGE durak_bot
SHOW ERRORS PACKAGE BODY durak_bot
