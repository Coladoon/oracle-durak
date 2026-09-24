PROMPT Создание внутреннего игрового автомата DURAK_ENGINE

CREATE OR REPLACE PACKAGE durak_engine AUTHID DEFINER AS
    PROCEDURE create_game (
        p_creator_player_id   IN NUMBER,
        p_deck_size           IN NUMBER DEFAULT 36,
        p_game_variant        IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode     IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs           IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec    IN NUMBER DEFAULT 60,
        p_idle_timeout_min    IN NUMBER DEFAULT 30,
        p_allow_throw_after_take IN VARCHAR2 DEFAULT 'N',
        p_limit_by_defender_hand IN VARCHAR2 DEFAULT 'Y',
        p_seed_text           IN VARCHAR2 DEFAULT NULL,
        p_daily_id            IN NUMBER DEFAULT NULL,
        p_game_id             OUT NUMBER
    );

    PROCEDURE join_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_seat_no   OUT NUMBER
    );

    PROCEDURE start_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    );

    PROCEDURE attack (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    );

    PROCEDURE defend (
        p_player_id        IN NUMBER,
        p_game_id          IN NUMBER,
        p_defense_card_code IN VARCHAR2,
        p_pair_no          IN NUMBER DEFAULT NULL
    );

    PROCEDURE throw_in (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    );

    PROCEDURE pass_throw (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    );

    PROCEDURE take_cards (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    );

    PROCEDURE transfer_attack (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    );

    PROCEDURE add_bot (
        p_actor_player_id IN NUMBER,
        p_game_id         IN NUMBER,
        p_bot_level       IN VARCHAR2,
        p_bot_player_id   OUT NUMBER,
        p_seat_no         OUT NUMBER
    );

    PROCEDURE execute_bot_action (
        p_bot_player_id IN NUMBER,
        p_game_id       IN NUMBER,
        p_action_type   IN VARCHAR2,
        p_card_code     IN VARCHAR2 DEFAULT NULL,
        p_pair_no       IN NUMBER DEFAULT NULL
    );

    PROCEDURE heartbeat (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    );

    PROCEDURE cancel_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    );

    PROCEDURE process_timeout (
        p_game_id IN NUMBER
    );

    PROCEDURE expire_idle_game (
        p_game_id IN NUMBER
    );

    PROCEDURE log_rejection (
        p_game_id      IN NUMBER,
        p_player_id    IN NUMBER,
        p_db_username  IN VARCHAR2,
        p_action_type  IN VARCHAR2,
        p_error_code   IN NUMBER,
        p_error_message IN VARCHAR2
    );
END durak_engine;
/

CREATE OR REPLACE PACKAGE BODY durak_engine AS
    c_target_hand_size CONSTANT PLS_INTEGER := 6;
    g_action_source durak_event.event_source%TYPE := 'MANUAL';

    PROCEDURE fail (
        p_code    IN NUMBER,
        p_message IN VARCHAR2
    ) IS
    BEGIN
        RAISE_APPLICATION_ERROR(p_code, p_message);
    END fail;

    FUNCTION normalized_flag (
        p_value IN VARCHAR2,
        p_name  IN VARCHAR2
    ) RETURN CHAR DETERMINISTIC IS
        v_value VARCHAR2(10) := UPPER(TRIM(p_value));
    BEGIN
        IF v_value IS NULL OR v_value NOT IN ('Y', 'N') THEN
            fail(-20703, p_name || ' должен иметь значение Y или N.');
        END IF;
        RETURN v_value;
    END normalized_flag;

    PROCEDURE lock_game (
        p_game_id IN NUMBER,
        p_game    OUT durak_game%ROWTYPE
    ) IS
    BEGIN
        BEGIN
            SELECT *
            INTO p_game
            FROM durak_game
            WHERE game_id = p_game_id
            FOR UPDATE WAIT 5;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fail(-20701, 'Партия ' || p_game_id || ' не найдена.');
            WHEN OTHERS THEN
                IF SQLCODE IN (-54, -30006) THEN
                    fail(-20702, 'Партия занята другим действием. Повторите попытку.');
                END IF;
                RAISE;
        END;
    END lock_game;

    PROCEDURE require_player (
        p_player_id IN NUMBER,
        p_player    OUT durak_player%ROWTYPE
    ) IS
    BEGIN
        SELECT *
        INTO p_player
        FROM durak_player
        WHERE player_id = p_player_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(-20704, 'Игрок не зарегистрирован.');
    END require_player;

    PROCEDURE require_game_player (
        p_game_id   IN NUMBER,
        p_player_id IN NUMBER,
        p_game_player OUT durak_game_player%ROWTYPE
    ) IS
    BEGIN
        SELECT *
        INTO p_game_player
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_id = p_player_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(-20705, 'Игрок не участвует в этой партии.');
    END require_game_player;

    PROCEDURE assert_no_active_session (
        p_player_id IN NUMBER
    ) IS
        v_game_id durak_active_session.game_id%TYPE;
        v_status  durak_game.game_status%TYPE;
    BEGIN
        BEGIN
            SELECT s.game_id, g.game_status
            INTO v_game_id, v_status
            FROM durak_active_session s
            JOIN durak_game g ON g.game_id = s.game_id
            WHERE s.player_id = p_player_id
            FOR UPDATE OF s.last_activity_at;

            IF v_status IN ('LOBBY', 'ACTIVE') THEN
                fail(
                    -20706,
                    'У пользователя уже открыта партия ' || v_game_id
                    || '. Вторая одновременная сессия запрещена.'
                );
            END IF;

            DELETE FROM durak_active_session
            WHERE player_id = p_player_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
    END assert_no_active_session;

    PROCEDURE reserve_session (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_type durak_player.player_type%TYPE;
    BEGIN
        SELECT player_type
        INTO v_type
        FROM durak_player
        WHERE player_id = p_player_id;

        IF v_type = 'HUMAN' THEN
            BEGIN
                INSERT INTO durak_active_session (player_id, game_id)
                VALUES (p_player_id, p_game_id);
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    fail(
                        -20706,
                        'У пользователя уже есть другая активная игровая сессия.'
                    );
            END;
        END IF;
    END reserve_session;

    PROCEDURE release_sessions (
        p_game_id IN NUMBER
    ) IS
    BEGIN
        DELETE FROM durak_active_session
        WHERE game_id = p_game_id;
    END release_sessions;

    PROCEDURE append_event (
        p_game_id            IN NUMBER,
        p_event_type         IN VARCHAR2,
        p_message            IN VARCHAR2,
        p_event_id           OUT NUMBER,
        p_event_no           OUT NUMBER,
        p_source             IN VARCHAR2 DEFAULT 'SYSTEM',
        p_actor_player_id    IN NUMBER DEFAULT NULL,
        p_actor_seat_no      IN NUMBER DEFAULT NULL,
        p_card_id            IN NUMBER DEFAULT NULL,
        p_target_pair_no     IN NUMBER DEFAULT NULL,
        p_target_seat_no     IN NUMBER DEFAULT NULL,
        p_visibility         IN VARCHAR2 DEFAULT 'PUBLIC',
        p_visible_to_seat_no IN NUMBER DEFAULT NULL
    ) IS
        v_round_no durak_game.current_round_no%TYPE;
        v_phase    durak_game.phase%TYPE;
        v_version  durak_game.version_no%TYPE;
    BEGIN
        SELECT next_event_no, current_round_no, phase, version_no
        INTO p_event_no, v_round_no, v_phase, v_version
        FROM durak_game
        WHERE game_id = p_game_id;

        p_event_id := durak_id_seq.NEXTVAL;

        INSERT INTO durak_event (
            event_id,
            game_id,
            event_no,
            round_no,
            event_type,
            event_source,
            actor_player_id,
            actor_seat_no,
            card_id,
            target_pair_no,
            target_seat_no,
            phase_before,
            phase_after,
            version_before,
            version_after,
            visibility_code,
            visible_to_seat_no,
            event_message
        ) VALUES (
            p_event_id,
            p_game_id,
            p_event_no,
            CASE WHEN v_round_no = 0 THEN NULL ELSE v_round_no END,
            p_event_type,
            p_source,
            p_actor_player_id,
            p_actor_seat_no,
            p_card_id,
            p_target_pair_no,
            p_target_seat_no,
            v_phase,
            v_phase,
            v_version,
            v_version,
            p_visibility,
            p_visible_to_seat_no,
            SUBSTR(p_message, 1, 1000)
        );

        UPDATE durak_game
        SET next_event_no = next_event_no + 1
        WHERE game_id = p_game_id;
    END append_event;

    PROCEDURE append_simple_event (
        p_game_id         IN NUMBER,
        p_event_type      IN VARCHAR2,
        p_message         IN VARCHAR2,
        p_source          IN VARCHAR2 DEFAULT 'SYSTEM',
        p_actor_player_id IN NUMBER DEFAULT NULL,
        p_actor_seat_no   IN NUMBER DEFAULT NULL,
        p_target_seat_no  IN NUMBER DEFAULT NULL
    ) IS
        v_event_id NUMBER;
        v_event_no NUMBER;
    BEGIN
        append_event(
            p_game_id         => p_game_id,
            p_event_type      => p_event_type,
            p_message         => p_message,
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => p_source,
            p_actor_player_id => p_actor_player_id,
            p_actor_seat_no   => p_actor_seat_no,
            p_target_seat_no  => p_target_seat_no
        );
    END append_simple_event;

    PROCEDURE finalize_event_state (
        p_game_id  IN NUMBER,
        p_event_id IN NUMBER
    ) IS
    BEGIN
        UPDATE durak_event e
        SET (phase_after, version_after) = (
            SELECT g.phase, g.version_no
            FROM durak_game g
            WHERE g.game_id = p_game_id
        )
        WHERE e.game_id = p_game_id
          AND e.event_id = p_event_id;

        IF SQL%ROWCOUNT <> 1 THEN
            fail(-20765, 'Не удалось зафиксировать итоговое состояние события.');
        END IF;
    END finalize_event_state;

    PROCEDURE append_card_move (
        p_event_id           IN NUMBER,
        p_game_id            IN NUMBER,
        p_card_id            IN NUMBER,
        p_from_zone          IN VARCHAR2,
        p_to_zone            IN VARCHAR2,
        p_from_owner_seat_no IN NUMBER DEFAULT NULL,
        p_to_owner_seat_no   IN NUMBER DEFAULT NULL,
        p_from_pair_no       IN NUMBER DEFAULT NULL,
        p_to_pair_no         IN NUMBER DEFAULT NULL,
        p_is_face_up_after   IN VARCHAR2 DEFAULT 'N'
    ) IS
    BEGIN
        INSERT INTO durak_card_move (
            card_move_id,
            game_id,
            event_id,
            card_id,
            from_zone,
            to_zone,
            from_owner_seat_no,
            to_owner_seat_no,
            from_pair_no,
            to_pair_no,
            is_face_up_after
        ) VALUES (
            durak_id_seq.NEXTVAL,
            p_game_id,
            p_event_id,
            p_card_id,
            p_from_zone,
            p_to_zone,
            p_from_owner_seat_no,
            p_to_owner_seat_no,
            p_from_pair_no,
            p_to_pair_no,
            p_is_face_up_after
        );
    END append_card_move;

    PROCEDURE touch_game (
        p_game_id   IN NUMBER,
        p_player_id IN NUMBER DEFAULT NULL
    ) IS
    BEGIN
        UPDATE durak_game
        SET version_no = version_no + 1,
            last_activity_at = CASE
                WHEN g_action_source = 'TIMEOUT' THEN last_activity_at
                ELSE SYSTIMESTAMP
            END,
            action_deadline_at = CASE
                WHEN game_status = 'ACTIVE' AND turn_timeout_sec > 0 THEN
                    SYSTIMESTAMP + NUMTODSINTERVAL(turn_timeout_sec, 'SECOND')
                ELSE NULL
            END
        WHERE game_id = p_game_id;

        -- Активность хранится на строке партии. Строка резерва сессии
        -- намеренно не блокируется каждым ходом: это сохраняет единый порядок
        -- блокировок «турнир -> сессия» при завершении турнирного матча.
    END touch_game;

    FUNCTION find_hand_card (
        p_game_id   IN NUMBER,
        p_seat_no   IN NUMBER,
        p_card_code IN VARCHAR2
    ) RETURN NUMBER IS
        v_card_id durak_card.card_id%TYPE;
    BEGIN
        SELECT gc.card_id
        INTO v_card_id
        FROM durak_game_card gc
        JOIN durak_card c ON c.card_id = gc.card_id
        WHERE gc.game_id = p_game_id
          AND gc.card_zone = 'HAND'
          AND gc.owner_seat_no = p_seat_no
          AND c.card_code = UPPER(TRIM(p_card_code));

        RETURN v_card_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            fail(-20720, 'У игрока нет карты ' || UPPER(TRIM(p_card_code)) || '.');
            RETURN NULL;
    END find_hand_card;

    PROCEDURE move_hand_card_to_table (
        p_game_id IN NUMBER,
        p_seat_no IN NUMBER,
        p_card_id IN NUMBER,
        p_pair_no IN NUMBER,
        p_zone    IN VARCHAR2,
        p_event_id IN NUMBER
    ) IS
    BEGIN
        UPDATE durak_game_card
        SET card_zone = p_zone,
            owner_seat_no = NULL,
            table_pair_no = p_pair_no,
            is_face_up = 'Y',
            changed_at = SYSTIMESTAMP
        WHERE game_id = p_game_id
          AND card_id = p_card_id
          AND card_zone = 'HAND'
          AND owner_seat_no = p_seat_no;

        IF SQL%ROWCOUNT <> 1 THEN
            fail(-20721, 'Карта уже перемещена другим действием.');
        END IF;

        UPDATE durak_game_player
        SET hand_count = hand_count - 1
        WHERE game_id = p_game_id
          AND seat_no = p_seat_no
          AND hand_count > 0;

        IF SQL%ROWCOUNT <> 1 THEN
            fail(-20722, 'Нарушен счётчик карт игрока.');
        END IF;

        append_card_move(
            p_event_id           => p_event_id,
            p_game_id            => p_game_id,
            p_card_id            => p_card_id,
            p_from_zone          => 'HAND',
            p_to_zone            => p_zone,
            p_from_owner_seat_no => p_seat_no,
            p_to_pair_no         => p_pair_no,
            p_is_face_up_after   => 'Y'
        );
    END move_hand_card_to_table;

    FUNCTION next_thrower (
        p_game_id         IN NUMBER,
        p_from_seat_no    IN NUMBER,
        p_defender_seat_no IN NUMBER
    ) RETURN NUMBER IS
        v_seat_no NUMBER;
    BEGIN
        SELECT seat_no
        INTO v_seat_no
        FROM (
            SELECT seat_no,
                   CASE
                       WHEN seat_no > p_from_seat_no THEN seat_no - p_from_seat_no
                       ELSE seat_no + 6 - p_from_seat_no
                   END AS distance_no
            FROM durak_game_player
            WHERE game_id = p_game_id
              AND player_status = 'ACTIVE'
              AND seat_no <> p_defender_seat_no
            ORDER BY distance_no, seat_no
        )
        WHERE ROWNUM = 1;

        RETURN v_seat_no;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END next_thrower;

    PROCEDURE draw_player_to_target (
        p_game_id IN NUMBER,
        p_seat_no IN NUMBER
    ) IS
        v_hand_count durak_game_player.hand_count%TYPE;
        v_target     durak_game.target_hand_size%TYPE;
        v_card_id    durak_game_card.card_id%TYPE;
        v_event_id   NUMBER;
        v_event_no   NUMBER;
    BEGIN
        SELECT gp.hand_count, g.target_hand_size
        INTO v_hand_count, v_target
        FROM durak_game_player gp
        JOIN durak_game g ON g.game_id = gp.game_id
        WHERE gp.game_id = p_game_id
          AND gp.seat_no = p_seat_no;

        WHILE v_hand_count < v_target LOOP
            BEGIN
                SELECT card_id
                INTO v_card_id
                FROM (
                    SELECT card_id
                    FROM durak_game_card
                    WHERE game_id = p_game_id
                      AND card_zone = 'TALON'
                    ORDER BY deck_pos
                )
                WHERE ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    EXIT;
            END;

            append_event(
                p_game_id            => p_game_id,
                p_event_type         => 'DRAW',
                p_message            => 'Игрок добрал карту из талона.',
                p_event_id           => v_event_id,
                p_event_no           => v_event_no,
                p_source             => 'SYSTEM',
                p_card_id            => v_card_id,
                p_target_seat_no      => p_seat_no,
                p_visibility         => 'PRIVATE',
                p_visible_to_seat_no => p_seat_no
            );

            UPDATE durak_game_card
            SET card_zone = 'HAND',
                owner_seat_no = p_seat_no,
                table_pair_no = NULL,
                received_seq = v_event_no,
                is_face_up = 'N',
                changed_at = SYSTIMESTAMP
            WHERE game_id = p_game_id
              AND card_id = v_card_id
              AND card_zone = 'TALON';

            IF SQL%ROWCOUNT <> 1 THEN
                fail(-20723, 'Карта талона уже была забрана.');
            END IF;

            UPDATE durak_game_player
            SET hand_count = hand_count + 1
            WHERE game_id = p_game_id
              AND seat_no = p_seat_no;

            append_card_move(
                p_event_id         => v_event_id,
                p_game_id          => p_game_id,
                p_card_id          => v_card_id,
                p_from_zone        => 'TALON',
                p_to_zone          => 'HAND',
                p_to_owner_seat_no => p_seat_no,
                p_is_face_up_after => 'N'
            );

            v_hand_count := v_hand_count + 1;
        END LOOP;
    END draw_player_to_target;

    FUNCTION game_attack_limit (
        p_game_id                IN NUMBER,
        p_max_pairs              IN NUMBER,
        p_defender_hand_size     IN NUMBER,
        p_limit_by_defender_hand IN VARCHAR2
    ) RETURN NUMBER IS
        v_talon_count NUMBER;
    BEGIN
        -- Домашнее ослабление лимита действует только после закрытия талона.
        -- Пока в талоне есть карты, базовый предел по руке обязателен.
        IF p_limit_by_defender_hand = 'N' THEN
            SELECT COUNT(*)
            INTO v_talon_count
            FROM durak_game_card
            WHERE game_id = p_game_id
              AND card_zone = 'TALON';

            IF v_talon_count = 0 THEN
                RETURN p_max_pairs;
            END IF;
        END IF;

        RETURN durak_rules.effective_attack_limit(
            p_max_pairs,
            p_defender_hand_size
        );
    END game_attack_limit;

    PROCEDURE draw_after_round (
        p_game_id              IN NUMBER,
        p_primary_attacker_seat IN NUMBER,
        p_defender_seat         IN NUMBER
    ) IS
    BEGIN
        FOR r IN (
            SELECT seat_no
            FROM durak_game_player
            WHERE game_id = p_game_id
              AND player_status = 'ACTIVE'
              AND seat_no <> p_defender_seat
            ORDER BY CASE
                WHEN seat_no >= p_primary_attacker_seat
                    THEN seat_no - p_primary_attacker_seat
                ELSE seat_no + 6 - p_primary_attacker_seat
            END
        ) LOOP
            draw_player_to_target(p_game_id, r.seat_no);
        END LOOP;

        FOR r IN (
            SELECT seat_no
            FROM durak_game_player
            WHERE game_id = p_game_id
              AND player_status = 'ACTIVE'
              AND seat_no = p_defender_seat
        ) LOOP
            draw_player_to_target(p_game_id, r.seat_no);
        END LOOP;
    END draw_after_round;

    PROCEDURE record_daily_results (
        p_game_id IN NUMBER
    ) IS
    BEGIN
        FOR r IN (
            SELECT
                g.daily_id,
                g.game_id,
                gp.player_id,
                gp.result_code,
                gp.finish_place,
                g.current_round_no AS rounds_played,
                (
                    SELECT COUNT(*)
                    FROM durak_event e
                    WHERE e.game_id = g.game_id
                      AND e.actor_player_id = gp.player_id
                      AND e.event_type IN (
                          'ATTACK', 'DEFEND', 'THROW_IN', 'TRANSFER',
                          'PASS', 'TAKE_DECLARED'
                      )
                ) AS actions_count,
                CASE
                    WHEN g.started_at IS NULL OR g.finished_at IS NULL THEN 0
                    ELSE GREATEST(
                        0,
                        ROUND(
                            EXTRACT(DAY FROM (g.finished_at - g.started_at)) * 86400
                            + EXTRACT(HOUR FROM (g.finished_at - g.started_at)) * 3600
                            + EXTRACT(MINUTE FROM (g.finished_at - g.started_at)) * 60
                            + EXTRACT(SECOND FROM (g.finished_at - g.started_at))
                        )
                    )
                END AS duration_sec
            FROM durak_game g
            JOIN durak_game_player gp
              ON gp.game_id = g.game_id
            WHERE g.game_id = p_game_id
              AND g.daily_id IS NOT NULL
              AND g.game_status = 'FINISHED'
              AND gp.result_code IN ('WIN', 'LOSS', 'DRAW')
        ) LOOP
            BEGIN
                INSERT INTO durak_daily_result (
                    daily_result_id,
                    daily_id,
                    game_id,
                    player_id,
                    result_code,
                    finish_place,
                    rounds_played,
                    actions_count,
                    duration_sec
                ) VALUES (
                    durak_id_seq.NEXTVAL,
                    r.daily_id,
                    r.game_id,
                    r.player_id,
                    r.result_code,
                    r.finish_place,
                    r.rounds_played,
                    r.actions_count,
                    r.duration_sec
                );
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    NULL;
            END;
        END LOOP;
    END record_daily_results;

    FUNCTION finish_if_needed (
        p_game_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_talon_count  NUMBER;
        v_active_count NUMBER;
        v_fool_seat    NUMBER;
        v_fool_player  NUMBER;
        v_fool_name    VARCHAR2(100);
        v_next_place   NUMBER;
        v_first_new_place NUMBER;
        v_fool_place   NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_talon_count
        FROM durak_game_card
        WHERE game_id = p_game_id
          AND card_zone = 'TALON';

        IF v_talon_count > 0 THEN
            RETURN FALSE;
        END IF;

        SELECT NVL(MAX(finish_place), 0) + 1
        INTO v_next_place
        FROM durak_game_player
        WHERE game_id = p_game_id;

        v_first_new_place := v_next_place;

        FOR r IN (
            SELECT gp.seat_no, gp.player_id, p.display_name
            FROM durak_game_player gp
            JOIN durak_player p ON p.player_id = gp.player_id
            WHERE gp.game_id = p_game_id
              AND gp.player_status = 'ACTIVE'
              AND gp.hand_count = 0
            ORDER BY gp.seat_no
        ) LOOP
            UPDATE durak_game_player
            SET player_status = 'OUT',
                result_code = 'WIN',
                finish_place = v_next_place,
                exited_at = SYSTIMESTAMP
            WHERE game_id = p_game_id
              AND seat_no = r.seat_no;

            v_next_place := v_next_place + 1;

            append_simple_event(
                p_game_id         => p_game_id,
                p_event_type      => 'PLAYER_OUT',
                p_message         => 'Игрок ' || r.display_name || ' вышел из игры.',
                p_actor_player_id => r.player_id,
                p_actor_seat_no   => r.seat_no
            );
        END LOOP;

        SELECT COUNT(*)
        INTO v_active_count
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_status = 'ACTIVE';

        IF v_active_count = 0 THEN
            UPDATE durak_game_player
            SET result_code = 'DRAW',
                finish_place = v_first_new_place
            WHERE game_id = p_game_id
              AND player_status = 'OUT'
              AND finish_place >= v_first_new_place;

            UPDATE durak_game
            SET game_status = 'FINISHED',
                phase = 'FINISHED',
                current_actor_seat_no = NULL,
                action_deadline_at = NULL,
                fool_seat_no = NULL,
                finish_reason = 'DRAW',
                finished_at = SYSTIMESTAMP,
                last_activity_at = SYSTIMESTAMP,
                version_no = version_no + 1
            WHERE game_id = p_game_id;

            append_simple_event(
                p_game_id    => p_game_id,
                p_event_type => 'GAME_FINISHED',
                p_message    => 'Партия завершена вничью: игроков с картами не осталось.'
            );
            record_daily_results(p_game_id);
            durak_tournament_pkg.record_game_result(p_game_id);
            release_sessions(p_game_id);
            RETURN TRUE;
        END IF;

        IF v_active_count = 1 THEN
            SELECT gp.seat_no, gp.player_id, p.display_name
            INTO v_fool_seat, v_fool_player, v_fool_name
            FROM durak_game_player gp
            JOIN durak_player p ON p.player_id = gp.player_id
            WHERE gp.game_id = p_game_id
              AND gp.player_status = 'ACTIVE';

            SELECT COUNT(*)
            INTO v_fool_place
            FROM durak_game_player
            WHERE game_id = p_game_id;

            UPDATE durak_game_player
            SET player_status = 'FOOL',
                result_code = 'LOSS',
                finish_place = v_fool_place,
                exited_at = SYSTIMESTAMP
            WHERE game_id = p_game_id
              AND seat_no = v_fool_seat;

            UPDATE durak_game
            SET game_status = 'FINISHED',
                phase = 'FINISHED',
                current_actor_seat_no = NULL,
                action_deadline_at = NULL,
                fool_seat_no = v_fool_seat,
                finish_reason = 'ONE_PLAYER_REMAINED',
                finished_at = SYSTIMESTAMP,
                last_activity_at = SYSTIMESTAMP,
                version_no = version_no + 1
            WHERE game_id = p_game_id;

            append_simple_event(
                p_game_id         => p_game_id,
                p_event_type      => 'GAME_FINISHED',
                p_message         => 'Партия завершена. Дурак — ' || v_fool_name || '.',
                p_actor_player_id => v_fool_player,
                p_actor_seat_no   => v_fool_seat
            );
            record_daily_results(p_game_id);
            durak_tournament_pkg.record_game_result(p_game_id);
            release_sessions(p_game_id);
            RETURN TRUE;
        END IF;

        RETURN FALSE;
    END finish_if_needed;

    PROCEDURE start_next_round (
        p_game_id                 IN NUMBER,
        p_preferred_attacker_seat IN NUMBER
    ) IS
        v_game          durak_game%ROWTYPE;
        v_attacker      NUMBER;
        v_defender      NUMBER;
        v_defender_hand NUMBER;
        v_active        NUMBER;
        v_round_no      NUMBER;
        v_attack_limit  NUMBER;
    BEGIN
        SELECT *
        INTO v_game
        FROM durak_game
        WHERE game_id = p_game_id;

        SELECT COUNT(*)
        INTO v_active
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND seat_no = p_preferred_attacker_seat
          AND player_status = 'ACTIVE';

        IF v_active = 1 THEN
            v_attacker := p_preferred_attacker_seat;
        ELSE
            v_attacker := durak_rules.next_active_seat(
                p_game_id,
                p_preferred_attacker_seat
            );
        END IF;

        v_defender := durak_rules.next_active_seat(p_game_id, v_attacker);

        IF v_attacker IS NULL OR v_defender IS NULL THEN
            fail(-20724, 'Невозможно определить участников следующего раунда.');
        END IF;

        SELECT hand_count
        INTO v_defender_hand
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND seat_no = v_defender;

        v_round_no := v_game.current_round_no + 1;
        v_attack_limit := game_attack_limit(
            p_game_id,
            v_game.max_pairs,
            v_defender_hand,
            v_game.limit_by_defender_hand
        );

        INSERT INTO durak_round (
            game_id,
            round_no,
            primary_attacker_seat_no,
            initial_defender_seat_no,
            defender_seat_no,
            throw_cursor_seat_no,
            defender_hand_at_start,
            attack_limit
        ) VALUES (
            p_game_id,
            v_round_no,
            v_attacker,
            v_defender,
            v_defender,
            v_attacker,
            v_defender_hand,
            v_attack_limit
        );

        UPDATE durak_game
        SET current_round_no = v_round_no,
            attacker_seat_no = v_attacker,
            defender_seat_no = v_defender,
            current_actor_seat_no = v_attacker,
            phase = 'WAIT_ATTACK'
        WHERE game_id = p_game_id;

        touch_game(p_game_id);

        append_simple_event(
            p_game_id      => p_game_id,
            p_event_type   => 'ROUND_STARTED',
            p_message      => 'Начат раунд ' || v_round_no
                || ': атакует место ' || v_attacker
                || ', защищается место ' || v_defender || '.',
            p_actor_seat_no => v_attacker,
            p_target_seat_no => v_defender
        );
    END start_next_round;

    PROCEDURE resolve_defended (
        p_game_id IN NUMBER
    ) IS
        v_round        durak_round%ROWTYPE;
        v_open_count   NUMBER;
        v_event_id     NUMBER;
        v_event_no     NUMBER;
    BEGIN
        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = (
              SELECT current_round_no
              FROM durak_game
              WHERE game_id = p_game_id
          );

        SELECT COUNT(*)
        INTO v_open_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_round.round_no
          AND pair_status = 'OPEN';

        IF v_open_count > 0 THEN
            fail(-20725, 'Нельзя завершить отбой: не все карты покрыты.');
        END IF;

        append_event(
            p_game_id    => p_game_id,
            p_event_type => 'DISCARD',
            p_message    => 'Все атакующие карты покрыты. Стол отправлен в отбой.',
            p_event_id   => v_event_id,
            p_event_no   => v_event_no
        );

        FOR r IN (
            SELECT card_id, card_zone, table_pair_no
            FROM durak_game_card
            WHERE game_id = p_game_id
              AND card_zone IN ('ATTACK', 'DEFENSE')
            ORDER BY table_pair_no, card_zone
        ) LOOP
            UPDATE durak_game_card
            SET card_zone = 'DISCARD',
                owner_seat_no = NULL,
                table_pair_no = NULL,
                is_face_up = 'Y',
                changed_at = SYSTIMESTAMP
            WHERE game_id = p_game_id
              AND card_id = r.card_id;

            append_card_move(
                p_event_id         => v_event_id,
                p_game_id          => p_game_id,
                p_card_id          => r.card_id,
                p_from_zone        => r.card_zone,
                p_to_zone          => 'DISCARD',
                p_from_pair_no     => r.table_pair_no,
                p_is_face_up_after => 'Y'
            );
        END LOOP;

        UPDATE durak_table_pair
        SET pair_status = 'DISCARDED'
        WHERE game_id = p_game_id
          AND round_no = v_round.round_no;

        UPDATE durak_round
        SET round_status = 'DEFENDED',
            ended_at = SYSTIMESTAMP,
            outcome_reason = 'ALL_COVERED'
        WHERE game_id = p_game_id
          AND round_no = v_round.round_no;

        draw_after_round(
            p_game_id,
            v_round.primary_attacker_seat_no,
            v_round.defender_seat_no
        );

        IF NOT finish_if_needed(p_game_id) THEN
            start_next_round(p_game_id, v_round.defender_seat_no);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END resolve_defended;

    PROCEDURE resolve_taken (
        p_game_id IN NUMBER
    ) IS
        v_round      durak_round%ROWTYPE;
        v_event_id   NUMBER;
        v_event_no   NUMBER;
        v_card_count NUMBER := 0;
        v_next_start NUMBER;
    BEGIN
        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = (
              SELECT current_round_no
              FROM durak_game
              WHERE game_id = p_game_id
          );

        append_event(
            p_game_id        => p_game_id,
            p_event_type     => 'TAKE',
            p_message        => 'Защитник забрал все карты со стола.',
            p_event_id       => v_event_id,
            p_event_no       => v_event_no,
            p_actor_seat_no  => v_round.defender_seat_no,
            p_target_seat_no => v_round.defender_seat_no
        );

        FOR r IN (
            SELECT card_id, card_zone, table_pair_no
            FROM durak_game_card
            WHERE game_id = p_game_id
              AND card_zone IN ('ATTACK', 'DEFENSE')
            ORDER BY table_pair_no, card_zone
        ) LOOP
            v_card_count := v_card_count + 1;

            UPDATE durak_game_card
            SET card_zone = 'HAND',
                owner_seat_no = v_round.defender_seat_no,
                table_pair_no = NULL,
                received_seq = v_event_no * 100 + v_card_count,
                is_face_up = 'N',
                changed_at = SYSTIMESTAMP
            WHERE game_id = p_game_id
              AND card_id = r.card_id;

            append_card_move(
                p_event_id         => v_event_id,
                p_game_id          => p_game_id,
                p_card_id          => r.card_id,
                p_from_zone        => r.card_zone,
                p_to_zone          => 'HAND',
                p_to_owner_seat_no => v_round.defender_seat_no,
                p_from_pair_no     => r.table_pair_no,
                p_is_face_up_after => 'N'
            );
        END LOOP;

        UPDATE durak_game_player
        SET hand_count = hand_count + v_card_count
        WHERE game_id = p_game_id
          AND seat_no = v_round.defender_seat_no;

        UPDATE durak_table_pair
        SET pair_status = 'TAKEN'
        WHERE game_id = p_game_id
          AND round_no = v_round.round_no;

        UPDATE durak_round
        SET round_status = 'TAKEN',
            take_declared = 'Y',
            ended_at = SYSTIMESTAMP,
            outcome_reason = 'DEFENDER_TOOK'
        WHERE game_id = p_game_id
          AND round_no = v_round.round_no;

        draw_after_round(
            p_game_id,
            v_round.primary_attacker_seat_no,
            v_round.defender_seat_no
        );

        IF NOT finish_if_needed(p_game_id) THEN
            v_next_start := durak_rules.next_active_seat(
                p_game_id,
                v_round.defender_seat_no
            );
            start_next_round(p_game_id, v_next_start);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END resolve_taken;

    PROCEDURE create_game (
        p_creator_player_id   IN NUMBER,
        p_deck_size           IN NUMBER DEFAULT 36,
        p_game_variant        IN VARCHAR2 DEFAULT 'PODKIDNOY',
        p_first_move_mode     IN VARCHAR2 DEFAULT 'LOWEST_TRUMP',
        p_max_pairs           IN NUMBER DEFAULT NULL,
        p_turn_timeout_sec    IN NUMBER DEFAULT 60,
        p_idle_timeout_min    IN NUMBER DEFAULT 30,
        p_allow_throw_after_take IN VARCHAR2 DEFAULT 'N',
        p_limit_by_defender_hand IN VARCHAR2 DEFAULT 'Y',
        p_seed_text           IN VARCHAR2 DEFAULT NULL,
        p_daily_id            IN NUMBER DEFAULT NULL,
        p_game_id             OUT NUMBER
    ) IS
        v_player       durak_player%ROWTYPE;
        v_daily        durak_daily%ROWTYPE;
        v_seed         VARCHAR2(128);
        v_variant      VARCHAR2(12) := UPPER(TRIM(p_game_variant));
        v_first        VARCHAR2(20) := UPPER(TRIM(p_first_move_mode));
        v_max_pairs    NUMBER;
        v_throw_after  CHAR(1);
        v_limit_hand   CHAR(1);
    BEGIN
        require_player(p_creator_player_id, v_player);
        assert_no_active_session(p_creator_player_id);

        IF p_deck_size IS NULL OR p_deck_size NOT IN (36, 52) THEN
            fail(-20707, 'Размер колоды должен быть 36 или 52.');
        END IF;
        IF v_variant IS NULL OR v_variant NOT IN ('PODKIDNOY', 'PEREVODNOY') THEN
            fail(-20708, 'Вариант должен быть PODKIDNOY или PEREVODNOY.');
        END IF;
        IF v_first IS NULL OR v_first NOT IN ('LOWEST_TRUMP', 'SEEDED_RANDOM') THEN
            fail(-20709, 'Неизвестный способ выбора первого хода.');
        END IF;
        IF p_turn_timeout_sec IS NULL
           OR p_turn_timeout_sec < 0
           OR p_turn_timeout_sec > 86400
           OR p_turn_timeout_sec <> TRUNC(p_turn_timeout_sec) THEN
            fail(-20710, 'Таймер хода должен быть целым числом от 0 до 86400.');
        END IF;
        IF p_idle_timeout_min IS NULL
           OR p_idle_timeout_min < 1
           OR p_idle_timeout_min > 10080
           OR p_idle_timeout_min <> TRUNC(p_idle_timeout_min) THEN
            fail(-20711, 'Таймер простоя должен быть целым числом от 1 до 10080.');
        END IF;

        v_max_pairs := NVL(p_max_pairs, durak_rules.default_max_pairs(p_deck_size));
        IF v_max_pairs < 1
           OR v_max_pairs > durak_rules.default_max_pairs(p_deck_size)
           OR v_max_pairs <> TRUNC(v_max_pairs) THEN
            fail(-20712, 'Некорректный максимальный размер стола.');
        END IF;

        v_throw_after := normalized_flag(
            p_allow_throw_after_take,
            'allow_throw_after_take'
        );
        v_limit_hand := normalized_flag(
            p_limit_by_defender_hand,
            'limit_by_defender_hand'
        );
        IF p_daily_id IS NOT NULL THEN
            BEGIN
                SELECT *
                INTO v_daily
                FROM durak_daily
                WHERE daily_id = p_daily_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    fail(-20757, 'Daily-конфигурация не найдена.');
            END;

            IF v_daily.deck_size <> p_deck_size
               OR v_daily.game_variant <> v_variant
               OR v_daily.first_move_mode <> v_first THEN
                fail(-20758, 'Параметры партии не совпадают с Daily-конфигурацией.');
            END IF;

            v_seed := v_daily.seed_text;
        ELSE
            v_seed := CASE
                WHEN TRIM(p_seed_text) IS NULL THEN durak_random.generated_seed
                ELSE durak_random.normalize_seed(p_seed_text)
            END;
        END IF;

        p_game_id := durak_id_seq.NEXTVAL;

        INSERT INTO durak_game (
            game_id,
            created_by_player_id,
            daily_id,
            deck_size,
            game_variant,
            first_move_mode,
            target_hand_size,
            max_pairs,
            allow_throw_after_take,
            limit_by_defender_hand,
            turn_timeout_sec,
            idle_timeout_min,
            seed_text,
            seed_hash,
            shuffle_version
        ) VALUES (
            p_game_id,
            p_creator_player_id,
            p_daily_id,
            p_deck_size,
            v_variant,
            v_first,
            c_target_hand_size,
            v_max_pairs,
            v_throw_after,
            v_limit_hand,
            p_turn_timeout_sec,
            p_idle_timeout_min,
            v_seed,
            durak_random.game_seed_hash(
                v_seed,
                p_deck_size,
                v_variant,
                durak_random.c_shuffle_version
            ),
            durak_random.c_shuffle_version
        );

        INSERT INTO durak_game_player (
            game_id,
            seat_no,
            player_id,
            player_status,
            is_creator
        ) VALUES (
            p_game_id,
            1,
            p_creator_player_id,
            'WAITING',
            'Y'
        );

        reserve_session(p_creator_player_id, p_game_id);

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'GAME_CREATED',
            p_message         => 'Партия создана игроком ' || v_player.display_name || '.',
            p_source          => 'MANUAL',
            p_actor_player_id => p_creator_player_id,
            p_actor_seat_no   => 1
        );
    END create_game;

    PROCEDURE join_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_seat_no   OUT NUMBER
    ) IS
        v_game         durak_game%ROWTYPE;
        v_player       durak_player%ROWTYPE;
        v_count        NUMBER;
        v_already_seat NUMBER;
    BEGIN
        require_player(p_player_id, v_player);
        assert_no_active_session(p_player_id);
        lock_game(p_game_id, v_game);

        IF v_game.game_status <> 'LOBBY' THEN
            fail(-20713, 'Присоединиться можно только к партии в лобби.');
        END IF;

        SELECT MAX(seat_no)
        INTO v_already_seat
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_id = p_player_id;

        IF v_already_seat IS NOT NULL THEN
            fail(-20714, 'Игрок уже находится в этой партии.');
        END IF;

        SELECT COUNT(*)
        INTO v_count
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_status = 'WAITING';

        IF v_count >= 6 THEN
            fail(-20715, 'В партии уже заняты все 6 мест.');
        END IF;

        SELECT MIN(candidate_seat)
        INTO p_seat_no
        FROM (
            SELECT LEVEL AS candidate_seat
            FROM dual
            CONNECT BY LEVEL <= 6
        ) seats
        WHERE NOT EXISTS (
            SELECT 1
            FROM durak_game_player gp
            WHERE gp.game_id = p_game_id
              AND gp.seat_no = seats.candidate_seat
        );

        INSERT INTO durak_game_player (
            game_id,
            seat_no,
            player_id,
            player_status,
            is_creator
        ) VALUES (
            p_game_id,
            p_seat_no,
            p_player_id,
            'WAITING',
            'N'
        );

        reserve_session(p_player_id, p_game_id);
        touch_game(p_game_id, p_player_id);

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'PLAYER_JOINED',
            p_message         => 'Игрок ' || v_player.display_name
                || ' занял место ' || p_seat_no || '.',
            p_source          => 'MANUAL',
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => p_seat_no
        );
    END join_game;

    PROCEDURE start_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_game            durak_game%ROWTYPE;
        v_game_player     durak_game_player%ROWTYPE;
        v_player_count    NUMBER;
        v_deal_count      NUMBER;
        v_attempt         PLS_INTEGER := 0;
        v_effective_ver   VARCHAR2(20);
        v_trump_card_id   NUMBER;
        v_trump_suit      CHAR(1);
        v_dealt_trumps    NUMBER;
        v_deck_pos        NUMBER := 0;
        v_card_id         NUMBER;
        v_event_id        NUMBER;
        v_event_no        NUMBER;
        v_attacker        NUMBER;
        v_defender        NUMBER;
        v_defender_hand   NUMBER;
        v_attack_limit    NUMBER;
        v_seeded_position NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'LOBBY' THEN
            fail(-20716, 'Партия уже запущена или завершена.');
        END IF;
        IF v_game_player.is_creator <> 'Y' THEN
            fail(-20717, 'Запустить партию может только её создатель.');
        END IF;

        SELECT COUNT(*)
        INTO v_player_count
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_status = 'WAITING';

        IF v_player_count NOT BETWEEN 2 AND 6 THEN
            fail(-20718, 'Для старта требуется от 2 до 6 игроков.');
        END IF;

        SELECT COUNT(*)
        INTO v_dealt_trumps
        FROM durak_game_card
        WHERE game_id = p_game_id;
        IF v_dealt_trumps > 0 THEN
            fail(-20719, 'Колода этой партии уже сформирована.');
        END IF;

        v_deal_count := v_player_count * c_target_hand_size;

        LOOP
            v_effective_ver := durak_random.c_shuffle_version
                || CASE WHEN v_attempt = 0 THEN NULL ELSE '-R' || v_attempt END;

            INSERT INTO durak_game_card (
                game_id,
                card_id,
                deck_pos,
                card_zone,
                is_face_up
            )
            SELECT
                p_game_id,
                ordered.card_id,
                ordered.deck_pos,
                'TALON',
                'N'
            FROM (
                SELECT
                    c.card_id,
                    ROW_NUMBER() OVER (
                        ORDER BY RAWTOHEX(
                            durak_random.card_shuffle_key(
                                v_game.seed_text,
                                v_game.deck_size,
                                v_game.game_variant,
                                v_effective_ver,
                                c.card_code
                            )
                        ), c.card_id
                    ) AS deck_pos
                FROM durak_card c
                WHERE v_game.deck_size = 52
                   OR c.included_in_36 = 'Y'
            ) ordered;

            SELECT gc.card_id, c.suit_code
            INTO v_trump_card_id, v_trump_suit
            FROM durak_game_card gc
            JOIN durak_card c ON c.card_id = gc.card_id
            WHERE gc.game_id = p_game_id
              AND gc.deck_pos = v_game.deck_size;

            SELECT COUNT(*)
            INTO v_dealt_trumps
            FROM durak_game_card gc
            JOIN durak_card c ON c.card_id = gc.card_id
            WHERE gc.game_id = p_game_id
              AND gc.deck_pos <= v_deal_count
              AND c.suit_code = v_trump_suit;

            EXIT WHEN v_dealt_trumps > 0;

            DELETE FROM durak_game_card
            WHERE game_id = p_game_id;

            v_attempt := v_attempt + 1;
            IF v_attempt > 99 THEN
                fail(-20726, 'Не удалось сформировать раздачу с козырем на руках.');
            END IF;
        END LOOP;

        UPDATE durak_game_card
        SET is_face_up = 'Y'
        WHERE game_id = p_game_id
          AND card_id = v_trump_card_id;

        UPDATE durak_game
        SET trump_card_id = v_trump_card_id,
            trump_suit = v_trump_suit,
            shuffle_version = v_effective_ver,
            seed_hash = durak_random.game_seed_hash(
                seed_text,
                deck_size,
                game_variant,
                v_effective_ver
            )
        WHERE game_id = p_game_id;

        append_event(
            p_game_id    => p_game_id,
            p_event_type => 'SHUFFLED',
            p_message    => 'Колода перемешана детерминированно. Козырь — '
                || v_trump_suit || '.',
            p_event_id   => v_event_id,
            p_event_no   => v_event_no,
            p_card_id    => v_trump_card_id
        );

        FOR deal_round IN 1 .. c_target_hand_size LOOP
            FOR seat_row IN (
                SELECT seat_no
                FROM durak_game_player
                WHERE game_id = p_game_id
                  AND player_status = 'WAITING'
                ORDER BY seat_no
            ) LOOP
                v_deck_pos := v_deck_pos + 1;

                SELECT card_id
                INTO v_card_id
                FROM durak_game_card
                WHERE game_id = p_game_id
                  AND deck_pos = v_deck_pos;

                append_event(
                    p_game_id            => p_game_id,
                    p_event_type         => 'DEALT',
                    p_message            => 'Игроку выдана карта.',
                    p_event_id           => v_event_id,
                    p_event_no           => v_event_no,
                    p_card_id            => v_card_id,
                    p_target_seat_no      => seat_row.seat_no,
                    p_visibility         => 'PRIVATE',
                    p_visible_to_seat_no => seat_row.seat_no
                );

                UPDATE durak_game_card
                SET card_zone = 'HAND',
                    owner_seat_no = seat_row.seat_no,
                    received_seq = v_event_no,
                    is_face_up = 'N',
                    changed_at = SYSTIMESTAMP
                WHERE game_id = p_game_id
                  AND card_id = v_card_id;

                UPDATE durak_game_player
                SET hand_count = hand_count + 1
                WHERE game_id = p_game_id
                  AND seat_no = seat_row.seat_no;

                append_card_move(
                    p_event_id         => v_event_id,
                    p_game_id          => p_game_id,
                    p_card_id          => v_card_id,
                    p_from_zone        => 'TALON',
                    p_to_zone          => 'HAND',
                    p_to_owner_seat_no => seat_row.seat_no,
                    p_is_face_up_after => 'N'
                );
            END LOOP;
        END LOOP;

        UPDATE durak_game_player
        SET player_status = 'ACTIVE'
        WHERE game_id = p_game_id
          AND player_status = 'WAITING';

        IF v_game.first_move_mode = 'LOWEST_TRUMP' THEN
            SELECT owner_seat_no
            INTO v_attacker
            FROM (
                SELECT gc.owner_seat_no, c.rank_value, gc.deck_pos
                FROM durak_game_card gc
                JOIN durak_card c ON c.card_id = gc.card_id
                WHERE gc.game_id = p_game_id
                  AND gc.card_zone = 'HAND'
                  AND c.suit_code = v_trump_suit
                ORDER BY c.rank_value, gc.owner_seat_no, gc.deck_pos
            )
            WHERE ROWNUM = 1;
        ELSE
            v_seeded_position := durak_random.seeded_position(
                v_game.seed_text,
                'FIRST-ATTACKER',
                v_player_count
            );

            SELECT seat_no
            INTO v_attacker
            FROM (
                SELECT seat_no, ROW_NUMBER() OVER (ORDER BY seat_no) AS rn
                FROM durak_game_player
                WHERE game_id = p_game_id
                  AND player_status = 'ACTIVE'
            )
            WHERE rn = v_seeded_position;
        END IF;

        v_defender := durak_rules.next_active_seat(p_game_id, v_attacker);

        SELECT hand_count
        INTO v_defender_hand
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND seat_no = v_defender;

        v_attack_limit := game_attack_limit(
            p_game_id,
            v_game.max_pairs,
            v_defender_hand,
            v_game.limit_by_defender_hand
        );

        INSERT INTO durak_round (
            game_id,
            round_no,
            primary_attacker_seat_no,
            initial_defender_seat_no,
            defender_seat_no,
            throw_cursor_seat_no,
            defender_hand_at_start,
            attack_limit
        ) VALUES (
            p_game_id,
            1,
            v_attacker,
            v_defender,
            v_defender,
            v_attacker,
            v_defender_hand,
            v_attack_limit
        );

        UPDATE durak_game
        SET game_status = 'ACTIVE',
            phase = 'WAIT_ATTACK',
            current_round_no = 1,
            attacker_seat_no = v_attacker,
            defender_seat_no = v_defender,
            current_actor_seat_no = v_attacker,
            started_at = SYSTIMESTAMP,
            last_activity_at = SYSTIMESTAMP
        WHERE game_id = p_game_id;

        touch_game(p_game_id, p_player_id);

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'GAME_STARTED',
            p_message         => 'Партия началась. Первым атакует место '
                || v_attacker || '.',
            p_source          => 'MANUAL',
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no,
            p_target_seat_no  => v_attacker
        );

        append_simple_event(
            p_game_id          => p_game_id,
            p_event_type       => 'ROUND_STARTED',
            p_message          => 'Начат раунд 1.',
            p_actor_seat_no    => v_attacker,
            p_target_seat_no   => v_defender
        );
    END start_game;

    PROCEDURE attack (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    ) IS
        v_game        durak_game%ROWTYPE;
        v_game_player durak_game_player%ROWTYPE;
        v_round       durak_round%ROWTYPE;
        v_card_id     NUMBER;
        v_pair_count  NUMBER;
        v_event_id    NUMBER;
        v_event_no    NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE' OR v_game.phase <> 'WAIT_ATTACK' THEN
            fail(-20730, 'Сейчас нельзя начинать атаку.');
        END IF;
        IF v_game_player.player_status <> 'ACTIVE' THEN
            fail(-20731, 'Игрок уже вышел или не активен.');
        END IF;
        IF v_game.current_actor_seat_no <> v_game_player.seat_no
           OR v_game.attacker_seat_no <> v_game_player.seat_no THEN
            fail(-20732, 'Первую карту должен положить текущий атакующий.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_pair_count <> 0 THEN
            fail(-20733, 'Первая атака этого раунда уже сделана.');
        END IF;

        v_card_id := find_hand_card(
            p_game_id,
            v_game_player.seat_no,
            p_card_code
        );

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'ATTACK',
            p_message         => 'Игрок с места ' || v_game_player.seat_no
                || ' начал атаку картой ' || UPPER(TRIM(p_card_code)) || '.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no,
            p_card_id         => v_card_id,
            p_target_pair_no  => 1,
            p_target_seat_no  => v_game.defender_seat_no
        );

        move_hand_card_to_table(
            p_game_id => p_game_id,
            p_seat_no => v_game_player.seat_no,
            p_card_id => v_card_id,
            p_pair_no => 1,
            p_zone => 'ATTACK',
            p_event_id => v_event_id
        );

        INSERT INTO durak_table_pair (
            game_id,
            round_no,
            pair_no,
            attack_card_id,
            attacking_seat_no,
            attack_event_no
        ) VALUES (
            p_game_id,
            v_game.current_round_no,
            1,
            v_card_id,
            v_game_player.seat_no,
            v_event_no
        );

        UPDATE durak_round
        SET throw_cursor_seat_no = v_round.primary_attacker_seat_no,
            consecutive_passes = 0
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        UPDATE durak_game
        SET phase = 'WAIT_DEFENSE',
            current_actor_seat_no = v_game.defender_seat_no
        WHERE game_id = p_game_id;

        touch_game(p_game_id, p_player_id);
        finalize_event_state(p_game_id, v_event_id);
    END attack;

    PROCEDURE defend (
        p_player_id         IN NUMBER,
        p_game_id           IN NUMBER,
        p_defense_card_code IN VARCHAR2,
        p_pair_no           IN NUMBER DEFAULT NULL
    ) IS
        v_game         durak_game%ROWTYPE;
        v_game_player  durak_game_player%ROWTYPE;
        v_round        durak_round%ROWTYPE;
        v_pair_no      NUMBER;
        v_attack_card  NUMBER;
        v_defense_card NUMBER;
        v_open_count   NUMBER;
        v_pair_count   NUMBER;
        v_event_id     NUMBER;
        v_event_no     NUMBER;
        v_thrower      NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE' OR v_game.phase <> 'WAIT_DEFENSE' THEN
            fail(-20734, 'Сейчас нет карты, которую требуется покрыть.');
        END IF;
        IF v_game_player.player_status <> 'ACTIVE'
           OR v_game_player.seat_no <> v_game.defender_seat_no
           OR v_game.current_actor_seat_no <> v_game_player.seat_no THEN
            fail(-20735, 'Защищаться должен текущий защитник.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        IF p_pair_no IS NULL THEN
            SELECT MIN(pair_no)
            INTO v_pair_no
            FROM durak_table_pair
            WHERE game_id = p_game_id
              AND round_no = v_game.current_round_no
              AND pair_status = 'OPEN';
        ELSE
            v_pair_no := p_pair_no;
        END IF;

        BEGIN
            SELECT attack_card_id
            INTO v_attack_card
            FROM durak_table_pair
            WHERE game_id = p_game_id
              AND round_no = v_game.current_round_no
              AND pair_no = v_pair_no
              AND pair_status = 'OPEN';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fail(-20736, 'Открытая пара ' || v_pair_no || ' не найдена.');
        END;

        v_defense_card := find_hand_card(
            p_game_id,
            v_game_player.seat_no,
            p_defense_card_code
        );

        IF durak_rules.can_beat(
            v_attack_card,
            v_defense_card,
            v_game.trump_suit
        ) = 0 THEN
            fail(
                -20737,
                'Карта ' || UPPER(TRIM(p_defense_card_code))
                || ' не бьёт выбранную атакующую карту.'
            );
        END IF;

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'DEFEND',
            p_message         => 'Защитник покрыл пару ' || v_pair_no
                || ' картой ' || UPPER(TRIM(p_defense_card_code)) || '.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no,
            p_card_id         => v_defense_card,
            p_target_pair_no  => v_pair_no
        );

        move_hand_card_to_table(
            p_game_id => p_game_id,
            p_seat_no => v_game_player.seat_no,
            p_card_id => v_defense_card,
            p_pair_no => v_pair_no,
            p_zone => 'DEFENSE',
            p_event_id => v_event_id
        );

        UPDATE durak_table_pair
        SET defense_card_id = v_defense_card,
            defending_seat_no = v_game_player.seat_no,
            pair_status = 'COVERED',
            defense_event_no = v_event_no,
            covered_at = SYSTIMESTAMP
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND pair_no = v_pair_no
          AND pair_status = 'OPEN';

        IF SQL%ROWCOUNT <> 1 THEN
            fail(-20738, 'Пара уже была покрыта другим действием.');
        END IF;

        UPDATE durak_round
        SET defense_started = 'Y'
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        SELECT COUNT(*)
        INTO v_open_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND pair_status = 'OPEN';

        IF v_open_count > 0 THEN
            UPDATE durak_game
            SET current_actor_seat_no = v_game.defender_seat_no,
                phase = 'WAIT_DEFENSE'
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        ELSIF v_pair_count >= v_round.attack_limit THEN
            touch_game(p_game_id, p_player_id);
            resolve_defended(p_game_id);
        ELSE
            v_thrower := NVL(
                v_round.throw_cursor_seat_no,
                v_round.primary_attacker_seat_no
            );

            UPDATE durak_game
            SET current_actor_seat_no = v_thrower,
                phase = 'WAIT_THROW'
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END defend;

    PROCEDURE throw_in (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    ) IS
        v_game        durak_game%ROWTYPE;
        v_game_player durak_game_player%ROWTYPE;
        v_round       durak_round%ROWTYPE;
        v_pair_count  NUMBER;
        v_pair_no     NUMBER;
        v_card_id     NUMBER;
        v_event_id    NUMBER;
        v_event_no    NUMBER;
        v_next_thrower NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE'
           OR v_game.phase NOT IN ('WAIT_THROW', 'TAKE_THROW') THEN
            fail(-20739, 'Сейчас подбрасывать нельзя.');
        END IF;
        IF v_game.current_actor_seat_no <> v_game_player.seat_no
           OR v_game_player.player_status <> 'ACTIVE'
           OR v_game_player.seat_no = v_game.defender_seat_no THEN
            fail(-20740, 'Сейчас подбрасывает другой игрок.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_pair_count >= v_round.attack_limit THEN
            fail(-20741, 'Достигнут лимит атакующих карт в раунде.');
        END IF;

        v_card_id := find_hand_card(
            p_game_id,
            v_game_player.seat_no,
            p_card_code
        );

        IF durak_rules.rank_present_on_table(
            p_game_id,
            v_game.current_round_no,
            v_card_id
        ) = 0 THEN
            fail(-20742, 'Подбрасывать можно только достоинство, уже лежащее на столе.');
        END IF;

        v_pair_no := v_pair_count + 1;
        v_next_thrower := next_thrower(
            p_game_id,
            v_game_player.seat_no,
            v_game.defender_seat_no
        );

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'THROW_IN',
            p_message         => 'Игрок с места ' || v_game_player.seat_no
                || ' подбросил карту ' || UPPER(TRIM(p_card_code)) || '.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no,
            p_card_id         => v_card_id,
            p_target_pair_no  => v_pair_no,
            p_target_seat_no  => v_game.defender_seat_no
        );

        move_hand_card_to_table(
            p_game_id => p_game_id,
            p_seat_no => v_game_player.seat_no,
            p_card_id => v_card_id,
            p_pair_no => v_pair_no,
            p_zone => 'ATTACK',
            p_event_id => v_event_id
        );

        INSERT INTO durak_table_pair (
            game_id,
            round_no,
            pair_no,
            attack_card_id,
            attacking_seat_no,
            attack_event_no
        ) VALUES (
            p_game_id,
            v_game.current_round_no,
            v_pair_no,
            v_card_id,
            v_game_player.seat_no,
            v_event_no
        );

        UPDATE durak_round
        SET throw_cursor_seat_no = v_next_thrower,
            consecutive_passes = 0
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_game.phase = 'WAIT_THROW' THEN
            UPDATE durak_game
            SET phase = 'WAIT_DEFENSE',
                current_actor_seat_no = v_game.defender_seat_no
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        ELSIF v_pair_no >= v_round.attack_limit THEN
            touch_game(p_game_id, p_player_id);
            resolve_taken(p_game_id);
        ELSE
            UPDATE durak_game
            SET phase = 'TAKE_THROW',
                current_actor_seat_no = v_next_thrower
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END throw_in;

    PROCEDURE pass_throw (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_game          durak_game%ROWTYPE;
        v_game_player   durak_game_player%ROWTYPE;
        v_round         durak_round%ROWTYPE;
        v_passes        NUMBER;
        v_attackers     NUMBER;
        v_next_thrower  NUMBER;
        v_event_id      NUMBER;
        v_event_no      NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE'
           OR v_game.phase NOT IN ('WAIT_THROW', 'TAKE_THROW') THEN
            fail(-20743, 'Сейчас нельзя пасовать при подбрасывании.');
        END IF;
        IF v_game.current_actor_seat_no <> v_game_player.seat_no
           OR v_game_player.player_status <> 'ACTIVE'
           OR v_game_player.seat_no = v_game.defender_seat_no THEN
            fail(-20744, 'Сейчас решение принимает другой подбрасывающий.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        SELECT COUNT(*)
        INTO v_attackers
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND player_status = 'ACTIVE'
          AND seat_no <> v_game.defender_seat_no;

        v_passes := v_round.consecutive_passes + 1;
        v_next_thrower := next_thrower(
            p_game_id,
            v_game_player.seat_no,
            v_game.defender_seat_no
        );

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'PASS',
            p_message         => 'Игрок с места ' || v_game_player.seat_no
                || ' отказался подбрасывать.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no
        );

        UPDATE durak_round
        SET consecutive_passes = v_passes,
            throw_cursor_seat_no = v_next_thrower
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_passes >= v_attackers THEN
            touch_game(p_game_id, p_player_id);
            IF v_game.phase = 'TAKE_THROW' OR v_round.take_declared = 'Y' THEN
                resolve_taken(p_game_id);
            ELSE
                resolve_defended(p_game_id);
            END IF;
        ELSE
            UPDATE durak_game
            SET current_actor_seat_no = v_next_thrower
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END pass_throw;

    PROCEDURE take_cards (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_game        durak_game%ROWTYPE;
        v_game_player durak_game_player%ROWTYPE;
        v_round       durak_round%ROWTYPE;
        v_pair_count  NUMBER;
        v_event_id    NUMBER;
        v_event_no    NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE' OR v_game.phase <> 'WAIT_DEFENSE' THEN
            fail(-20745, 'Сейчас нельзя объявить взятие карт.');
        END IF;
        IF v_game.current_actor_seat_no <> v_game_player.seat_no
           OR v_game.defender_seat_no <> v_game_player.seat_no
           OR v_game_player.player_status <> 'ACTIVE' THEN
            fail(-20746, 'Взять карты может только текущий защитник.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'TAKE_DECLARED',
            p_message         => 'Защитник объявил взятие карт.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no
        );

        UPDATE durak_round
        SET take_declared = 'Y',
            consecutive_passes = 0,
            throw_cursor_seat_no = primary_attacker_seat_no
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_game.allow_throw_after_take = 'Y'
           AND v_pair_count < v_round.attack_limit THEN
            UPDATE durak_game
            SET phase = 'TAKE_THROW',
                current_actor_seat_no = v_round.primary_attacker_seat_no
            WHERE game_id = p_game_id;
            touch_game(p_game_id, p_player_id);
        ELSE
            touch_game(p_game_id, p_player_id);
            resolve_taken(p_game_id);
        END IF;

        finalize_event_state(p_game_id, v_event_id);
    END take_cards;

    PROCEDURE transfer_attack (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER,
        p_card_code IN VARCHAR2
    ) IS
        v_game             durak_game%ROWTYPE;
        v_game_player      durak_game_player%ROWTYPE;
        v_round            durak_round%ROWTYPE;
        v_card_id          NUMBER;
        v_pair_count       NUMBER;
        v_pair_no          NUMBER;
        v_new_defender     NUMBER;
        v_new_hand_count   NUMBER;
        v_already_attacked NUMBER;
        v_new_limit        NUMBER;
        v_event_id         NUMBER;
        v_event_no         NUMBER;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'ACTIVE'
           OR v_game.game_variant <> 'PEREVODNOY'
           OR v_game.phase <> 'WAIT_DEFENSE' THEN
            fail(-20747, 'Сейчас перевод атаки недоступен.');
        END IF;
        IF v_game.current_actor_seat_no <> v_game_player.seat_no
           OR v_game.defender_seat_no <> v_game_player.seat_no
           OR v_game_player.player_status <> 'ACTIVE' THEN
            fail(-20748, 'Перевести атаку может только текущий защитник.');
        END IF;

        SELECT *
        INTO v_round
        FROM durak_round
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND round_status = 'ACTIVE';

        IF v_round.defense_started = 'Y' THEN
            fail(-20749, 'После начала защиты перевод запрещён.');
        END IF;

        SELECT COUNT(*)
        INTO v_pair_count
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        IF v_pair_count = 0 THEN
            fail(-20750, 'На столе нет атаки для перевода.');
        END IF;

        v_new_defender := durak_rules.next_active_seat(
            p_game_id,
            v_game.defender_seat_no
        );

        IF v_new_defender IS NULL THEN
            fail(-20751, 'Нет следующего активного игрока для перевода.');
        END IF;

        SELECT COUNT(*)
        INTO v_already_attacked
        FROM durak_table_pair
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no
          AND attacking_seat_no = v_new_defender;

        IF v_already_attacked > 0 THEN
            fail(-20752, 'Нельзя перевести атаку обратно на уже атаковавшего игрока.');
        END IF;

        SELECT hand_count
        INTO v_new_hand_count
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND seat_no = v_new_defender
          AND player_status = 'ACTIVE';

        IF v_new_hand_count < 1 THEN
            fail(-20753, 'У следующего игрока нет карт для защиты.');
        END IF;

        v_new_limit := game_attack_limit(
            p_game_id,
            v_game.max_pairs,
            v_new_hand_count,
            v_game.limit_by_defender_hand
        );

        IF v_pair_count + 1 > v_new_limit THEN
            fail(-20754, 'Перевод превысит лимит карт нового защитника.');
        END IF;

        v_card_id := find_hand_card(
            p_game_id,
            v_game_player.seat_no,
            p_card_code
        );

        IF durak_rules.rank_present_on_table(
            p_game_id,
            v_game.current_round_no,
            v_card_id
        ) = 0 THEN
            fail(-20755, 'Для перевода нужна карта того же достоинства.');
        END IF;

        v_pair_no := v_pair_count + 1;

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'TRANSFER',
            p_message         => 'Защитник перевёл атаку с места '
                || v_game_player.seat_no || ' на место ' || v_new_defender || '.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => g_action_source,
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no,
            p_card_id         => v_card_id,
            p_target_pair_no  => v_pair_no,
            p_target_seat_no  => v_new_defender
        );

        move_hand_card_to_table(
            p_game_id => p_game_id,
            p_seat_no => v_game_player.seat_no,
            p_card_id => v_card_id,
            p_pair_no => v_pair_no,
            p_zone => 'ATTACK',
            p_event_id => v_event_id
        );

        INSERT INTO durak_table_pair (
            game_id,
            round_no,
            pair_no,
            attack_card_id,
            attacking_seat_no,
            attack_event_no
        ) VALUES (
            p_game_id,
            v_game.current_round_no,
            v_pair_no,
            v_card_id,
            v_game_player.seat_no,
            v_event_no
        );

        UPDATE durak_round
        SET defender_seat_no = v_new_defender,
            defender_hand_at_start = v_new_hand_count,
            attack_limit = v_new_limit,
            transfer_count = transfer_count + 1,
            consecutive_passes = 0,
            throw_cursor_seat_no = primary_attacker_seat_no
        WHERE game_id = p_game_id
          AND round_no = v_game.current_round_no;

        UPDATE durak_game
        SET defender_seat_no = v_new_defender,
            current_actor_seat_no = v_new_defender,
            phase = 'WAIT_DEFENSE'
        WHERE game_id = p_game_id;

        touch_game(p_game_id, p_player_id);
        finalize_event_state(p_game_id, v_event_id);
    END transfer_attack;

    PROCEDURE add_bot (
        p_actor_player_id IN NUMBER,
        p_game_id         IN NUMBER,
        p_bot_level       IN VARCHAR2,
        p_bot_player_id   OUT NUMBER,
        p_seat_no         OUT NUMBER
    ) IS
        v_game        durak_game%ROWTYPE;
        v_actor       durak_game_player%ROWTYPE;
        v_level       VARCHAR2(10) := UPPER(TRIM(p_bot_level));
        v_display_name VARCHAR2(100);
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_actor_player_id, v_actor);

        IF v_game.game_status <> 'LOBBY' THEN
            fail(-20759, 'Добавить бота можно только до запуска партии.');
        END IF;
        IF v_actor.is_creator <> 'Y' THEN
            fail(-20760, 'Добавлять ботов может только создатель партии.');
        END IF;
        IF v_level IS NULL OR v_level NOT IN ('EASY', 'NORMAL', 'HARD') THEN
            fail(-20761, 'Уровень бота должен быть EASY, NORMAL или HARD.');
        END IF;

        p_bot_player_id := durak_id_seq.NEXTVAL;
        v_display_name := 'Бот ' || INITCAP(LOWER(v_level))
            || ' #' || p_bot_player_id;

        INSERT INTO durak_player (
            player_id,
            db_username,
            display_name,
            player_type,
            bot_level
        ) VALUES (
            p_bot_player_id,
            NULL,
            v_display_name,
            'BOT',
            v_level
        );

        join_game(p_bot_player_id, p_game_id, p_seat_no);

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'BOT_ADDED',
            p_message         => v_display_name || ' добавлен на место ' || p_seat_no || '.',
            p_source          => 'SYSTEM',
            p_actor_player_id => p_actor_player_id,
            p_actor_seat_no   => v_actor.seat_no,
            p_target_seat_no  => p_seat_no
        );
    END add_bot;

    PROCEDURE execute_bot_action (
        p_bot_player_id IN NUMBER,
        p_game_id       IN NUMBER,
        p_action_type   IN VARCHAR2,
        p_card_code     IN VARCHAR2 DEFAULT NULL,
        p_pair_no       IN NUMBER DEFAULT NULL
    ) IS
        v_game            durak_game%ROWTYPE;
        v_game_player     durak_game_player%ROWTYPE;
        v_player          durak_player%ROWTYPE;
        v_action          VARCHAR2(30) := UPPER(TRIM(p_action_type));
        v_previous_source durak_event.event_source%TYPE := g_action_source;
    BEGIN
        require_player(p_bot_player_id, v_player);
        IF v_player.player_type <> 'BOT' THEN
            fail(-20762, 'Автоматическое действие разрешено только ботам.');
        END IF;

        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_bot_player_id, v_game_player);

        IF v_action IS NULL
           OR v_action NOT IN ('ATTACK', 'DEFEND', 'THROW_IN', 'PASS', 'TAKE', 'TRANSFER') THEN
            fail(-20763, 'Неизвестное действие бота.');
        END IF;

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'BOT_DECISION',
            p_message         => 'Бот выбрал действие ' || v_action
                || CASE
                    WHEN p_card_code IS NOT NULL
                    THEN ' картой ' || UPPER(TRIM(p_card_code))
                    ELSE NULL
                END || '.',
            p_source          => 'BOT',
            p_actor_player_id => p_bot_player_id,
            p_actor_seat_no   => v_game_player.seat_no
        );

        g_action_source := 'BOT';
        CASE v_action
            WHEN 'ATTACK' THEN
                attack(p_bot_player_id, p_game_id, p_card_code);
            WHEN 'DEFEND' THEN
                defend(p_bot_player_id, p_game_id, p_card_code, p_pair_no);
            WHEN 'THROW_IN' THEN
                throw_in(p_bot_player_id, p_game_id, p_card_code);
            WHEN 'PASS' THEN
                pass_throw(p_bot_player_id, p_game_id);
            WHEN 'TAKE' THEN
                take_cards(p_bot_player_id, p_game_id);
            WHEN 'TRANSFER' THEN
                transfer_attack(p_bot_player_id, p_game_id, p_card_code);
        END CASE;
        g_action_source := v_previous_source;
    EXCEPTION
        WHEN OTHERS THEN
            g_action_source := v_previous_source;
            RAISE;
    END execute_bot_action;

    PROCEDURE heartbeat (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_game        durak_game%ROWTYPE;
        v_game_player durak_game_player%ROWTYPE;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status NOT IN ('LOBBY', 'ACTIVE') THEN
            fail(-20727, 'Партия уже завершена.');
        END IF;

        UPDATE durak_game
        SET last_activity_at = SYSTIMESTAMP
        WHERE game_id = p_game_id;

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'HEARTBEAT',
            p_message         => 'Активность пользователя подтверждена.',
            p_source          => 'MANUAL',
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no
        );
    END heartbeat;

    PROCEDURE cancel_game (
        p_player_id IN NUMBER,
        p_game_id   IN NUMBER
    ) IS
        v_game        durak_game%ROWTYPE;
        v_game_player durak_game_player%ROWTYPE;
    BEGIN
        lock_game(p_game_id, v_game);
        require_game_player(p_game_id, p_player_id, v_game_player);

        IF v_game.game_status <> 'LOBBY' THEN
            fail(-20728, 'Отменить можно только партию в лобби.');
        END IF;
        IF v_game_player.is_creator <> 'Y' THEN
            fail(-20729, 'Отменить партию может только её создатель.');
        END IF;

        UPDATE durak_game
        SET game_status = 'CANCELLED',
            phase = 'FINISHED',
            finish_reason = 'CANCELLED_BY_CREATOR',
            finished_at = SYSTIMESTAMP,
            last_activity_at = SYSTIMESTAMP,
            action_deadline_at = NULL,
            version_no = version_no + 1
        WHERE game_id = p_game_id;

        UPDATE durak_game_player
        SET player_status = 'LEFT',
            result_code = 'ABANDONED',
            exited_at = SYSTIMESTAMP
        WHERE game_id = p_game_id;

        append_simple_event(
            p_game_id         => p_game_id,
            p_event_type      => 'GAME_CANCELLED',
            p_message         => 'Создатель отменил партию.',
            p_source          => 'MANUAL',
            p_actor_player_id => p_player_id,
            p_actor_seat_no   => v_game_player.seat_no
        );

        release_sessions(p_game_id);
    END cancel_game;

    PROCEDURE process_timeout (
        p_game_id IN NUMBER
    ) IS
        v_game            durak_game%ROWTYPE;
        v_actor_player_id NUMBER;
        v_card_code       VARCHAR2(3);
        v_event_id        NUMBER;
        v_event_no        NUMBER;
        v_previous_source durak_event.event_source%TYPE := g_action_source;
    BEGIN
        lock_game(p_game_id, v_game);

        IF v_game.game_status <> 'ACTIVE'
           OR v_game.action_deadline_at IS NULL
           OR v_game.action_deadline_at > SYSTIMESTAMP THEN
            RETURN;
        END IF;

        SELECT player_id
        INTO v_actor_player_id
        FROM durak_game_player
        WHERE game_id = p_game_id
          AND seat_no = v_game.current_actor_seat_no
          AND player_status = 'ACTIVE';

        append_event(
            p_game_id         => p_game_id,
            p_event_type      => 'TIMEOUT',
            p_message         => 'Истёк лимит действия для места '
                || v_game.current_actor_seat_no || ' в фазе '
                || v_game.phase || '.',
            p_event_id        => v_event_id,
            p_event_no        => v_event_no,
            p_source          => 'TIMEOUT',
            p_actor_player_id => v_actor_player_id,
            p_actor_seat_no   => v_game.current_actor_seat_no
        );

        g_action_source := 'TIMEOUT';

        CASE v_game.phase
            WHEN 'WAIT_ATTACK' THEN
                SELECT card_code
                INTO v_card_code
                FROM (
                    SELECT c.card_code
                    FROM durak_game_card gc
                    JOIN durak_card c ON c.card_id = gc.card_id
                    WHERE gc.game_id = p_game_id
                      AND gc.card_zone = 'HAND'
                      AND gc.owner_seat_no = v_game.current_actor_seat_no
                    ORDER BY
                        CASE WHEN c.suit_code = v_game.trump_suit THEN 1 ELSE 0 END,
                        c.rank_value,
                        c.suit_code
                )
                WHERE ROWNUM = 1;

                attack(v_actor_player_id, p_game_id, v_card_code);
            WHEN 'WAIT_DEFENSE' THEN
                take_cards(v_actor_player_id, p_game_id);
            WHEN 'WAIT_THROW' THEN
                pass_throw(v_actor_player_id, p_game_id);
            WHEN 'TAKE_THROW' THEN
                pass_throw(v_actor_player_id, p_game_id);
            ELSE
                fail(-20756, 'Для текущей фазы не определено действие по тайм-ауту.');
        END CASE;

        finalize_event_state(p_game_id, v_event_id);

        g_action_source := v_previous_source;
    EXCEPTION
        WHEN OTHERS THEN
            g_action_source := v_previous_source;
            RAISE;
    END process_timeout;

    PROCEDURE expire_idle_game (
        p_game_id IN NUMBER
    ) IS
        v_game durak_game%ROWTYPE;
    BEGIN
        lock_game(p_game_id, v_game);

        IF v_game.game_status NOT IN ('LOBBY', 'ACTIVE') THEN
            RETURN;
        END IF;

        IF v_game.last_activity_at >
           SYSTIMESTAMP - NUMTODSINTERVAL(v_game.idle_timeout_min, 'MINUTE') THEN
            RETURN;
        END IF;

        UPDATE durak_game_player
        SET player_status = 'LEFT',
            result_code = 'ABANDONED',
            exited_at = SYSTIMESTAMP
        WHERE game_id = p_game_id
          AND player_status IN ('WAITING', 'ACTIVE');

        UPDATE durak_game
        SET game_status = 'EXPIRED',
            phase = 'FINISHED',
            current_actor_seat_no = NULL,
            action_deadline_at = NULL,
            finish_reason = 'IDLE_TIMEOUT',
            finished_at = SYSTIMESTAMP,
            last_activity_at = SYSTIMESTAMP,
            version_no = version_no + 1
        WHERE game_id = p_game_id;

        append_simple_event(
            p_game_id    => p_game_id,
            p_event_type => 'IDLE_TIMEOUT',
            p_message    => 'Партия автоматически завершена из-за длительного простоя.',
            p_source     => 'TIMEOUT'
        );

        durak_tournament_pkg.record_game_result(p_game_id);
        release_sessions(p_game_id);
    END expire_idle_game;

    PROCEDURE log_rejection (
        p_game_id       IN NUMBER,
        p_player_id     IN NUMBER,
        p_db_username   IN VARCHAR2,
        p_action_type   IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_message IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO durak_error (
            error_id,
            game_id,
            player_id,
            db_username,
            action_type,
            error_code,
            error_message
        ) VALUES (
            durak_id_seq.NEXTVAL,
            p_game_id,
            p_player_id,
            UPPER(SUBSTR(p_db_username, 1, 128)),
            UPPER(SUBSTR(NVL(p_action_type, 'UNKNOWN'), 1, 30)),
            NVL(p_error_code, -20000),
            SUBSTR(NVL(p_error_message, 'Неизвестная ошибка'), 1, 1000)
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END log_rejection;
END durak_engine;
/

SHOW ERRORS PACKAGE durak_engine
SHOW ERRORS PACKAGE BODY durak_engine
